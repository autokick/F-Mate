package app.fmate.social;

import app.fmate.common.ApiException;
import app.fmate.media.StorageService;
import app.fmate.notification.NotificationService;
import app.fmate.user.UserSummary;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;

import java.time.OffsetDateTime;
import java.util.List;
import java.util.Map;

@Service
public class CommentService {

    private final JdbcTemplate jdbc;
    private final PostService posts;
    private final StorageService storage;
    private final NotificationService notifications;

    public CommentService(JdbcTemplate jdbc, PostService posts, StorageService storage, NotificationService notifications) {
        this.jdbc = jdbc;
        this.posts = posts;
        this.storage = storage;
        this.notifications = notifications;
    }

    public record CommentView(long id, Long parentId, UserSummary author, String body, OffsetDateTime createdAt,
                              boolean mine) {
    }

    public List<CommentView> list(long viewerId, long postId, Long afterId, int limit) {
        posts.requireViewable(viewerId, postId);
        return jdbc.query("""
                SELECT c.id, c.parent_id, c.author_id, p.nickname::text, p.avatar_object_key, c.body, c.created_at
                  FROM comments c JOIN user_profiles p ON p.user_id = c.author_id
                 WHERE c.post_id = ? AND c.status = 'ACTIVE' AND NOT is_blocked_between(?, c.author_id)
                   AND (?::bigint IS NULL OR c.id > ?)
                 ORDER BY c.id LIMIT ?""",
                (rs, i) -> new CommentView(rs.getLong(1), (Long) rs.getObject(2),
                        new UserSummary(rs.getLong(3), rs.getString(4), storage.publicUrl(rs.getString(5))),
                        rs.getString(6), rs.getObject(7, OffsetDateTime.class), rs.getLong(3) == viewerId),
                postId, viewerId, afterId, afterId, Math.min(Math.max(limit, 1), 100));
    }

    public CommentView create(long userId, boolean emailVerified, long postId, Long parentId, String body) {
        if (!emailVerified) throw ApiException.forbidden("EMAIL_NOT_VERIFIED");
        posts.requireViewable(userId, postId);
        String text = body == null ? "" : body.strip();
        if (text.isEmpty() || text.length() > 1000) throw ApiException.badRequest("VALIDATION_FAILED", "댓글은 1~1,000자예요");
        Long author = jdbc.queryForObject("SELECT author_id FROM posts WHERE id = ?", Long.class, postId);
        Boolean blocked = jdbc.queryForObject("SELECT is_blocked_between(?, ?)", Boolean.class, userId, author);
        if (Boolean.TRUE.equals(blocked)) throw ApiException.forbidden("BLOCKED");

        Long parentAuthor = null;
        if (parentId != null) {
            List<Map<String, Object>> parent = jdbc.queryForList(
                    "SELECT author_id, parent_id FROM comments WHERE id = ? AND post_id = ? AND status = 'ACTIVE'", parentId, postId);
            if (parent.isEmpty()) throw ApiException.notFound();
            if (parent.get(0).get("parent_id") != null) {
                throw ApiException.badRequest("VALIDATION_FAILED", "답글에는 답글을 달 수 없어요");
            }
            parentAuthor = ((Number) parent.get(0).get("author_id")).longValue();
        }
        Long id = jdbc.queryForObject(
                "INSERT INTO comments (post_id, author_id, parent_id, body) VALUES (?, ?, ?, ?) RETURNING id",
                Long.class, postId, userId, parentId, text);

        String nick = jdbc.queryForObject("SELECT nickname::text FROM user_profiles WHERE user_id = ?", String.class, userId);
        String preview = text.length() > 40 ? text.substring(0, 40) + "…" : text;
        notifications.notify(author, "COMMENT", userId, "POST", postId, "새 댓글", nick + ": " + preview,
                Map.of("commentId", id));
        if (parentAuthor != null && !parentAuthor.equals(author)) {
            notifications.notify(parentAuthor, "COMMENT", userId, "POST", postId, "새 답글", nick + ": " + preview,
                    Map.of("commentId", id));
        }
        return new CommentView(id, parentId, new UserSummary(userId, nick, null), text, OffsetDateTime.now(), true);
    }

    /** 댓글 작성자, 게시물 작성자, 모더레이터가 삭제할 수 있다 */
    public void delete(long userId, boolean moderator, long commentId) {
        List<Map<String, Object>> rows = jdbc.queryForList("""
                SELECT c.author_id, p.author_id AS post_author FROM comments c JOIN posts p ON p.id = c.post_id
                 WHERE c.id = ? AND c.status = 'ACTIVE'""", commentId);
        if (rows.isEmpty()) throw ApiException.notFound();
        long author = ((Number) rows.get(0).get("author_id")).longValue();
        long postAuthor = ((Number) rows.get(0).get("post_author")).longValue();
        if (author != userId && postAuthor != userId && !moderator) throw ApiException.forbidden("FORBIDDEN");
        jdbc.update("UPDATE comments SET status = 'DELETED', updated_at = now() WHERE id = ?", commentId);
    }
}
