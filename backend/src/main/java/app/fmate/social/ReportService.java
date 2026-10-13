package app.fmate.social;

import app.fmate.common.ApiException;
import app.fmate.notification.NotificationService;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.Map;
import java.util.Set;

/**
 * 신고 접수. 서로 다른 5명 이상이 같은 게시물·댓글을 신고하면 검토 전까지 자동으로 숨긴다(이용자 보호).
 * 최종 판단은 모더레이터가 관리자 화면에서 한다.
 */
@Service
public class ReportService {

    public static final int AUTO_HIDE_THRESHOLD = 5;
    private static final Set<String> TARGETS = Set.of("POST", "COMMENT", "USER", "MESSAGE", "VENUE");
    private static final Set<String> REASONS = Set.of("SPAM", "HARASSMENT", "HATE", "SEXUAL", "VIOLENCE", "ILLEGAL",
            "COPYRIGHT", "IMPERSONATION", "FALSE_VENUE_INFO", "OTHER");

    private final JdbcTemplate jdbc;
    private final NotificationService notifications;

    public ReportService(JdbcTemplate jdbc, NotificationService notifications) {
        this.jdbc = jdbc;
        this.notifications = notifications;
    }

    @Transactional
    public long report(long reporterId, String targetType, long targetId, String reason, String detail) {
        if (!TARGETS.contains(targetType) || !REASONS.contains(reason)) throw ApiException.badRequest("VALIDATION_FAILED");
        if (!targetExists(reporterId, targetType, targetId)) throw ApiException.notFound();
        String d = detail == null ? null : detail.strip();
        if (d != null && d.length() > 1000) d = d.substring(0, 1000);
        Long id = jdbc.queryForObject("""
                INSERT INTO reports (reporter_id, target_type, target_id, reason, detail) VALUES (?, ?, ?, ?, ?) RETURNING id""",
                Long.class, reporterId, targetType, targetId, reason, d);

        Integer distinct = jdbc.queryForObject("""
                SELECT count(DISTINCT reporter_id)::int FROM reports
                 WHERE target_type = ? AND target_id = ? AND status IN ('OPEN','REVIEWING')""",
                Integer.class, targetType, targetId);
        if (distinct != null && distinct == AUTO_HIDE_THRESHOLD) {
            if ("POST".equals(targetType)) {
                jdbc.update("UPDATE posts SET status = 'HIDDEN_BY_MODERATION' WHERE id = ? AND status = 'ACTIVE'", targetId);
            } else if ("COMMENT".equals(targetType)) {
                jdbc.update("UPDATE comments SET status = 'HIDDEN_BY_MODERATION' WHERE id = ? AND status = 'ACTIVE'", targetId);
            }
            notifications.notifyAdmins("신고 누적", targetType + " #" + targetId + " 신고가 " + distinct + "건 누적되어 검토가 필요해요",
                    Map.of("targetType", targetType, "targetId", targetId));
        }
        return id;
    }

    /** 신고자가 실제로 볼 수 있는 대상인지 확인 (존재하지 않거나 볼 수 없는 대상 신고 방지) */
    private boolean targetExists(long reporterId, String type, long id) {
        Boolean ok = switch (type) {
            case "POST" -> jdbc.queryForObject("SELECT can_view_post(?, ?)", Boolean.class, reporterId, id);
            case "COMMENT" -> jdbc.queryForObject("""
                    SELECT EXISTS (SELECT 1 FROM comments c WHERE c.id = ? AND c.status = 'ACTIVE'
                                     AND can_view_post(?, c.post_id))""", Boolean.class, id, reporterId);
            case "USER" -> jdbc.queryForObject(
                    "SELECT EXISTS (SELECT 1 FROM users WHERE id = ? AND status <> 'DELETED')", Boolean.class, id);
            case "MESSAGE" -> jdbc.queryForObject("""
                    SELECT EXISTS (SELECT 1 FROM messages m JOIN chats c ON c.id = m.chat_id
                                    WHERE m.id = ? AND ? IN (c.user_low, c.user_high))""", Boolean.class, id, reporterId);
            case "VENUE" -> jdbc.queryForObject(
                    "SELECT EXISTS (SELECT 1 FROM futsal_venues WHERE id = ?)", Boolean.class, id);
            default -> false;
        };
        return Boolean.TRUE.equals(ok);
    }
}
