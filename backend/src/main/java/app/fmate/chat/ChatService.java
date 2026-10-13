package app.fmate.chat;

import app.fmate.common.ApiException;
import app.fmate.common.RateLimiter;
import app.fmate.media.StorageService;
import app.fmate.notification.NotificationService;
import app.fmate.user.UserSummary;
import org.springframework.context.annotation.Lazy;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;

import java.time.Duration;
import java.time.OffsetDateTime;
import java.util.List;
import java.util.Map;
import java.util.UUID;

@Service
public class ChatService {

    private final JdbcTemplate jdbc;
    private final StorageService storage;
    private final NotificationService notifications;
    private final RateLimiter limiter;
    private final ChatSocketHandler sockets;

    public ChatService(JdbcTemplate jdbc, StorageService storage, NotificationService notifications,
                       RateLimiter limiter, @Lazy ChatSocketHandler sockets) {
        this.jdbc = jdbc;
        this.storage = storage;
        this.notifications = notifications;
        this.limiter = limiter;
        this.sockets = sockets;
    }

    public record MessageView(long id, long chatId, long senderId, String clientMessageId, String body,
                              boolean deleted, OffsetDateTime createdAt) {
    }

    public record ChatSummary(long id, UserSummary other, MessageView lastMessage, int unreadCount,
                              long myLastReadMessageId, long otherLastReadMessageId, boolean blocked) {
    }

    public ChatSummary open(long me, long other) {
        Integer exists = jdbc.queryForObject("SELECT count(*)::int FROM users WHERE id = ? AND status = 'ACTIVE'",
                Integer.class, other);
        if (exists == null || exists == 0) throw ApiException.notFound();
        Long chatId = jdbc.queryForObject("SELECT fn_open_chat(?, ?)", Long.class, me, other);
        jdbc.update("UPDATE chat_members SET hidden_at = NULL WHERE chat_id = ? AND user_id = ?", chatId, me);
        return summary(me, chatId);
    }

    public List<ChatSummary> list(long me) {
        List<Long> ids = jdbc.queryForList("""
                SELECT c.id FROM chats c JOIN chat_members m ON m.chat_id = c.id AND m.user_id = ?
                 WHERE m.hidden_at IS NULL
                 ORDER BY c.last_message_at DESC NULLS LAST, c.id DESC LIMIT 200""", Long.class, me);
        return ids.stream().map(id -> summary(me, id)).toList();
    }

    public ChatSummary summary(long me, long chatId) {
        Map<String, Object> c = participant(me, chatId);
        long other = ((Number) c.get("user_low")).longValue() == me
                ? ((Number) c.get("user_high")).longValue() : ((Number) c.get("user_low")).longValue();
        UserSummary otherSummary = jdbc.query("""
                SELECT u.id, COALESCE(p.nickname::text, '(탈퇴한 사용자)'), p.avatar_object_key
                  FROM users u LEFT JOIN user_profiles p ON p.user_id = u.id WHERE u.id = ?""",
                rs -> rs.next() ? new UserSummary(rs.getLong(1), rs.getString(2), storage.publicUrl(rs.getString(3))) : null,
                other);
        List<MessageView> last = jdbc.query("""
                SELECT id, chat_id, sender_id, client_message_id::text, body, deleted_at IS NOT NULL, created_at
                  FROM messages WHERE chat_id = ? ORDER BY id DESC LIMIT 1""", this::mapMessage, chatId);
        long myRead = readPointer(chatId, me);
        long otherRead = readPointer(chatId, other);
        Integer unread = jdbc.queryForObject(
                "SELECT count(*)::int FROM messages WHERE chat_id = ? AND sender_id <> ? AND id > ?",
                Integer.class, chatId, me, myRead);
        Boolean blocked = jdbc.queryForObject("SELECT is_blocked_between(?, ?)", Boolean.class, me, other);
        return new ChatSummary(chatId, otherSummary, last.isEmpty() ? null : last.get(0), unread == null ? 0 : unread,
                myRead, otherRead, Boolean.TRUE.equals(blocked));
    }

    public List<MessageView> messages(long me, long chatId, Long beforeId, Long afterId, int limit) {
        participant(me, chatId);
        int size = Math.min(Math.max(limit, 1), 100);
        if (afterId != null) {
            // 재연결 후 누락분 동기화: 오래된 것부터
            return jdbc.query("""
                    SELECT id, chat_id, sender_id, client_message_id::text, body, deleted_at IS NOT NULL, created_at
                      FROM messages WHERE chat_id = ? AND id > ? ORDER BY id LIMIT ?""",
                    this::mapMessage, chatId, afterId, size);
        }
        return jdbc.query("""
                SELECT id, chat_id, sender_id, client_message_id::text, body, deleted_at IS NOT NULL, created_at
                  FROM messages WHERE chat_id = ? AND (?::bigint IS NULL OR id < ?) ORDER BY id DESC LIMIT ?""",
                this::mapMessage, chatId, beforeId, beforeId, size);
    }

    /**
     * 메시지 전송. client_message_id 로 멱등 처리 — 재연결 후 같은 메시지를 다시 보내도 1건만 저장된다.
     */
    public MessageView send(long me, long chatId, String clientMessageId, String body) {
        participant(me, chatId);
        limiter.check("chat-send", Long.toString(me), 60, Duration.ofMinutes(1));
        String text = body == null ? "" : body.strip();
        if (text.isEmpty() || text.length() > 2000) throw ApiException.badRequest("VALIDATION_FAILED", "메시지는 1~2,000자예요");
        UUID cmid;
        try {
            cmid = UUID.fromString(clientMessageId);
        } catch (Exception e) {
            throw ApiException.badRequest("VALIDATION_FAILED");
        }
        List<MessageView> inserted = jdbc.query("""
                INSERT INTO messages (chat_id, sender_id, client_message_id, body) VALUES (?, ?, ?, ?)
                ON CONFLICT (sender_id, client_message_id) DO NOTHING
                RETURNING id, chat_id, sender_id, client_message_id::text, body, deleted_at IS NOT NULL, created_at""",
                this::mapMessage, chatId, me, cmid, text);
        if (inserted.isEmpty()) {
            return jdbc.queryForObject("""
                    SELECT id, chat_id, sender_id, client_message_id::text, body, deleted_at IS NOT NULL, created_at
                      FROM messages WHERE sender_id = ? AND client_message_id = ?""", this::mapMessage, me, cmid);
        }
        MessageView m = inserted.get(0);
        long other = otherMember(chatId, me);
        sockets.deliverMessage(List.of(me, other), m);
        if (!sockets.isOnline(other)) {
            Boolean muted = jdbc.queryForObject("SELECT muted FROM chat_members WHERE chat_id = ? AND user_id = ?",
                    Boolean.class, chatId, other);
            if (!Boolean.TRUE.equals(muted)) {
                String nick = jdbc.queryForObject("SELECT nickname::text FROM user_profiles WHERE user_id = ?", String.class, me);
                notifications.notify(other, "MESSAGE", me, "CHAT", chatId, nick,
                        text.length() > 60 ? text.substring(0, 60) + "…" : text, null);
            }
        }
        return m;
    }

    public void markRead(long me, long chatId, long messageId) {
        participant(me, chatId);
        int n = jdbc.update("""
                UPDATE chat_members SET last_read_message_id = ?
                 WHERE chat_id = ? AND user_id = ? AND last_read_message_id < ?
                   AND EXISTS (SELECT 1 FROM messages WHERE id = ? AND chat_id = ?)""",
                messageId, chatId, me, messageId, messageId, chatId);
        if (n > 0) sockets.deliverRead(otherMember(chatId, me), chatId, me, messageId);
    }

    public void hide(long me, long chatId) {
        participant(me, chatId);
        jdbc.update("UPDATE chat_members SET hidden_at = now() WHERE chat_id = ? AND user_id = ?", chatId, me);
    }

    public void mute(long me, long chatId, boolean muted) {
        participant(me, chatId);
        jdbc.update("UPDATE chat_members SET muted = ? WHERE chat_id = ? AND user_id = ?", muted, chatId, me);
    }

    private Map<String, Object> participant(long me, long chatId) {
        List<Map<String, Object>> rows = jdbc.queryForList(
                "SELECT user_low, user_high FROM chats WHERE id = ? AND ? IN (user_low, user_high)", chatId, me);
        if (rows.isEmpty()) throw ApiException.notFound();
        return rows.get(0);
    }

    private long otherMember(long chatId, long me) {
        Map<String, Object> c = participant(me, chatId);
        long low = ((Number) c.get("user_low")).longValue();
        return low == me ? ((Number) c.get("user_high")).longValue() : low;
    }

    private long readPointer(long chatId, long userId) {
        List<Long> v = jdbc.queryForList("SELECT last_read_message_id FROM chat_members WHERE chat_id = ? AND user_id = ?",
                Long.class, chatId, userId);
        return v.isEmpty() ? 0 : v.get(0);
    }

    private MessageView mapMessage(java.sql.ResultSet rs, int i) throws java.sql.SQLException {
        boolean deleted = rs.getBoolean(6);
        return new MessageView(rs.getLong(1), rs.getLong(2), rs.getLong(3), rs.getString(4),
                deleted ? "(삭제된 메시지)" : rs.getString(5), deleted, rs.getObject(7, OffsetDateTime.class));
    }
}
