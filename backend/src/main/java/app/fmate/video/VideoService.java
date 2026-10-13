package app.fmate.video;

import app.fmate.common.ApiException;
import app.fmate.common.RateLimiter;
import app.fmate.config.FmateProperties;
import app.fmate.media.StorageService;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;

import java.time.Duration;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;

/**
 * 영상 업로드. 앱 → presigned PUT → 스토리지(raw 버킷) 직접 업로드. API 서버는 파일을 중계하지 않는다.
 * 업로드 완료 통지 후 인코더(VideoEncoder)가 HLS + 썸네일을 만들어 public 버킷/CDN 으로 제공한다.
 */
@Service
public class VideoService {

    public static final long MAX_BYTES = 500L * 1024 * 1024;
    public static final int MAX_DURATION_MS = 90_000;
    private static final Set<String> TYPES = Set.of("video/mp4", "video/quicktime");

    private final JdbcTemplate jdbc;
    private final StorageService storage;
    private final FmateProperties props;
    private final RateLimiter limiter;

    public VideoService(JdbcTemplate jdbc, StorageService storage, FmateProperties props, RateLimiter limiter) {
        this.jdbc = jdbc;
        this.storage = storage;
        this.props = props;
        this.limiter = limiter;
    }

    public record UploadTicket(long videoId, String uploadUrl, String method, Map<String, String> headers,
                               long maxBytes, int maxDurationSeconds) {
    }

    public UploadTicket createUpload(long userId, boolean emailVerified, String contentType, long sizeBytes) {
        if (!emailVerified) throw ApiException.forbidden("EMAIL_NOT_VERIFIED");
        storage.ensureConfigured();
        if (!props.encoder().enabled()) throw ApiException.unavailable("MEDIA_NOT_CONFIGURED");
        if (!TYPES.contains(contentType)) throw ApiException.badRequest("UNSUPPORTED_MEDIA", "mp4 또는 mov 영상만 올릴 수 있어요");
        if (sizeBytes <= 0 || sizeBytes > MAX_BYTES) throw ApiException.badRequest("FILE_TOO_LARGE", "영상은 500MB 이하만 올릴 수 있어요");
        limiter.check("video-upload", Long.toString(userId), 20, Duration.ofDays(1));

        String ext = "video/quicktime".equals(contentType) ? "mov" : "mp4";
        String key = "videos/raw/" + userId + "/" + UUID.randomUUID() + "." + ext;
        Long id = jdbc.queryForObject("""
                INSERT INTO videos (owner_id, source_object_key, content_type, declared_size_bytes, upload_expires_at)
                VALUES (?, ?, ?, ?, now() + interval '2 hours') RETURNING id""",
                Long.class, userId, key, contentType, sizeBytes);
        String url = storage.presignPut(storage.rawBucket(), key, contentType, Duration.ofHours(2));
        return new UploadTicket(id, url, "PUT", Map.of("Content-Type", contentType), MAX_BYTES, MAX_DURATION_MS / 1000);
    }

    /** 업로드 완료 통지: 실제 파일 존재·크기를 스토리지에서 확인 */
    public VideoStatus complete(long userId, long videoId) {
        Map<String, Object> v = owned(userId, videoId);
        if (!"UPLOAD_PENDING".equals(v.get("status"))) return status(userId, videoId);
        String key = (String) v.get("source_object_key");
        Long size = storage.size(storage.rawBucket(), key).orElse(null);
        if (size == null) throw ApiException.badRequest("UPLOAD_NOT_FOUND", "업로드된 영상을 찾을 수 없어요. 다시 올려 주세요");
        if (size > MAX_BYTES) {
            storage.delete(storage.rawBucket(), key);
            jdbc.update("UPDATE videos SET status = 'FAILED', failure_reason = 'file too large' WHERE id = ?", videoId);
            throw ApiException.badRequest("FILE_TOO_LARGE");
        }
        jdbc.update("UPDATE videos SET status = 'UPLOADED', actual_size_bytes = ? WHERE id = ? AND status = 'UPLOAD_PENDING'",
                size, videoId);
        return status(userId, videoId);
    }

    public void abort(long userId, long videoId) {
        Map<String, Object> v = owned(userId, videoId);
        if ("DELETED".equals(v.get("status"))) return;
        if (v.get("post_id") != null) throw ApiException.conflict("INVALID_STATE", "게시된 영상은 게시물을 삭제해 주세요");
        jdbc.update("UPDATE videos SET status = 'DELETED' WHERE id = ?", videoId);
    }

    public record VideoStatus(long id, String status, String failureReason, String hlsUrl, String thumbnailUrl,
                              Integer durationMs, Long postId) {
    }

    public VideoStatus status(long userId, long videoId) {
        owned(userId, videoId);
        return jdbc.queryForObject("""
                SELECT id, status, failure_reason, hls_manifest_key, thumbnail_key, duration_ms, post_id
                  FROM videos WHERE id = ?""",
                (rs, i) -> new VideoStatus(rs.getLong(1), rs.getString(2), userFacingReason(rs.getString(3)),
                        storage.publicUrl(rs.getString(4)), storage.publicUrl(rs.getString(5)),
                        (Integer) rs.getObject(6), (Long) rs.getObject(7)), videoId);
    }

    private Map<String, Object> owned(long userId, long videoId) {
        List<Map<String, Object>> rows = jdbc.queryForList(
                "SELECT owner_id, status, source_object_key, post_id FROM videos WHERE id = ?", videoId);
        if (rows.isEmpty() || ((Number) rows.get(0).get("owner_id")).longValue() != userId) throw ApiException.notFound();
        return rows.get(0);
    }

    static String userFacingReason(String internal) {
        if (internal == null) return null;
        if (internal.startsWith("too long")) return "영상 길이는 90초 이하여야 해요";
        if (internal.startsWith("too short")) return "영상 길이는 1초 이상이어야 해요";
        if (internal.startsWith("no video stream") || internal.startsWith("probe failed")) return "영상 파일을 읽을 수 없어요";
        if (internal.startsWith("upload expired")) return "업로드 시간이 지났어요. 다시 올려 주세요";
        return "영상 처리에 실패했어요. 다시 올려 주세요";
    }
}
