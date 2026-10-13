package app.fmate.auth;

import app.fmate.common.ApiException;
import app.fmate.common.RateLimiter;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.time.Duration;
import java.util.List;
import java.util.Locale;

@RestController
@RequestMapping("/api/v1/auth")
public class AuthController {

    private final AuthService auth;
    private final RateLimiter limiter;

    public AuthController(AuthService auth, RateLimiter limiter) {
        this.auth = auth;
        this.limiter = limiter;
    }

    public record SignupRequest(
            @NotBlank @Size(max = 254) String email,
            @NotBlank @Size(max = 64) String password,
            @NotBlank @Size(max = 20) String nickname,
            List<AuthService.Consent> consents,
            @Size(max = 20) String termsVersion,
            @Size(max = 100) String deviceLabel) {
    }

    public record LoginRequest(@NotBlank @Size(max = 254) String email, @NotBlank @Size(max = 64) String password,
                               @Size(max = 100) String deviceLabel) {
    }

    public record RefreshRequest(@NotBlank String refreshToken) {
    }

    public record LogoutRequest(String refreshToken) {
    }

    public record CodeRequest(@NotBlank @Size(min = 6, max = 6) String code) {
    }

    public record EmailRequest(@NotBlank @Size(max = 254) String email) {
    }

    public record ResetRequest(@NotBlank String email, @NotBlank @Size(min = 6, max = 6) String code,
                               @NotBlank @Size(max = 64) String newPassword) {
    }

    public record ChangePasswordRequest(@NotBlank String currentPassword, @NotBlank @Size(max = 64) String newPassword) {
    }

    public record SocialRequest(@NotBlank @Size(max = 4096) String token, @Size(max = 100) String deviceLabel) {
    }

    @PostMapping("/signup")
    public ResponseEntity<AuthService.AuthResult> signup(@Valid @RequestBody SignupRequest r, HttpServletRequest req) {
        limiter.check("signup", req.getRemoteAddr(), 10, Duration.ofHours(1));
        return ResponseEntity.status(HttpStatus.CREATED).body(
                auth.signup(r.email(), r.password(), r.nickname(), r.consents(), r.termsVersion(), r.deviceLabel()));
    }

    @PostMapping("/login")
    public AuthService.AuthResult login(@Valid @RequestBody LoginRequest r, HttpServletRequest req) {
        limiter.check("login-ip", req.getRemoteAddr(), 30, Duration.ofMinutes(10));
        limiter.check("login-email", r.email().trim().toLowerCase(Locale.ROOT), 10, Duration.ofMinutes(10));
        return auth.login(r.email(), r.password(), r.deviceLabel());
    }

    @PostMapping("/refresh")
    public AuthService.AuthResult refresh(@Valid @RequestBody RefreshRequest r, HttpServletRequest req) {
        limiter.check("refresh", req.getRemoteAddr(), 120, Duration.ofMinutes(10));
        return auth.refresh(r.refreshToken());
    }

    @PostMapping("/logout")
    public ResponseEntity<Void> logout(@AuthenticationPrincipal AuthUser me, @RequestBody(required = false) LogoutRequest r) {
        auth.logout(me.id(), r == null ? null : r.refreshToken());
        return ResponseEntity.noContent().build();
    }

    @PostMapping("/email/verify")
    public ResponseEntity<Void> verifyEmail(@AuthenticationPrincipal AuthUser me, @Valid @RequestBody CodeRequest r) {
        limiter.check("verify", Long.toString(me.id()), 20, Duration.ofHours(1));
        auth.verifyEmail(me.id(), r.code());
        return ResponseEntity.noContent().build();
    }

    @PostMapping("/email/resend")
    public ResponseEntity<Void> resend(@AuthenticationPrincipal AuthUser me) {
        limiter.check("resend-minute", Long.toString(me.id()), 1, Duration.ofMinutes(1));
        limiter.check("resend-day", Long.toString(me.id()), 5, Duration.ofDays(1));
        auth.resendVerification(me.id());
        return ResponseEntity.noContent().build();
    }

    @PostMapping("/password/reset-request")
    public ResponseEntity<Void> resetRequest(@Valid @RequestBody EmailRequest r, HttpServletRequest req) {
        limiter.check("reset-ip", req.getRemoteAddr(), 10, Duration.ofHours(1));
        limiter.check("reset-email", r.email().trim().toLowerCase(Locale.ROOT), 3, Duration.ofHours(1));
        auth.requestPasswordReset(r.email());
        return ResponseEntity.accepted().build();   // 계정 존재 여부와 무관하게 같은 응답
    }

    @PostMapping("/password/reset")
    public ResponseEntity<Void> reset(@Valid @RequestBody ResetRequest r, HttpServletRequest req) {
        limiter.check("reset-confirm", req.getRemoteAddr(), 20, Duration.ofHours(1));
        auth.resetPassword(r.email(), r.code(), r.newPassword());
        return ResponseEntity.noContent().build();
    }

    @PutMapping("/password")
    public ResponseEntity<Void> change(@AuthenticationPrincipal AuthUser me, @Valid @RequestBody ChangePasswordRequest r) {
        limiter.check("change-pw", Long.toString(me.id()), 10, Duration.ofHours(1));
        auth.changePassword(me.id(), r.currentPassword(), r.newPassword());
        return ResponseEntity.noContent().build();
    }

    @PostMapping("/social/{provider}")
    public AuthService.AuthResult social(@PathVariable String provider, @Valid @RequestBody SocialRequest r,
                                         HttpServletRequest req) {
        limiter.check("social", req.getRemoteAddr(), 30, Duration.ofMinutes(10));
        String p = provider.toUpperCase(Locale.ROOT);
        if (!List.of("KAKAO", "GOOGLE", "APPLE").contains(p)) throw ApiException.notFound();
        return auth.socialLogin(p, r.token(), r.deviceLabel());
    }
}
