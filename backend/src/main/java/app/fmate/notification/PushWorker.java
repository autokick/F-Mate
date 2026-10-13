package app.fmate.notification;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;
import org.springframework.transaction.support.TransactionTemplate;

import java.util.HashMap;
import java.util.List;
import java.util.Map;

/** 대기 중인 알림을 FCM 으로 발송 (사용자 알림 설정을 따른다). 여러 서버에서 돌아도 SKIP LOCKED 로 중복 발송 없음. */
@Component
public class PushWorker {

    private final JdbcTemplate jdbc;
    private final PushService push;
    private final TransactionTemplate tx;
    private final ObjectMapper mapper;

    public PushWorker(JdbcTemplate jdbc, PushService push, TransactionTemplate tx, ObjectMapper mapper) {
        this.jdbc = jdbc;
        this.push = push;
        this.tx = tx;
        this.mapper = mapper;
    }

    private record Pending(long id, long userId, String type, String targetType, Long targetId, String data) {
    }

    static String category(String type) {
        if (type.startsWith("RESERVATION_") || type.startsWith("REFUND_")) return "reservation";
        if ("MESSAGE".equals(type)) return "chat";
        if ("SYSTEM".equals(type)) return "system";
        return "social";
    }

    @Scheduled(fixedDelay = 5000, initialDelay = 15000)
    public void run() {
        if (!push.isAvailable()) {
            jdbc.update("UPDATE notifications SET push_status = 'SKIPPED' WHERE push_status = 'PENDING'");
            return;
        }
        tx.executeWithoutResult(status -> {
            List<Pending> batch = jdbc.query("""
                    SELECT id, user_id, type, target_type, target_id, data::text FROM notifications
                     WHERE push_status = 'PENDING' ORDER BY id LIMIT 100 FOR UPDATE SKIP LOCKED""",
                    (rs, i) -> new Pending(rs.getLong(1), rs.getLong(2), rs.getString(3), rs.getString(4),
                            (Long) rs.getObject(5), rs.getString(6)));
            for (Pending n : batch) process(n);
        });
    }

    private void process(Pending n) {
        String cat = category(n.type());
        if (!"system".equals(cat)) {
            Boolean allowed = jdbc.queryForObject("""
                    SELECT COALESCE((SELECT CASE ? WHEN 'reservation' THEN reservation WHEN 'chat' THEN chat ELSE social END
                                       FROM notification_settings WHERE user_id = ?), true)""",
                    Boolean.class, cat, n.userId());
            if (!Boolean.TRUE.equals(allowed)) {
                jdbc.update("UPDATE notifications SET push_status = 'SKIPPED' WHERE id = ?", n.id());
                return;
            }
        }
        List<String> tokens = jdbc.queryForList("SELECT fcm_token FROM device_tokens WHERE user_id = ?", String.class, n.userId());
        if (tokens.isEmpty()) {
            jdbc.update("UPDATE notifications SET push_status = 'SKIPPED' WHERE id = ?", n.id());
            return;
        }
        String title = "F-Mate";
        String body = "";
        try {
            JsonNode d = mapper.readTree(n.data());
            title = d.path("title").asText("F-Mate");
            body = d.path("body").asText("");
        } catch (Exception ignored) {
            // 기본 문구 사용
        }
        Map<String, String> data = new HashMap<>();
        data.put("notificationId", Long.toString(n.id()));
        data.put("type", n.type());
        if (n.targetType() != null) data.put("targetType", n.targetType());
        if (n.targetId() != null) data.put("targetId", Long.toString(n.targetId()));

        boolean anySent = false;
        for (String t : tokens) {
            PushService.Result r = push.send(t, title, body, data);
            if (r == PushService.Result.SENT) anySent = true;
            if (r == PushService.Result.INVALID_TOKEN) jdbc.update("DELETE FROM device_tokens WHERE fcm_token = ?", t);
        }
        jdbc.update("UPDATE notifications SET push_status = ? WHERE id = ?", anySent ? "SENT" : "FAILED", n.id());
    }
}
