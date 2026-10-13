package app.fmate.auth;

import app.fmate.common.ApiException;
import app.fmate.common.Hashing;
import app.fmate.media.StorageService;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;
import org.springframework.transaction.support.TransactionTemplate;

import java.time.OffsetDateTime;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;
import java.util.regex.Pattern;

@Service
public class AuthService {

    private static final Logger log = LoggerFactory.getLogger(AuthService.class);

    public static final Pattern NICKNAME = Pattern.compile("^[A-Za-z0-9가-힣_.]{2,20}$");
    private static final Pattern HAS_LETTER = Pattern.compile("[A-Za-z]");
    private static final Pattern HAS_DIGIT = Pattern.compile("[0-9]");
    private static final Set<String> REQUIRED_CONSENTS = Set.of("AGE_14", "TERMS", "PRIVACY");
    private static final Set<String> ALL_CONSENTS = Set.of("AGE_14", "TERMS", "PRIVACY", "LOCATION", "MARKETING");
    private static final int MAX_FAILED_LOGINS = 5;
    /** 존재하지 않는 계정 로그인 시에도 같은 시간이 걸리도록 비교에 쓰는 더미 해시 */
    private final String dummyHash;

    private final JdbcTemplate jdbc;
    private final PasswordEncoder encoder;
    private final TokenService tokens;
    private final OneTimeCodeService codes;
    private final MailService mail;
    private final SocialVerifier social;
    private final StorageService storage;
    private final TransactionTemplate tx;

    public AuthService(JdbcTemplate jdbc, PasswordEncoder encoder, TokenService tokens, OneTimeCodeService codes,
                       MailService mail, SocialVerifier social, StorageService storage, TransactionTemplate tx) {
        this.jdbc = jdbc;
        this.encoder = encoder;
        this.tokens = tokens;
        this.codes = codes;
        this.mail = mail;
        this.social = social;
        this.storage = storage;
        this.tx = tx;
        this.dummyHash = encoder.encode(Hashing.randomToken(16));
    }

    public record AuthResult(String accessToken, String refreshToken, long expiresIn, long userId,
                             boolean emailVerified, boolean needsProfile) {
    }

    public record Consent(String type, boolean agreed) {
    }

    // ------------------------------------------------------------------ 가입

    public AuthResult signup(String rawEmail, String password, String nickname, List<Consent> consents,
                             String termsVersion, String deviceLabel) {
        String email = normalizeEmail(rawEmail);
        validatePassword(password);
        if (nickname == null || !NICKNAME.matcher(nickname.trim()).matches()) {
            throw ApiException.badRequest("VALIDATION_FAILED", "닉네임은 한글·영문·숫자·_ . 2~20자예요");
        }
        validateConsents(consents, true);
        mail.ensureAvailable();

        long userId = tx.execute(status -> {
            Long id = jdbc.queryForObject(
                    "INSERT INTO users (email, password_hash) VALUES (?, ?) RETURNING id",
                    Long.class, email, encoder.encode(password));
            jdbc.update("INSERT INTO user_profiles (user_id, nickname) VALUES (?, ?)", id, nickname.trim());
            jdbc.update("INSERT INTO notification_settings (user_id) VALUES (?)", id);
            saveConsents(id, consents, termsVersion);
            return id;
        });

        sendVerificationCode(userId, email);
        TokenService.Tokens t = tokens.issueNewSession(userId, deviceLabel);
        return new AuthResult(t.accessToken(), t.refreshToken(), t.expiresInSeconds(), userId, false, false);
    }

    private void sendVerificationCode(long userId, String email) {
        String code = codes.issue(userId, OneTimeCodeService.EMAIL_VERIFY);
        try {
            mail.send(email, "[F-Mate] 이메일 인증 코드",
                    "F-Mate 이메일 인증 코드는 " + code + " 입니다.\n15분 안에 앱에 입력해 주세요.\n"
                            + "본인이 요청하지 않았다면 이 메일을 무시해 주세요.");
        } catch (ApiException e) {
            throw e;
        } catch (Exception e) {
            // 가입은 완료된 상태. 사용자는 앱에서 인증 코드를 다시 받을 수 있다.
            log.warn("verification mail failed for user {}: {}", userId, e.getClass().getSimpleName());
        }
    }

    public void resendVerification(long userId) {
        Map<String, Object> u = jdbc.queryForMap(
                "SELECT email, email_verified_at FROM users WHERE id = ?", userId);
        if (u.get("email_verified_at") != null) throw ApiException.conflict("INVALID_STATE");
        if (u.get("email") == null) throw ApiException.conflict("INVALID_STATE");
        sendVerificationCode(userId, (String) u.get("email"));
    }

    public void verifyEmail(long userId, String code) {
        codes.verify(userId, OneTimeCodeService.EMAIL_VERIFY, code);
        jdbc.update("UPDATE users SET email_verified_at = now() WHERE id = ? AND email_verified_at IS NULL", userId);
    }

    // ------------------------------------------------------------------ 로그인

    private record LoginRow(long id, String hash, String status, int failed, OffsetDateTime lockedUntil,
                            OffsetDateTime suspendedUntil, boolean verified) {
    }

    public AuthResult login(String rawEmail, String password, String deviceLabel) {
        String email = normalizeEmail(rawEmail);
        List<LoginRow> rows = jdbc.query("""
                SELECT u.id, u.password_hash, u.status, u.failed_login_count, u.locked_until, u.suspended_until,
                       u.email_verified_at IS NOT NULL
                  FROM users u WHERE u.email = ?""",
                (rs, i) -> new LoginRow(rs.getLong(1), rs.getString(2), rs.getString(3), rs.getInt(4),
                        rs.getObject(5, OffsetDateTime.class), rs.getObject(6, OffsetDateTime.class), rs.getBoolean(7)),
                email);
        if (rows.isEmpty() || rows.get(0).hash() == null) {
            encoder.matches(password == null ? "" : password, dummyHash);
            throw ApiException.unauthorized("INVALID_CREDENTIALS");
        }
        LoginRow u = rows.get(0);
        if (u.lockedUntil() != null && u.lockedUntil().isAfter(OffsetDateTime.now())) {
            throw new ApiException(org.springframework.http.HttpStatus.LOCKED, "ACCOUNT_LOCKED");
        }
        if (password == null || !encoder.matches(password, u.hash())) {
            int failed = u.failed() + 1;
            if (failed >= MAX_FAILED_LOGINS) {
                jdbc.update("UPDATE users SET failed_login_count = 0, locked_until = now() + interval '15 minutes' WHERE id = ?", u.id());
            } else {
                jdbc.update("UPDATE users SET failed_login_count = ? WHERE id = ?", failed, u.id());
            }
            throw ApiException.unauthorized("INVALID_CREDENTIALS");
        }
        if ("SUSPENDED".equals(u.status())) {
            throw ApiException.forbidden("ACCOUNT_SUSPENDED");
        }
        jdbc.update("UPDATE users SET failed_login_count = 0, locked_until = NULL, last_login_at = now() WHERE id = ?", u.id());
        TokenService.Tokens t = tokens.issueNewSession(u.id(), deviceLabel);
        return new AuthResult(t.accessToken(), t.refreshToken(), t.expiresInSeconds(), u.id(), u.verified(), false);
    }

    public AuthResult refresh(String refreshToken) {
        TokenService.Tokens t = tokens.rotate(refreshToken);
        // 회전 결과에는 사용자 정보가 없으므로 앱은 필요하면 /me 를 다시 조회한다
        return new AuthResult(t.accessToken(), t.refreshToken(), t.expiresInSeconds(), 0, false, false);
    }

    public void logout(long userId, String refreshToken) {
        tokens.revoke(userId, refreshToken);
    }

    // ------------------------------------------------------------------ 소셜 로그인

    public AuthResult socialLogin(String provider, String token, String deviceLabel) {
        SocialVerifier.SocialIdentity id = social.verify(provider, token);
        Long existing = tx.execute(status -> {
            List<Long> found = jdbc.queryForList("""
                    SELECT s.user_id FROM social_accounts s JOIN users u ON u.id = s.user_id
                     WHERE s.provider = ? AND s.provider_user_id = ? AND u.status <> 'DELETED'""",
                    Long.class, id.provider(), id.providerUserId());
            return found.isEmpty() ? null : found.get(0);
        });

        long userId;
        boolean needsProfile;
        if (existing != null) {
            String status = jdbc.queryForObject("SELECT status FROM users WHERE id = ?", String.class, existing);
            if ("SUSPENDED".equals(status)) throw ApiException.forbidden("ACCOUNT_SUSPENDED");
            userId = existing;
            Integer consentCount = jdbc.queryForObject(
                    "SELECT count(DISTINCT consent_type) FROM consents WHERE user_id = ? AND agreed AND consent_type IN ('AGE_14','TERMS','PRIVACY')",
                    Integer.class, userId);
            needsProfile = consentCount == null || consentCount < 3;
        } else {
            // 신규 가입. 공급자가 확인한 이메일이라도 기존 계정과 자동 연결하지 않는다(계정 탈취 방지).
            userId = tx.execute(status -> {
                String email = null;
                if (id.email() != null && id.emailVerified()) {
                    String normalized = id.email().trim().toLowerCase(Locale.ROOT);
                    Integer taken = jdbc.queryForObject("SELECT count(*) FROM users WHERE email = ?", Integer.class, normalized);
                    if (taken != null && taken == 0) email = normalized;
                }
                Long newId = jdbc.queryForObject(
                        "INSERT INTO users (email, email_verified_at) VALUES (?, now()) RETURNING id", Long.class, email);
                jdbc.update("INSERT INTO user_profiles (user_id, nickname) VALUES (?, ?)", newId, "player" + Hashing.randomDigits(8));
                jdbc.update("INSERT INTO notification_settings (user_id) VALUES (?)", newId);
                jdbc.update("INSERT INTO social_accounts (user_id, provider, provider_user_id) VALUES (?, ?, ?)",
                        newId, id.provider(), id.providerUserId());
                return newId;
            });
            needsProfile = true;
        }
        jdbc.update("UPDATE users SET last_login_at = now() WHERE id = ?", userId);
        TokenService.Tokens t = tokens.issueNewSession(userId, deviceLabel);
        return new AuthResult(t.accessToken(), t.refreshToken(), t.expiresInSeconds(), userId, true, needsProfile);
    }

    // ------------------------------------------------------------------ 비밀번호

    public void requestPasswordReset(String rawEmail) {
        String email;
        try {
            email = normalizeEmail(rawEmail);
        } catch (ApiException e) {
            return; // 계정 존재 여부를 알려주지 않는다
        }
        List<Long> ids = jdbc.queryForList(
                "SELECT id FROM users WHERE email = ? AND status = 'ACTIVE' AND password_hash IS NOT NULL", Long.class, email);
        if (ids.isEmpty()) return;
        String code = codes.issue(ids.get(0), OneTimeCodeService.PASSWORD_RESET);
        try {
            mail.send(email, "[F-Mate] 비밀번호 재설정 코드",
                    "비밀번호 재설정 코드는 " + code + " 입니다.\n15분 안에 앱에 입력해 주세요.\n"
                            + "본인이 요청하지 않았다면 이 메일을 무시해 주세요. 비밀번호는 바뀌지 않습니다.");
        } catch (Exception e) {
            log.warn("password reset mail failed: {}", e.getClass().getSimpleName());
        }
    }

    public void resetPassword(String rawEmail, String code, String newPassword) {
        String email = normalizeEmail(rawEmail);
        validatePassword(newPassword);
        List<Long> ids = jdbc.queryForList("SELECT id FROM users WHERE email = ? AND status = 'ACTIVE'", Long.class, email);
        if (ids.isEmpty()) throw ApiException.badRequest("CODE_INVALID");
        long userId = ids.get(0);
        codes.verify(userId, OneTimeCodeService.PASSWORD_RESET, code);
        jdbc.update("UPDATE users SET password_hash = ?, failed_login_count = 0, locked_until = NULL WHERE id = ?",
                encoder.encode(newPassword), userId);
        tokens.revokeAll(userId, "PASSWORD_CHANGED");
    }

    public void changePassword(long userId, String current, String newPassword) {
        validatePassword(newPassword);
        String hash = jdbc.queryForObject("SELECT password_hash FROM users WHERE id = ?", String.class, userId);
        if (hash == null || current == null || !encoder.matches(current, hash)) {
            throw ApiException.badRequest("INVALID_CREDENTIALS");
        }
        jdbc.update("UPDATE users SET password_hash = ? WHERE id = ?", encoder.encode(newPassword), userId);
        tokens.revokeAll(userId, "PASSWORD_CHANGED");
    }

    // ------------------------------------------------------------------ 탈퇴

    public void deleteAccount(long userId, String password) {
        String hash = jdbc.queryForObject("SELECT password_hash FROM users WHERE id = ?", String.class, userId);
        if (hash != null && (password == null || !encoder.matches(password, hash))) {
            throw ApiException.badRequest("INVALID_CREDENTIALS");
        }
        // 삭제 전에 스토리지에서 지울 파일 목록을 모은다
        List<String> keys = jdbc.queryForList("""
                SELECT pm.object_key FROM post_media pm JOIN posts p ON p.id = pm.post_id WHERE p.author_id = ?
                UNION ALL SELECT avatar_object_key FROM user_profiles WHERE user_id = ? AND avatar_object_key IS NOT NULL
                """, String.class, userId, userId);
        tx.executeWithoutResult(status -> {
            jdbc.queryForObject("SELECT 1 FROM fn_delete_account(?)", Integer.class, userId);
            jdbc.update("UPDATE refresh_tokens SET revoked_at = now(), revoke_reason = 'ACCOUNT_DELETED' WHERE user_id = ? AND revoked_at IS NULL", userId);
        });
        storage.deletePublicQuietly(keys);   // 영상 파일은 VideoCleanupJob 이 DELETED 상태 기준으로 삭제
    }

    // ------------------------------------------------------------------ 약관

    public void saveConsents(long userId, List<Consent> consents, String version) {
        if (consents == null) return;
        String v = version == null || version.isBlank() ? "2026-10" : version.trim();
        if (v.length() > 20) v = v.substring(0, 20);
        for (Consent c : consents) {
            if (c == null || !ALL_CONSENTS.contains(c.type())) continue;
            jdbc.update("INSERT INTO consents (user_id, consent_type, version, agreed) VALUES (?, ?, ?, ?)",
                    userId, c.type(), v, c.agreed());
        }
    }

    public static void validateConsents(List<Consent> consents, boolean requireAll) {
        if (!requireAll) return;
        for (String required : REQUIRED_CONSENTS) {
            boolean ok = consents != null && consents.stream()
                    .anyMatch(c -> c != null && required.equals(c.type()) && c.agreed());
            if (!ok) throw ApiException.badRequest("CONSENT_REQUIRED");
        }
    }

    // ------------------------------------------------------------------ 검증

    static String normalizeEmail(String email) {
        if (email == null) throw ApiException.badRequest("VALIDATION_FAILED");
        String e = email.trim().toLowerCase(Locale.ROOT);
        if (e.length() > 254 || !e.matches("^[^\\s@]+@[^\\s@]+\\.[^\\s@]{2,}$")) {
            throw ApiException.badRequest("VALIDATION_FAILED", "올바른 이메일 형식이 아니에요");
        }
        return e;
    }

    static void validatePassword(String password) {
        if (password == null || password.length() < 8 || password.length() > 64
                || !HAS_LETTER.matcher(password).find() || !HAS_DIGIT.matcher(password).find()) {
            throw ApiException.badRequest("WEAK_PASSWORD");
        }
    }
}
