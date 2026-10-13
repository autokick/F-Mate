package app.fmate.chat;

import app.fmate.auth.AuthUser;
import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;

/** 채팅 REST. 실시간 송수신은 WebSocket(/ws/chat), 이 API 는 목록·이력·오프라인 전송용 */
@RestController
@RequestMapping("/api/v1/chats")
public class ChatController {

    private final ChatService chats;

    public ChatController(ChatService chats) {
        this.chats = chats;
    }

    public record OpenRequest(@NotNull Long userId) {
    }

    @PostMapping
    public ChatService.ChatSummary open(@AuthenticationPrincipal AuthUser me, @Valid @RequestBody OpenRequest r) {
        return chats.open(me.id(), r.userId());
    }

    @GetMapping
    public List<ChatService.ChatSummary> list(@AuthenticationPrincipal AuthUser me) {
        return chats.list(me.id());
    }

    @GetMapping("/{id}")
    public ChatService.ChatSummary get(@AuthenticationPrincipal AuthUser me, @PathVariable long id) {
        return chats.summary(me.id(), id);
    }

    @GetMapping("/{id}/messages")
    public List<ChatService.MessageView> messages(@AuthenticationPrincipal AuthUser me, @PathVariable long id,
                                                  @RequestParam(required = false) Long before,
                                                  @RequestParam(required = false) Long after,
                                                  @RequestParam(defaultValue = "50") int limit) {
        return chats.messages(me.id(), id, before, after, limit);
    }

    public record SendRequest(@NotBlank String clientMessageId, @NotBlank String body) {
    }

    @PostMapping("/{id}/messages")
    public ChatService.MessageView send(@AuthenticationPrincipal AuthUser me, @PathVariable long id,
                                        @Valid @RequestBody SendRequest r) {
        return chats.send(me.id(), id, r.clientMessageId(), r.body());
    }

    public record ReadRequest(@NotNull Long messageId) {
    }

    @PostMapping("/{id}/read")
    public ResponseEntity<Void> read(@AuthenticationPrincipal AuthUser me, @PathVariable long id,
                                     @Valid @RequestBody ReadRequest r) {
        chats.markRead(me.id(), id, r.messageId());
        return ResponseEntity.noContent().build();
    }

    @PostMapping("/{id}/hide")
    public ResponseEntity<Void> hide(@AuthenticationPrincipal AuthUser me, @PathVariable long id) {
        chats.hide(me.id(), id);
        return ResponseEntity.noContent().build();
    }

    public record MuteRequest(boolean muted) {
    }

    @PostMapping("/{id}/mute")
    public ResponseEntity<Void> mute(@AuthenticationPrincipal AuthUser me, @PathVariable long id, @RequestBody MuteRequest r) {
        chats.mute(me.id(), id, r.muted());
        return ResponseEntity.noContent().build();
    }
}
