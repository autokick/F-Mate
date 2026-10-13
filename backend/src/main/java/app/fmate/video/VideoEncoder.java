package app.fmate.video;

import app.fmate.config.FmateProperties;
import app.fmate.media.StorageService;
import app.fmate.notification.NotificationService;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.List;
import java.util.concurrent.TimeUnit;
import java.util.stream.Stream;

/**
 * ffmpeg 기반 인코딩 워커 (ENCODER_ENABLED=true 이고 서버에 ffmpeg/ffprobe 가 있을 때).
 *  1) UPLOADED 영상을 하나 잡아 PROCESSING 으로 (SKIP LOCKED → 여러 서버에서도 중복 처리 없음)
 *  2) ffprobe 로 길이·해상도 확인 (1~90초)
 *  3) 720x1280 안쪽으로 맞춘 H.264/AAC HLS(4초 세그먼트) + 썸네일 생성
 *  4) public 버킷 hls/{videoId}/ 에 올리고 READY → 게시물 자동 공개(DB 트리거) → 작성자 알림
 * 일시 오류는 최대 3회 재시도, 길이·형식 문제는 바로 실패 처리.
 */
@Component
public class VideoEncoder {

    private static final Logger log = LoggerFactory.getLogger(VideoEncoder.class);
    private static final String RETRY = "retry: ";

    private final JdbcTemplate jdbc;
    private final StorageService storage;
    private final FmateProperties.Encoder cfg;
    private final NotificationService notifications;
    private final ObjectMapper mapper;

    public VideoEncoder(JdbcTemplate jdbc, StorageService storage, FmateProperties props,
                        NotificationService notifications, ObjectMapper mapper) {
        this.jdbc = jdbc;
        this.storage = storage;
        this.cfg = props.encoder();
        this.notifications = notifications;
        this.mapper = mapper;
    }

    private record Job(long id, long ownerId, String key) {
    }

    @Scheduled(fixedDelay = 10_000, initialDelay = 20_000)
    public void run() {
        if (!cfg.enabled() || !storage.isConfigured()) return;
        List<Job> jobs = jdbc.query("""
                UPDATE videos SET status = 'PROCESSING', encode_attempts = encode_attempts + 1
                 WHERE id = (SELECT id FROM videos
                              WHERE status = 'UPLOADED'
                                 OR (status = 'FAILED' AND encode_attempts < 3 AND failure_reason LIKE 'retry: %')
                              ORDER BY id LIMIT 1 FOR UPDATE SKIP LOCKED)
                RETURNING id, owner_id, source_object_key""",
                (rs, i) -> new Job(rs.getLong(1), rs.getLong(2), rs.getString(3)));
        if (jobs.isEmpty()) return;
        encode(jobs.get(0));
    }

    private void encode(Job job) {
        Path dir = null;
        try {
            dir = Files.createTempDirectory("fmate-video-" + job.id() + "-");
            Path input = dir.resolve("source");
            storage.download(storage.rawBucket(), job.key(), input);

            Probe probe = probe(input);
            if (probe == null) {
                fail(job, "probe failed", false);
                return;
            }
            if (!probe.hasVideo()) {
                fail(job, "no video stream", false);
                return;
            }
            if (probe.durationMs() > VideoService.MAX_DURATION_MS + 500) {
                fail(job, "too long: " + probe.durationMs(), false);
                return;
            }
            if (probe.durationMs() < 1000) {
                fail(job, "too short: " + probe.durationMs(), false);
                return;
            }

            Path out = Files.createDirectory(dir.resolve("out"));
            String scale = "scale=w=720:h=1280:force_original_aspect_ratio=decrease,scale=trunc(iw/2)*2:trunc(ih/2)*2";
            run(List.of(cfg.ffmpegPath(), "-y", "-hide_banner", "-loglevel", "error", "-i", input.toString(),
                    "-vf", scale, "-c:v", "libx264", "-preset", "veryfast", "-crf", "23", "-profile:v", "main",
                    "-pix_fmt", "yuv420p", "-c:a", "aac", "-b:a", "128k", "-ac", "2",
                    "-f", "hls", "-hls_time", "4", "-hls_playlist_type", "vod",
                    "-hls_segment_filename", out.resolve("seg_%03d.ts").toString(),
                    out.resolve("index.m3u8").toString()), 600);
            String ss = probe.durationMs() > 2000 ? "1" : "0";
            run(List.of(cfg.ffmpegPath(), "-y", "-hide_banner", "-loglevel", "error", "-ss", ss, "-i", input.toString(),
                    "-frames:v", "1", "-vf", scale, "-q:v", "3", out.resolve("thumb.jpg").toString()), 120);

            String prefix = "hls/" + job.id() + "/";
            List<Path> files;
            try (Stream<Path> s = Files.list(out)) {
                files = s.toList();
            }
            for (Path f : files) {
                String name = f.getFileName().toString();
                String type = name.endsWith(".m3u8") ? "application/vnd.apple.mpegurl"
                        : name.endsWith(".ts") ? "video/mp2t" : "image/jpeg";
                String cache = name.endsWith(".m3u8") ? "public, max-age=60" : "public, max-age=31536000, immutable";
                storage.upload(storage.publicBucket(), prefix + name, f, type, cache);
            }
            int n = jdbc.update("""
                    UPDATE videos SET status = 'READY', hls_manifest_key = ?, thumbnail_key = ?, duration_ms = ?,
                           width = ?, height = ?, failure_reason = NULL
                     WHERE id = ? AND status = 'PROCESSING'""",
                    prefix + "index.m3u8", prefix + "thumb.jpg", Math.min(probe.durationMs(), VideoService.MAX_DURATION_MS),
                    probe.width(), probe.height(), job.id());
            if (n == 1) {
                storage.delete(storage.rawBucket(), job.key());   // 원본은 보관하지 않는다 (비용·개인정보)
                notifications.notify(job.ownerId(), "VIDEO_READY", null, "VIDEO", job.id(),
                        "영상이 게시되었어요", "업로드한 하이라이트 영상 처리가 끝났어요", null);
            }
        } catch (Exception e) {
            log.warn("video {} encode error: {}", job.id(), e.toString());
            fail(job, e.getClass().getSimpleName(), true);
        } finally {
            if (dir != null) deleteRecursively(dir);
        }
    }

    /** 삭제된 영상(게시물 삭제·탈퇴·업로드 취소)의 원본·HLS 파일을 스토리지에서 지운다 */
    @Scheduled(fixedDelay = 600_000, initialDelay = 120_000)
    public void cleanupDeleted() {
        if (!storage.isConfigured()) return;
        List<Job> deleted = jdbc.query("""
                SELECT id, owner_id, source_object_key FROM videos
                 WHERE status IN ('DELETED','FAILED') AND COALESCE(failure_reason, '') <> 'files-deleted'
                   AND (status = 'DELETED' OR (failure_reason NOT LIKE 'retry: %' OR encode_attempts >= 3))
                 ORDER BY id LIMIT 50""",
                (rs, i) -> new Job(rs.getLong(1), rs.getLong(2), rs.getString(3)));
        for (Job v : deleted) {
            try {
                storage.delete(storage.rawBucket(), v.key());
                storage.deletePrefix(storage.publicBucket(), "hls/" + v.id() + "/");
                jdbc.update("UPDATE videos SET failure_reason = 'files-deleted' WHERE id = ?", v.id());
            } catch (Exception e) {
                log.warn("video {} file cleanup failed: {}", v.id(), e.getClass().getSimpleName());
            }
        }
    }

    private void fail(Job job, String reason, boolean retryable) {
        String r = (retryable ? RETRY : "") + reason;
        jdbc.update("UPDATE videos SET status = 'FAILED', failure_reason = ? WHERE id = ? AND status = 'PROCESSING'",
                r.length() > 300 ? r.substring(0, 300) : r, job.id());
        Integer attempts = jdbc.queryForObject("SELECT encode_attempts FROM videos WHERE id = ?", Integer.class, job.id());
        boolean finalFailure = !retryable || attempts == null || attempts >= 3;
        if (finalFailure) {
            notifications.notify(job.ownerId(), "VIDEO_FAILED", null, "VIDEO", job.id(), "영상을 올리지 못했어요",
                    VideoService.userFacingReason(reason), null);
        }
    }

    private record Probe(boolean hasVideo, int durationMs, Integer width, Integer height) {
    }

    private Probe probe(Path input) {
        try {
            String json = run(List.of(cfg.ffprobePath(), "-v", "error", "-print_format", "json", "-show_format",
                    "-show_streams", input.toString()), 60);
            JsonNode root = mapper.readTree(json);
            boolean hasVideo = false;
            Integer w = null;
            Integer h = null;
            for (JsonNode s : root.path("streams")) {
                if ("video".equals(s.path("codec_type").asText())) {
                    hasVideo = true;
                    w = s.path("width").asInt();
                    h = s.path("height").asInt();
                    // 회전 메타데이터(세로 촬영)가 있으면 가로·세로를 바꿔 기록
                    int rotate = Math.abs(s.path("tags").path("rotate").asInt(0));
                    for (JsonNode sd : s.path("side_data_list")) {
                        if (sd.has("rotation")) rotate = Math.abs(sd.path("rotation").asInt(0));
                    }
                    if (rotate == 90 || rotate == 270) {
                        Integer t = w;
                        w = h;
                        h = t;
                    }
                    break;
                }
            }
            double seconds = root.path("format").path("duration").asDouble(0);
            return new Probe(hasVideo, (int) Math.round(seconds * 1000), w, h);
        } catch (Exception e) {
            log.warn("ffprobe failed: {}", e.toString());
            return null;
        }
    }

    private static String run(List<String> cmd, int timeoutSeconds) throws IOException, InterruptedException {
        Process p = new ProcessBuilder(new ArrayList<>(cmd)).redirectErrorStream(true).start();
        byte[] output;
        try (var in = p.getInputStream()) {
            output = in.readAllBytes();
        }
        if (!p.waitFor(timeoutSeconds, TimeUnit.SECONDS)) {
            p.destroyForcibly();
            throw new IOException("process timeout: " + cmd.get(0));
        }
        if (p.exitValue() != 0) {
            String msg = new String(output, StandardCharsets.UTF_8);
            throw new IOException(cmd.get(0) + " exit " + p.exitValue() + ": " + (msg.length() > 200 ? msg.substring(0, 200) : msg));
        }
        return new String(output, StandardCharsets.UTF_8);
    }

    private static void deleteRecursively(Path dir) {
        try (Stream<Path> s = Files.walk(dir)) {
            s.sorted(Comparator.reverseOrder()).forEach(p -> {
                try {
                    Files.deleteIfExists(p);
                } catch (IOException ignored) {
                    // 임시 파일 정리 실패는 무시
                }
            });
        } catch (IOException ignored) {
            // 무시
        }
    }
}
