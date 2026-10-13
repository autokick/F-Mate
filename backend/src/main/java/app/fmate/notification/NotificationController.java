package app.fmate.notification;

import app.fmate.auth.AuthUser;
import app.fmate.media.StorageService;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.time.OffsetDateTime;
import java.util.List;
import java.util.Map;

@RestController
@RequestMapping("/api/v1/notifications")
public class NotificationController {

    private final NotificationService notifications;
    private final StorageService storage;
    private final ObjectMapper mapper;

    public NotificationController(NotificationService notifications, StorageService storage, ObjectMapper mapper) {
        this.notifications = notifications;
        this.storage = storage;
        this.mapper = mapper;
    }

    public record Actor(long id, String nickname, String avatarUrl) {
    }

    public record NotificationView(long id, String type, Actor actor, String targetType, Long targetId,
                                   String title, String body, JsonNode data, boolean read, OffsetDateTime createdAt) {
    }

    @GetMapping
    public List<NotificationView> list(@AuthenticationPrincipal AuthUser me,
                                       @RequestParam(required = false) Long before,
                                       @RequestParam(defaultValue = "30") int limit) {
        return notifications.list(me.id(), before, limit).stream().map(n -> {
            JsonNode data = null;
            try {
                data = mapper.readTree(n.data());
            } catch (Exception ignored) {
                // 손상된 데이터는 비워서 보낸다
            }
            Actor actor = n.actorId() == null ? null
                    : new Actor(n.actorId(), n.actorNickname(), storage.publicUrl(n.actorAvatarKey()));
            return new NotificationView(n.id(), n.type(), actor, n.targetType(), n.targetId(),
                    data == null ? null : data.path("title").asText(null),
                    data == null ? null : data.path("body").asText(null),
                    data, n.read(), n.createdAt());
        }).toList();
    }

    @GetMapping("/unread-count")
    public Map<String, Integer> unread(@AuthenticationPrincipal AuthUser me) {
        return Map.of("count", notifications.unreadCount(me.id()));
    }

    public record ReadRequest(List<Long> ids) {
    }

    @PostMapping("/read")
    public ResponseEntity<Void> read(@AuthenticationPrincipal AuthUser me, @RequestBody(required = false) ReadRequest r) {
        notifications.markRead(me.id(), r == null ? null : r.ids());
        return ResponseEntity.noContent().build();
    }
}
