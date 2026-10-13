package app.fmate.chat;

import app.fmate.auth.AuthUser;
import app.fmate.auth.JwtAuthConverter;
import app.fmate.common.ApiException;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.security.oauth2.jwt.JwtDecoder;
import org.springframework.stereotype.Component;
import org.springframework.web.socket.CloseStatus;
import org.springframework.web.socket.TextMessage;
import org.springframework.web.socket.WebSocketSession;
import org.springframework.web.socket.handler.ConcurrentWebSocketSessionDecorator;
import org.springframework.web.socket.handler.TextWebSocketHandler;

import java.util.Collection;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.Set;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.Executors;
import java.util.concurrent.ScheduledExecutorService;
import java.util.concurrent.TimeUnit;

/**
 * 채팅 WebSocket (/ws/chat). 토큰을 URL 에 넣지 않도록(로그 노출 방지) 연결 후 첫 메시지로 인증한다.
 *
 * 클라이언트 → 서버
 *   {"type":"auth","token":"<액세스 토큰>"}               (연결 후 10초 안에)
 *   {"type":"send","chatId":1,"clientMessageId":"<uuid>","body":"..."}
 *   {"type":"read","chatId":1,"messageId":10}
 *   {"type":"ping"}
 * 서버 → 클라이언트
 *   {"type":"ready"} / {"type":"ack","clientMessageId":..,"message":{..}} / {"type":"error","code":..,"clientMessageId":..}
 *   {"type":"message","message":{..}} / {"type":"read","chatId":..,"userId":..,"messageId":..} / {"type":"pong"}
 *
 * 서버 1대 기준 인메모리 세션. 여러 대로 늘릴 때는 Redis Pub/Sub 으로 deliver* 를 중계해야 한다 (docs/05-deploy.md).
 */
@Component
public class ChatSocketHandler extends TextWebSocketHandler {

    private static final Logger log = LoggerFactory.getLogger(ChatSocketHandler.class);
    private static final String USER = "userId";

    private final JwtDecoder decoder;
    private final JwtAuthConverter converter;
    private final ObjectMapper mapper;
    private final ChatService chats;
    private final Map<Long, Set<WebSocketSession>> sessions = new ConcurrentHashMap<>();
    private final ScheduledExecutorService timer = Executors.newSingleThreadScheduledExecutor(r -> {
        Thread t = new Thread(r, "ws-auth-timeout");
        t.setDaemon(true);
        return t;
    });

    public ChatSocketHandler(JwtDecoder decoder, JwtAuthConverter converter, ObjectMapper mapper, ChatService chats) {
        this.decoder = decoder;
        this.converter = converter;
        this.mapper = mapper;
        this.chats = chats;
    }

    @Override
    public void afterConnectionEstablished(WebSocketSession raw) {
        timer.schedule(() -> {
            if (raw.isOpen() && raw.getAttributes().get(USER) == null) {
                try {
                    raw.close(CloseStatus.POLICY_VIOLATION.withReason("auth timeout"));
                } catch (Exception ignored) {
                    // 이미 닫힘
                }
            }
        }, 10, TimeUnit.SECONDS);
    }

    @Override
    protected void handleTextMessage(WebSocketSession raw, TextMessage text) throws Exception {
        if (text.getPayloadLength() > 8_000) {
            raw.close(CloseStatus.TOO_BIG_TO_PROCESS);
            return;
        }
        JsonNode msg = mapper.readTree(text.getPayload());
        String type = msg.path("type").asText("");
        Object uid = raw.getAttributes().get(USER);

        if (uid == null) {
            if (!"auth".equals(type)) {
                raw.close(CloseStatus.POLICY_VIOLATION.withReason("auth required"));
                return;
            }
            try {
                AuthUser user = (AuthUser) converter.convert(decoder.decode(msg.path("token").asText(""))).getPrincipal();
                raw.getAttributes().put(USER, user.id());
                WebSocketSession s = new ConcurrentWebSocketSessionDecorator(raw, 5_000, 256 * 1024);
                raw.getAttributes().put("decorated", s);
                sessions.computeIfAbsent(user.id(), k -> ConcurrentHashMap.newKeySet()).add(s);
                send(s, Map.of("type", "ready"));
            } catch (Exception e) {
                raw.close(CloseStatus.POLICY_VIOLATION.withReason("invalid token"));
            }
            return;
        }

        long me = (Long) uid;
        WebSocketSession s = (WebSocketSession) raw.getAttributes().get("decorated");
        String cmid = msg.path("clientMessageId").asText(null);
        try {
            switch (type) {
                case "send" -> {
                    ChatService.MessageView m = chats.send(me, msg.path("chatId").asLong(), cmid, msg.path("body").asText(""));
                    Map<String, Object> ack = new LinkedHashMap<>();
                    ack.put("type", "ack");
                    ack.put("clientMessageId", cmid);
                    ack.put("message", m);
                    send(s, ack);
                }
                case "read" -> chats.markRead(me, msg.path("chatId").asLong(), msg.path("messageId").asLong());
                case "ping" -> send(s, Map.of("type", "pong"));
                default -> send(s, Map.of("type", "error", "code", "BAD_REQUEST"));
            }
        } catch (ApiException e) {
            Map<String, Object> err = new LinkedHashMap<>();
            err.put("type", "error");
            err.put("code", e.code());
            err.put("message", e.getMessage());
            if (cmid != null) err.put("clientMessageId", cmid);
            send(s, err);
        } catch (Exception e) {
            log.warn("ws message failed: {}", e.getClass().getSimpleName());
            Map<String, Object> err = new LinkedHashMap<>();
            err.put("type", "error");
            err.put("code", "INTERNAL");
            if (cmid != null) err.put("clientMessageId", cmid);
            send(s, err);
        }
    }

    @Override
    public void afterConnectionClosed(WebSocketSession raw, CloseStatus status) {
        Object uid = raw.getAttributes().get(USER);
        Object dec = raw.getAttributes().get("decorated");
        if (uid instanceof Long id && dec instanceof WebSocketSession s) {
            Set<WebSocketSession> set = sessions.get(id);
            if (set != null) {
                set.remove(s);
                if (set.isEmpty()) sessions.remove(id, set);
            }
        }
    }

    public boolean isOnline(long userId) {
        Set<WebSocketSession> set = sessions.get(userId);
        return set != null && set.stream().anyMatch(WebSocketSession::isOpen);
    }

    public void deliverMessage(Collection<Long> userIds, ChatService.MessageView m) {
        Map<String, Object> payload = new LinkedHashMap<>();
        payload.put("type", "message");
        payload.put("message", m);
        for (Long id : userIds) broadcast(id, payload);
    }

    public void deliverRead(long toUser, long chatId, long readerId, long messageId) {
        broadcast(toUser, Map.of("type", "read", "chatId", chatId, "userId", readerId, "messageId", messageId));
    }

    private void broadcast(long userId, Map<String, Object> payload) {
        Set<WebSocketSession> set = sessions.get(userId);
        if (set == null) return;
        for (WebSocketSession s : set) send(s, payload);
    }

    private void send(WebSocketSession s, Object payload) {
        if (s == null || !s.isOpen()) return;
        try {
            s.sendMessage(new TextMessage(mapper.writeValueAsString(payload)));
        } catch (Exception e) {
            log.debug("ws send failed: {}", e.getClass().getSimpleName());
        }
    }
}
