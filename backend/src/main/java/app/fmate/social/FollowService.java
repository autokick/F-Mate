package app.fmate.social;

import app.fmate.common.ApiException;
import app.fmate.media.StorageService;
import app.fmate.notification.NotificationService;
import app.fmate.user.UserSummary;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;

import java.util.List;
import java.util.Map;

@Service
public class FollowService {

    private final JdbcTemplate jdbc;
    private final StorageService storage;
    private final NotificationService notifications;

    public FollowService(JdbcTemplate jdbc, StorageService storage, NotificationService notifications) {
        this.jdbc = jdbc;
        this.storage = storage;
        this.notifications = notifications;
    }

    /** 공개 계정이면 바로 팔로우(FOLLOWING), 비공개 계정이면 요청(PENDING) */
    public String follow(long me, long target) {
        if (me == target) throw ApiException.badRequest("INVALID_TARGET");
        List<Map<String, Object>> t = jdbc.queryForList("""
                SELECT p.is_private FROM users u JOIN user_profiles p ON p.user_id = u.id
                 WHERE u.id = ? AND u.status = 'ACTIVE'""", target);
        if (t.isEmpty()) throw ApiException.notFound();
        boolean isPrivate = (Boolean) t.get(0).get("is_private");
        String status = isPrivate ? "PENDING" : "ACCEPTED";
        int n = jdbc.update("INSERT INTO follows (follower_id, followee_id, status) VALUES (?, ?, ?) ON CONFLICT DO NOTHING",
                me, target, status);
        if (n > 0) {
            String nick = nickname(me);
            if (isPrivate) {
                notifications.notify(target, "FOLLOW_REQUEST", me, "USER", me, "팔로우 요청", nick + "님이 팔로우를 요청했어요", null);
            } else {
                notifications.notify(target, "FOLLOW", me, "USER", me, "새 팔로워", nick + "님이 회원님을 팔로우해요", null);
            }
            return isPrivate ? "PENDING" : "FOLLOWING";
        }
        String existing = jdbc.queryForObject("SELECT status FROM follows WHERE follower_id = ? AND followee_id = ?",
                String.class, me, target);
        return "ACCEPTED".equals(existing) ? "FOLLOWING" : existing;
    }

    public void unfollow(long me, long target) {
        jdbc.update("DELETE FROM follows WHERE follower_id = ? AND followee_id = ?", me, target);
    }

    /** 나를 팔로우하는 사람 삭제 (요청 거절 포함) */
    public void removeFollower(long me, long follower) {
        jdbc.update("DELETE FROM follows WHERE follower_id = ? AND followee_id = ?", follower, me);
    }

    public void acceptRequest(long me, long requester) {
        int n = jdbc.update("UPDATE follows SET status = 'ACCEPTED' WHERE follower_id = ? AND followee_id = ? AND status = 'PENDING'",
                requester, me);
        if (n == 0) throw ApiException.notFound();
        notifications.notify(requester, "FOLLOW", me, "USER", me, "팔로우 요청 수락",
                nickname(me) + "님이 팔로우 요청을 수락했어요", null);
    }

    public List<UserSummary> requests(long me) {
        return jdbc.query("""
                SELECT f.follower_id, p.nickname::text, p.avatar_object_key FROM follows f
                  JOIN user_profiles p ON p.user_id = f.follower_id
                 WHERE f.followee_id = ? AND f.status = 'PENDING' ORDER BY f.created_at DESC LIMIT 200""",
                (rs, i) -> new UserSummary(rs.getLong(1), rs.getString(2), storage.publicUrl(rs.getString(3))), me);
    }

    /** 비공개 계정의 목록은 본인과 승인된 팔로워만 볼 수 있다 */
    public List<UserSummary> followers(long viewer, long target, int page, int size) {
        requireListVisible(viewer, target);
        return jdbc.query("""
                SELECT f.follower_id, p.nickname::text, p.avatar_object_key FROM follows f
                  JOIN user_profiles p ON p.user_id = f.follower_id
                 WHERE f.followee_id = ? AND f.status = 'ACCEPTED' AND NOT is_blocked_between(?, f.follower_id)
                 ORDER BY f.created_at DESC LIMIT ? OFFSET ?""",
                (rs, i) -> new UserSummary(rs.getLong(1), rs.getString(2), storage.publicUrl(rs.getString(3))),
                target, viewer, clamp(size), Math.max(page, 0) * clamp(size));
    }

    public List<UserSummary> following(long viewer, long target, int page, int size) {
        requireListVisible(viewer, target);
        return jdbc.query("""
                SELECT f.followee_id, p.nickname::text, p.avatar_object_key FROM follows f
                  JOIN user_profiles p ON p.user_id = f.followee_id
                 WHERE f.follower_id = ? AND f.status = 'ACCEPTED' AND NOT is_blocked_between(?, f.followee_id)
                 ORDER BY f.created_at DESC LIMIT ? OFFSET ?""",
                (rs, i) -> new UserSummary(rs.getLong(1), rs.getString(2), storage.publicUrl(rs.getString(3))),
                target, viewer, clamp(size), Math.max(page, 0) * clamp(size));
    }

    private void requireListVisible(long viewer, long target) {
        if (viewer == target) return;
        Boolean ok = jdbc.queryForObject("""
                SELECT NOT is_blocked_between(?, u.id) AND (NOT p.is_private OR EXISTS (
                         SELECT 1 FROM follows f WHERE f.follower_id = ? AND f.followee_id = u.id AND f.status = 'ACCEPTED'))
                  FROM users u JOIN user_profiles p ON p.user_id = u.id WHERE u.id = ? AND u.status = 'ACTIVE'""",
                Boolean.class, viewer, viewer, target);
        if (!Boolean.TRUE.equals(ok)) throw ApiException.forbidden("FORBIDDEN");
    }

    // ------------------------------------------------------------- 차단

    public void block(long me, long target) {
        if (me == target) throw ApiException.badRequest("INVALID_TARGET");
        jdbc.update("INSERT INTO blocks (blocker_id, blocked_id) VALUES (?, ?) ON CONFLICT DO NOTHING", me, target);
    }

    public void unblock(long me, long target) {
        jdbc.update("DELETE FROM blocks WHERE blocker_id = ? AND blocked_id = ?", me, target);
    }

    public List<UserSummary> blocked(long me) {
        return jdbc.query("""
                SELECT b.blocked_id, COALESCE(p.nickname::text, '(탈퇴한 사용자)'), p.avatar_object_key FROM blocks b
                  LEFT JOIN user_profiles p ON p.user_id = b.blocked_id
                 WHERE b.blocker_id = ? ORDER BY b.created_at DESC""",
                (rs, i) -> new UserSummary(rs.getLong(1), rs.getString(2), storage.publicUrl(rs.getString(3))), me);
    }

    private String nickname(long userId) {
        return jdbc.queryForObject("SELECT nickname::text FROM user_profiles WHERE user_id = ?", String.class, userId);
    }

    private static int clamp(int size) {
        return Math.min(Math.max(size, 1), 50);
    }
}
