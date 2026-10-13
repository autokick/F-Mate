package app.fmate.notification;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;

import java.time.OffsetDateTime;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/**
 * 인앱 알림 생성. 푸시(FCM) 발송은 PushWorker 가 비동기로 처리한다.
 * data 에는 title/body 를 함께 저장해 앱 목록과 푸시 문구가 같게 한다.
 */
@Service
public class NotificationService {

    private static final Logger log = LoggerFactory.getLogger(NotificationService.class);

    private final JdbcTemplate jdbc;
    private final ObjectMapper mapper;

    public NotificationService(JdbcTemplate jdbc, ObjectMapper mapper) {
        this.jdbc = jdbc;
        this.mapper = mapper;
    }

    public void notify(long userId, String type, Long actorId, String targetType, Long targetId,
                       String title, String body, Map<String, Object> extra) {
        try {
            if (actorId != null) {
                if (actorId == userId) return;
                Boolean blocked = jdbc.queryForObject("SELECT is_blocked_between(?, ?)", Boolean.class, userId, actorId);
                if (Boolean.TRUE.equals(blocked)) return;
            }
            Map<String, Object> data = new LinkedHashMap<>();
            if (extra != null) data.putAll(extra);
            data.put("title", title);
            data.put("body", body);
            jdbc.update("""
                    INSERT INTO notifications (user_id, type, actor_id, target_type, target_id, data)
                    VALUES (?, ?, ?, ?, ?, ?::jsonb)""",
                    userId, type, actorId, targetType, targetId, mapper.writeValueAsString(data));
        } catch (JsonProcessingException e) {
            throw new IllegalStateException(e);
        } catch (RuntimeException e) {
            // 알림 실패가 본 작업(예약·결제 등)을 깨뜨리지 않도록 기록만 한다
            log.warn("notification insert failed type={} : {}", type, e.getClass().getSimpleName());
        }
    }

    /** 관리자 전체에게 시스템 알림 (환불 반복 실패 등) */
    public void notifyAdmins(String title, String body, Map<String, Object> extra) {
        List<Long> admins = jdbc.queryForList("SELECT id FROM users WHERE role = 'ADMIN' AND status = 'ACTIVE'", Long.class);
        for (Long id : admins) notify(id, "SYSTEM", null, null, null, title, body, extra);
    }

    public record Item(long id, String type, Long actorId, String actorNickname, String actorAvatarKey,
                       String targetType, Long targetId, String data, boolean read, OffsetDateTime createdAt) {
    }

    public List<Item> list(long userId, Long beforeId, int limit) {
        return jdbc.query("""
                SELECT n.id, n.type, n.actor_id, p.nickname::text, p.avatar_object_key, n.target_type, n.target_id,
                       n.data::text, n.read_at IS NOT NULL, n.created_at
                  FROM notifications n LEFT JOIN user_profiles p ON p.user_id = n.actor_id
                 WHERE n.user_id = ? AND (?::bigint IS NULL OR n.id < ?)
                 ORDER BY n.id DESC LIMIT ?""",
                (rs, i) -> new Item(rs.getLong(1), rs.getString(2), (Long) rs.getObject(3), rs.getString(4),
                        rs.getString(5), rs.getString(6), (Long) rs.getObject(7), rs.getString(8), rs.getBoolean(9),
                        rs.getObject(10, OffsetDateTime.class)),
                userId, beforeId, beforeId, Math.min(Math.max(limit, 1), 50));
    }

    public int unreadCount(long userId) {
        Integer n = jdbc.queryForObject("SELECT count(*)::int FROM notifications WHERE user_id = ? AND read_at IS NULL",
                Integer.class, userId);
        return n == null ? 0 : n;
    }

    public void markRead(long userId, List<Long> ids) {
        if (ids == null || ids.isEmpty()) {
            jdbc.update("UPDATE notifications SET read_at = now() WHERE user_id = ? AND read_at IS NULL", userId);
        } else {
            for (Long id : ids) {
                jdbc.update("UPDATE notifications SET read_at = now() WHERE user_id = ? AND id = ? AND read_at IS NULL", userId, id);
            }
        }
    }
}
