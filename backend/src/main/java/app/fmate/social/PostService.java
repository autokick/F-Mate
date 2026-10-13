package app.fmate.social;

import app.fmate.common.ApiException;
import app.fmate.media.MediaController;
import app.fmate.media.MediaKeys;
import app.fmate.media.StorageService;
import app.fmate.notification.NotificationService;
import app.fmate.user.UserSummary;
import org.springframework.jdbc.core.namedparam.MapSqlParameterSource;
import org.springframework.jdbc.core.namedparam.NamedParameterJdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.OffsetDateTime;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * 게시물·피드. 열람 권한은 DB 함수 can_view_post(차단·공개범위·비공개 계정·삭제 상태) 하나로 판단한다.
 */
@Service
public class PostService {

    private static final Pattern HASHTAG = Pattern.compile("#([A-Za-z0-9가-힣_]{1,50})");
    private static final Set<String> VISIBILITY = Set.of("PUBLIC", "FOLLOWERS", "PRIVATE");

    private final NamedParameterJdbcTemplate db;
    private final StorageService storage;
    private final MediaKeys mediaKeys;
    private final NotificationService notifications;

    public PostService(NamedParameterJdbcTemplate db, StorageService storage, MediaKeys mediaKeys,
                       NotificationService notifications) {
        this.db = db;
        this.storage = storage;
        this.mediaKeys = mediaKeys;
        this.notifications = notifications;
    }

    // ------------------------------------------------------------- 모델

    public record Image(String url, Integer width, Integer height) {
    }

    public record Video(long id, String status, String hlsUrl, String thumbnailUrl, Integer durationMs,
                        Integer width, Integer height) {
    }

    public record VenueTag(long id, String name) {
    }

    public record PostView(long id, UserSummary author, String kind, String caption, String visibility,
                           boolean isHighlight, VenueTag venue, String status, List<Image> images, Video video,
                           int likeCount, int commentCount, boolean likedByMe, boolean savedByMe,
                           OffsetDateTime createdAt) {
    }

    public record FeedPage(List<PostView> items, Long nextCursor) {
    }

    public record ImageInput(String objectKey, Integer width, Integer height) {
    }

    public record PostInput(String kind, String caption, String visibility, Boolean isHighlight, Long venueId,
                            List<ImageInput> images, Long videoId) {
    }

    // ------------------------------------------------------------- 작성·수정·삭제

    @Transactional
    public PostView create(long userId, boolean emailVerified, PostInput in) {
        if (!emailVerified) throw ApiException.forbidden("EMAIL_NOT_VERIFIED");
        String kind = in.kind() == null ? "" : in.kind();
        String visibility = in.visibility() == null ? "PUBLIC" : in.visibility();
        if (!VISIBILITY.contains(visibility)) throw ApiException.badRequest("VALIDATION_FAILED");
        String caption = in.caption() == null ? null : in.caption().strip();
        if (caption != null && caption.length() > 2200) throw ApiException.badRequest("VALIDATION_FAILED", "글은 2,200자까지 쓸 수 있어요");
        if (in.venueId() != null) {
            Integer n = db.queryForObject("SELECT count(*)::int FROM futsal_venues WHERE id = :id AND verification_status = 'VERIFIED'",
                    new MapSqlParameterSource("id", in.venueId()), Integer.class);
            if (n == null || n == 0) throw ApiException.badRequest("VALIDATION_FAILED");
        }

        String status = "ACTIVE";
        switch (kind) {
            case "TEXT" -> {
                if (caption == null || caption.isEmpty()) throw ApiException.badRequest("VALIDATION_FAILED", "내용을 입력해 주세요");
            }
            case "PHOTO" -> {
                if (in.images() == null || in.images().isEmpty() || in.images().size() > 10) {
                    throw ApiException.badRequest("VALIDATION_FAILED", "사진은 1~10장이에요");
                }
                for (ImageInput img : in.images()) {
                    mediaKeys.requireOwnedUpload(MediaController.Purpose.POST_IMAGE, userId, img.objectKey());
                }
            }
            case "VIDEO" -> {
                if (in.videoId() == null) throw ApiException.badRequest("VALIDATION_FAILED");
                Map<String, Object> v = videoOwned(userId, in.videoId());
                if (v.get("post_id") != null) throw ApiException.conflict("INVALID_STATE", "이미 게시된 영상이에요");
                String vs = (String) v.get("status");
                if (!Set.of("UPLOADED", "PROCESSING", "READY").contains(vs)) {
                    throw ApiException.conflict("INVALID_STATE", "업로드가 끝난 영상만 올릴 수 있어요");
                }
                status = "READY".equals(vs) ? "ACTIVE" : "PENDING_MEDIA";
            }
            default -> throw ApiException.badRequest("VALIDATION_FAILED");
        }

        MapSqlParameterSource p = new MapSqlParameterSource()
                .addValue("author", userId).addValue("kind", kind).addValue("caption", caption)
                .addValue("visibility", visibility).addValue("highlight", Boolean.TRUE.equals(in.isHighlight()))
                .addValue("venue", in.venueId()).addValue("status", status);
        Long postId = db.queryForObject("""
                INSERT INTO posts (author_id, kind, caption, visibility, is_highlight, venue_id, status)
                VALUES (:author, :kind, :caption, :visibility, :highlight, :venue, :status) RETURNING id""", p, Long.class);

        if ("PHOTO".equals(kind)) {
            for (int i = 0; i < in.images().size(); i++) {
                ImageInput img = in.images().get(i);
                db.update("""
                        INSERT INTO post_media (post_id, object_key, content_type, width, height, sort_order)
                        VALUES (:post, :key, :ct, :w, :h, :ord)""",
                        new MapSqlParameterSource("post", postId).addValue("key", img.objectKey())
                                .addValue("ct", contentTypeOf(img.objectKey())).addValue("w", img.width())
                                .addValue("h", img.height()).addValue("ord", i));
            }
        }
        if ("VIDEO".equals(kind)) {
            db.update("UPDATE videos SET post_id = :post WHERE id = :video",
                    new MapSqlParameterSource("post", postId).addValue("video", in.videoId()));
        }
        syncHashtags(postId, caption);
        return get(userId, postId);
    }

    @Transactional
    public PostView update(long userId, long postId, PostInput in) {
        Map<String, Object> post = authorPost(userId, postId);
        MapSqlParameterSource p = new MapSqlParameterSource("id", postId);
        if (in.caption() != null) {
            String caption = in.caption().strip();
            if (caption.length() > 2200) throw ApiException.badRequest("VALIDATION_FAILED");
            if ("TEXT".equals(post.get("kind")) && caption.isEmpty()) throw ApiException.badRequest("VALIDATION_FAILED");
            db.update("UPDATE posts SET caption = :c WHERE id = :id", p.addValue("c", caption.isEmpty() ? null : caption));
            syncHashtags(postId, caption);
        }
        if (in.visibility() != null) {
            if (!VISIBILITY.contains(in.visibility())) throw ApiException.badRequest("VALIDATION_FAILED");
            db.update("UPDATE posts SET visibility = :v WHERE id = :id", p.addValue("v", in.visibility()));
        }
        if (in.isHighlight() != null) {
            db.update("UPDATE posts SET is_highlight = :h WHERE id = :id", p.addValue("h", in.isHighlight()));
        }
        return get(userId, postId);
    }

    /** 작성자 본인 또는 모더레이터 삭제. 파일 정리는 MediaCleanupJob 이 수행. */
    @Transactional
    public void delete(long userId, boolean moderator, long postId) {
        List<Map<String, Object>> rows = db.queryForList("SELECT author_id, status FROM posts WHERE id = :id",
                new MapSqlParameterSource("id", postId));
        if (rows.isEmpty() || "DELETED".equals(rows.get(0).get("status"))) throw ApiException.notFound();
        long author = ((Number) rows.get(0).get("author_id")).longValue();
        if (author != userId && !moderator) throw ApiException.forbidden("FORBIDDEN");
        List<String> keys = db.queryForList("SELECT object_key FROM post_media WHERE post_id = :id",
                new MapSqlParameterSource("id", postId), String.class);
        db.update("UPDATE posts SET status = 'DELETED', deleted_at = now() WHERE id = :id", new MapSqlParameterSource("id", postId));
        db.update("DELETE FROM post_media WHERE post_id = :id", new MapSqlParameterSource("id", postId));
        db.update("UPDATE videos SET status = 'DELETED' WHERE post_id = :id AND status <> 'DELETED'", new MapSqlParameterSource("id", postId));
        storage.deletePublicQuietly(keys);
    }

    private Map<String, Object> authorPost(long userId, long postId) {
        List<Map<String, Object>> rows = db.queryForList(
                "SELECT author_id, kind, status FROM posts WHERE id = :id", new MapSqlParameterSource("id", postId));
        if (rows.isEmpty() || "DELETED".equals(rows.get(0).get("status"))) throw ApiException.notFound();
        if (((Number) rows.get(0).get("author_id")).longValue() != userId) throw ApiException.forbidden("FORBIDDEN");
        return rows.get(0);
    }

    private Map<String, Object> videoOwned(long userId, long videoId) {
        List<Map<String, Object>> rows = db.queryForList(
                "SELECT owner_id, status, post_id FROM videos WHERE id = :id", new MapSqlParameterSource("id", videoId));
        if (rows.isEmpty() || ((Number) rows.get(0).get("owner_id")).longValue() != userId) throw ApiException.notFound();
        return rows.get(0);
    }

    void syncHashtags(long postId, String caption) {
        db.update("DELETE FROM post_hashtags WHERE post_id = :id", new MapSqlParameterSource("id", postId));
        for (String tag : extractHashtags(caption)) {
            Long tagId = db.queryForObject("""
                    WITH ins AS (INSERT INTO hashtags (tag) VALUES (:tag) ON CONFLICT (tag) DO NOTHING RETURNING id)
                    SELECT id FROM ins UNION ALL SELECT id FROM hashtags WHERE tag = :tag LIMIT 1""",
                    new MapSqlParameterSource("tag", tag), Long.class);
            db.update("INSERT INTO post_hashtags (post_id, hashtag_id) VALUES (:p, :t) ON CONFLICT DO NOTHING",
                    new MapSqlParameterSource("p", postId).addValue("t", tagId));
        }
    }

    static List<String> extractHashtags(String caption) {
        if (caption == null) return List.of();
        Set<String> tags = new LinkedHashSet<>();
        Matcher m = HASHTAG.matcher(caption);
        while (m.find() && tags.size() < 20) tags.add(m.group(1));
        return new ArrayList<>(tags);
    }

    private static String contentTypeOf(String key) {
        String k = key.toLowerCase();
        if (k.endsWith(".png")) return "image/png";
        if (k.endsWith(".webp")) return "image/webp";
        if (k.endsWith(".heic")) return "image/heic";
        return "image/jpeg";
    }

    // ------------------------------------------------------------- 조회

    private static final String SELECT = """
            SELECT p.id, p.author_id, pr.nickname::text AS nickname, pr.avatar_object_key, p.kind, p.caption,
                   p.visibility, p.is_highlight, p.venue_id, v.name AS venue_name, p.status, p.like_count,
                   p.comment_count, p.created_at,
                   EXISTS (SELECT 1 FROM likes l WHERE l.post_id = p.id AND l.user_id = :viewer) AS liked,
                   EXISTS (SELECT 1 FROM saved_posts s WHERE s.post_id = p.id AND s.user_id = :viewer) AS saved
              FROM posts p
              JOIN user_profiles pr ON pr.user_id = p.author_id
              LEFT JOIN futsal_venues v ON v.id = p.venue_id
            """;

    private record Row(long id, long authorId, String nickname, String avatarKey, String kind, String caption,
                       String visibility, boolean highlight, Long venueId, String venueName, String status,
                       int likes, int comments, OffsetDateTime createdAt, boolean liked, boolean saved) {
    }

    private List<Row> rows(String sql, MapSqlParameterSource p) {
        return db.query(sql, p, (rs, i) -> new Row(rs.getLong("id"), rs.getLong("author_id"), rs.getString("nickname"),
                rs.getString("avatar_object_key"), rs.getString("kind"), rs.getString("caption"),
                rs.getString("visibility"), rs.getBoolean("is_highlight"), (Long) rs.getObject("venue_id"),
                rs.getString("venue_name"), rs.getString("status"), rs.getInt("like_count"), rs.getInt("comment_count"),
                rs.getObject("created_at", OffsetDateTime.class), rs.getBoolean("liked"), rs.getBoolean("saved")));
    }

    public PostView get(long viewerId, long postId) {
        MapSqlParameterSource p = new MapSqlParameterSource("viewer", viewerId).addValue("id", postId);
        List<Row> r = rows(SELECT + " WHERE p.id = :id AND can_view_post(:viewer, p.id)", p);
        if (r.isEmpty()) throw ApiException.notFound();
        return hydrate(r).get(0);
    }

    public FeedPage feed(long viewerId, String type, Long cursor, int limit) {
        int size = Math.min(Math.max(limit, 1), 30);
        MapSqlParameterSource p = new MapSqlParameterSource("viewer", viewerId).addValue("limit", size + 1)
                .addValue("cursor", cursor);
        String sql;
        switch (type == null ? "latest" : type) {
            case "following" -> sql = SELECT + """
                     WHERE p.status = 'ACTIVE' AND (:cursor::bigint IS NULL OR p.id < :cursor)
                       AND (p.author_id = :viewer OR p.author_id IN
                            (SELECT followee_id FROM follows WHERE follower_id = :viewer AND status = 'ACCEPTED'))
                       AND can_view_post(:viewer, p.id)
                     ORDER BY p.id DESC LIMIT :limit""";
            case "recommended" -> {
                // 최근 14일 공개 게시물을 반응(좋아요 + 댓글x2)과 시간 경과로 점수화. cursor 는 offset 으로 쓴다.
                p.addValue("offset", cursor == null ? 0 : cursor);
                sql = SELECT + """
                         WHERE p.status = 'ACTIVE' AND p.visibility = 'PUBLIC'
                           AND p.created_at > now() - interval '14 days'
                           AND can_view_post(:viewer, p.id)
                         ORDER BY (p.like_count + 2 * p.comment_count + 1)
                                  / power(extract(epoch FROM (now() - p.created_at)) / 3600 + 2, 1.5) DESC, p.id DESC
                         LIMIT :limit OFFSET :offset""";
                List<Row> r = rows(sql, p);
                boolean more = r.size() > size;
                long next = (cursor == null ? 0 : cursor) + size;
                return new FeedPage(hydrate(more ? r.subList(0, size) : r), more ? next : null);
            }
            default -> sql = SELECT + """
                     WHERE p.status = 'ACTIVE' AND p.visibility = 'PUBLIC' AND (:cursor::bigint IS NULL OR p.id < :cursor)
                       AND can_view_post(:viewer, p.id)
                     ORDER BY p.id DESC LIMIT :limit""";
        }
        return page(rows(sql, p), size);
    }

    /** 숏폼: 인코딩 완료된 공개 영상만 */
    public FeedPage shorts(long viewerId, Long cursor, int limit) {
        int size = Math.min(Math.max(limit, 1), 20);
        MapSqlParameterSource p = new MapSqlParameterSource("viewer", viewerId).addValue("limit", size + 1)
                .addValue("cursor", cursor);
        String sql = SELECT + """
                 WHERE p.status = 'ACTIVE' AND p.kind = 'VIDEO' AND (:cursor::bigint IS NULL OR p.id < :cursor)
                   AND EXISTS (SELECT 1 FROM videos vd WHERE vd.post_id = p.id AND vd.status = 'READY')
                   AND can_view_post(:viewer, p.id)
                 ORDER BY p.id DESC LIMIT :limit""";
        return page(rows(sql, p), size);
    }

    public FeedPage userPosts(long viewerId, long authorId, boolean highlightsOnly, Long cursor, int limit) {
        int size = Math.min(Math.max(limit, 1), 30);
        MapSqlParameterSource p = new MapSqlParameterSource("viewer", viewerId).addValue("author", authorId)
                .addValue("limit", size + 1).addValue("cursor", cursor).addValue("hl", highlightsOnly);
        String sql = SELECT + """
                 WHERE p.author_id = :author AND p.status IN ('ACTIVE','PENDING_MEDIA')
                   AND (:hl = false OR p.is_highlight) AND (:cursor::bigint IS NULL OR p.id < :cursor)
                   AND can_view_post(:viewer, p.id)
                 ORDER BY p.id DESC LIMIT :limit""";
        return page(rows(sql, p), size);
    }

    public FeedPage saved(long viewerId, Long cursor, int limit) {
        int size = Math.min(Math.max(limit, 1), 30);
        MapSqlParameterSource p = new MapSqlParameterSource("viewer", viewerId).addValue("limit", size + 1)
                .addValue("cursor", cursor);
        String sql = SELECT + """
                 JOIN saved_posts sp ON sp.post_id = p.id AND sp.user_id = :viewer
                 WHERE (:cursor::bigint IS NULL OR p.id < :cursor) AND can_view_post(:viewer, p.id)
                 ORDER BY p.id DESC LIMIT :limit""";
        return page(rows(sql, p), size);
    }

    public FeedPage hashtag(long viewerId, String tag, Long cursor, int limit) {
        int size = Math.min(Math.max(limit, 1), 30);
        MapSqlParameterSource p = new MapSqlParameterSource("viewer", viewerId).addValue("limit", size + 1)
                .addValue("cursor", cursor).addValue("tag", tag);
        String sql = SELECT + """
                 JOIN post_hashtags ph ON ph.post_id = p.id JOIN hashtags h ON h.id = ph.hashtag_id AND h.tag = :tag
                 WHERE p.status = 'ACTIVE' AND (:cursor::bigint IS NULL OR p.id < :cursor) AND can_view_post(:viewer, p.id)
                 ORDER BY p.id DESC LIMIT :limit""";
        return page(rows(sql, p), size);
    }

    private FeedPage page(List<Row> r, int size) {
        boolean more = r.size() > size;
        List<Row> items = more ? r.subList(0, size) : r;
        return new FeedPage(hydrate(items), more ? items.get(items.size() - 1).id() : null);
    }

    private List<PostView> hydrate(List<Row> rows) {
        if (rows.isEmpty()) return List.of();
        List<Long> ids = rows.stream().map(Row::id).toList();
        Map<Long, List<Image>> images = new HashMap<>();
        db.query("SELECT post_id, object_key, width, height FROM post_media WHERE post_id IN (:ids) ORDER BY post_id, sort_order",
                new MapSqlParameterSource("ids", ids), rs -> {
                    images.computeIfAbsent(rs.getLong(1), k -> new ArrayList<>())
                            .add(new Image(storage.publicUrl(rs.getString(2)), (Integer) rs.getObject(3), (Integer) rs.getObject(4)));
                });
        Map<Long, Video> videos = new HashMap<>();
        db.query("""
                SELECT post_id, id, status, hls_manifest_key, thumbnail_key, duration_ms, width, height
                  FROM videos WHERE post_id IN (:ids) AND status <> 'DELETED'""",
                new MapSqlParameterSource("ids", ids), rs -> {
                    videos.put(rs.getLong(1), new Video(rs.getLong(2), rs.getString(3),
                            storage.publicUrl(rs.getString(4)), storage.publicUrl(rs.getString(5)),
                            (Integer) rs.getObject(6), (Integer) rs.getObject(7), (Integer) rs.getObject(8)));
                });
        List<PostView> out = new ArrayList<>();
        for (Row r : rows) {
            out.add(new PostView(r.id(), new UserSummary(r.authorId(), r.nickname(), storage.publicUrl(r.avatarKey())),
                    r.kind(), r.caption(), r.visibility(), r.highlight(),
                    r.venueId() == null ? null : new VenueTag(r.venueId(), r.venueName()), r.status(),
                    images.getOrDefault(r.id(), List.of()), videos.get(r.id()), r.likes(), r.comments(),
                    r.liked(), r.saved(), r.createdAt()));
        }
        return out;
    }

    // ------------------------------------------------------------- 좋아요·저장

    public void like(long userId, long postId, boolean on) {
        requireViewable(userId, postId);
        MapSqlParameterSource p = new MapSqlParameterSource("u", userId).addValue("p", postId);
        if (on) {
            int n = db.update("INSERT INTO likes (user_id, post_id) VALUES (:u, :p) ON CONFLICT DO NOTHING", p);
            if (n > 0) {
                Long author = db.queryForObject("SELECT author_id FROM posts WHERE id = :p", p, Long.class);
                String nick = db.queryForObject("SELECT nickname::text FROM user_profiles WHERE user_id = :u", p, String.class);
                notifications.notify(author, "LIKE", userId, "POST", postId,
                        "새 좋아요", nick + "님이 회원님의 게시물을 좋아해요", null);
            }
        } else {
            db.update("DELETE FROM likes WHERE user_id = :u AND post_id = :p", p);
        }
    }

    public void save(long userId, long postId, boolean on) {
        requireViewable(userId, postId);
        MapSqlParameterSource p = new MapSqlParameterSource("u", userId).addValue("p", postId);
        if (on) db.update("INSERT INTO saved_posts (user_id, post_id) VALUES (:u, :p) ON CONFLICT DO NOTHING", p);
        else db.update("DELETE FROM saved_posts WHERE user_id = :u AND post_id = :p", p);
    }

    public void requireViewable(long userId, long postId) {
        Boolean ok = db.queryForObject("SELECT can_view_post(:u, :p)",
                new MapSqlParameterSource("u", userId).addValue("p", postId), Boolean.class);
        if (!Boolean.TRUE.equals(ok)) throw ApiException.notFound();
    }
}
