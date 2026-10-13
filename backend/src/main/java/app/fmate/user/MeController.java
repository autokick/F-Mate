package app.fmate.user;

import app.fmate.auth.AuthService;
import app.fmate.auth.AuthUser;
import app.fmate.common.ApiException;
import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;
import org.springframework.http.ResponseEntity;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PatchMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;
import java.util.Map;

@RestController
@RequestMapping("/api/v1")
public class MeController {

    private final UserService users;
    private final AuthService auth;
    private final JdbcTemplate jdbc;

    public MeController(UserService users, AuthService auth, JdbcTemplate jdbc) {
        this.users = users;
        this.auth = auth;
        this.jdbc = jdbc;
    }

    @GetMapping("/me")
    public UserService.Me me(@AuthenticationPrincipal AuthUser me) {
        return users.me(me.id());
    }

    @PatchMapping("/me/profile")
    public UserService.Me updateProfile(@AuthenticationPrincipal AuthUser me, @RequestBody UserService.ProfileUpdate r) {
        users.updateProfile(me.id(), r);
        return users.me(me.id());
    }

    public record AvatarRequest(@Size(max = 300) String objectKey) {
    }

    @PutMapping("/me/avatar")
    public UserService.Me avatar(@AuthenticationPrincipal AuthUser me, @RequestBody AvatarRequest r) {
        users.setAvatar(me.id(), r.objectKey());
        return users.me(me.id());
    }

    public record ConsentsRequest(List<AuthService.Consent> consents, @Size(max = 20) String version) {
    }

    @PostMapping("/me/consents")
    public UserService.Me consents(@AuthenticationPrincipal AuthUser me, @RequestBody ConsentsRequest r) {
        auth.saveConsents(me.id(), r.consents(), r.version());
        return users.me(me.id());
    }

    public record NotificationSettings(boolean reservation, boolean social, boolean chat, boolean marketing) {
    }

    @GetMapping("/me/notification-settings")
    public NotificationSettings getSettings(@AuthenticationPrincipal AuthUser me) {
        jdbc.update("INSERT INTO notification_settings (user_id) VALUES (?) ON CONFLICT DO NOTHING", me.id());
        return jdbc.queryForObject(
                "SELECT reservation, social, chat, marketing FROM notification_settings WHERE user_id = ?",
                (rs, i) -> new NotificationSettings(rs.getBoolean(1), rs.getBoolean(2), rs.getBoolean(3), rs.getBoolean(4)),
                me.id());
    }

    @PutMapping("/me/notification-settings")
    public NotificationSettings putSettings(@AuthenticationPrincipal AuthUser me, @RequestBody NotificationSettings s) {
        jdbc.update("""
                INSERT INTO notification_settings (user_id, reservation, social, chat, marketing) VALUES (?, ?, ?, ?, ?)
                ON CONFLICT (user_id) DO UPDATE SET reservation = EXCLUDED.reservation, social = EXCLUDED.social,
                       chat = EXCLUDED.chat, marketing = EXCLUDED.marketing""",
                me.id(), s.reservation(), s.social(), s.chat(), s.marketing());
        return s;
    }

    public record DeviceRequest(@NotBlank @Size(max = 4096) String fcmToken,
                                @Pattern(regexp = "ANDROID|IOS") String platform) {
    }

    @PostMapping("/me/devices")
    public ResponseEntity<Void> registerDevice(@AuthenticationPrincipal AuthUser me, @Valid @RequestBody DeviceRequest r) {
        jdbc.update("""
                INSERT INTO device_tokens (user_id, fcm_token, platform) VALUES (?, ?, ?)
                ON CONFLICT (fcm_token) DO UPDATE SET user_id = EXCLUDED.user_id, platform = EXCLUDED.platform,
                       last_seen_at = now()""",
                me.id(), r.fcmToken(), r.platform() == null ? "ANDROID" : r.platform());
        return ResponseEntity.noContent().build();
    }

    @PostMapping("/me/devices/remove")
    public ResponseEntity<Void> removeDevice(@AuthenticationPrincipal AuthUser me, @RequestBody Map<String, String> r) {
        jdbc.update("DELETE FROM device_tokens WHERE user_id = ? AND fcm_token = ?", me.id(), r.get("fcmToken"));
        return ResponseEntity.noContent().build();
    }

    public record DeleteAccountRequest(@Size(max = 64) String password, @NotBlank String confirm) {
    }

    /** 회원 탈퇴. confirm 에 "탈퇴" 를 입력해야 한다. 비밀번호 계정은 비밀번호도 필요. */
    @PostMapping("/me/delete")
    public ResponseEntity<Void> delete(@AuthenticationPrincipal AuthUser me, @Valid @RequestBody DeleteAccountRequest r) {
        if (!"탈퇴".equals(r.confirm().trim())) throw ApiException.badRequest("VALIDATION_FAILED");
        auth.deleteAccount(me.id(), r.password());
        return ResponseEntity.noContent().build();
    }

    @GetMapping("/users/{id}")
    public UserService.ProfileView profile(@AuthenticationPrincipal AuthUser me, @PathVariable long id) {
        return users.profile(me.id(), id);
    }

    @GetMapping("/users/search")
    public List<UserSummary> search(@AuthenticationPrincipal AuthUser me, @RequestParam("q") String q) {
        return users.search(me.id(), q, 20);
    }
}
