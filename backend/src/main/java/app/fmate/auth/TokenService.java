package app.fmate.auth;

import app.fmate.common.ApiException;
import app.fmate.common.Hashing;
import app.fmate.config.FmateProperties;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.oauth2.jose.jws.MacAlgorithm;
import org.springframework.security.oauth2.jwt.JwsHeader;
import org.springframework.security.oauth2.jwt.JwtClaimsSet;
import org.springframework.security.oauth2.jwt.JwtEncoder;
import org.springframework.security.oauth2.jwt.JwtEncoderParameters;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.sql.Timestamp;
import java.time.Instant;
import java.time.OffsetDateTime;
import java.util.List;
import java.util.UUID;

/**
 * 액세스 토큰(JWT, 15분) + 리프레시 토큰(불투명, 30일, 해시 저장, 회전·재사용 탐지).
 */
@Service
public class TokenService {

    private final JwtEncoder encoder;
    private final JdbcTemplate jdbc;
    private final FmateProperties props;

    public TokenService(JwtEncoder encoder, JdbcTemplate jdbc, FmateProperties props) {
        this.encoder = encoder;
        this.jdbc = jdbc;
        this.props = props;
    }

    public record Tokens(String accessToken, String refreshToken, long expiresInSeconds) {
    }

    /** 새 로그인 세션 (새 family) */
    @Transactional
    public Tokens issueNewSession(long userId, String deviceLabel) {
        return issue(userId, UUID.randomUUID(), deviceLabel);
    }

    private Tokens issue(long userId, UUID familyId, String deviceLabel) {
        Integer tv = jdbc.queryForObject("SELECT token_version FROM users WHERE id = ?", Integer.class, userId);
        Instant now = Instant.now();
        Instant exp = now.plus(props.jwt().accessTtl());
        JwtClaimsSet claims = JwtClaimsSet.builder()
                .issuer(props.jwt().issuer())
                .subject(Long.toString(userId))
                .issuedAt(now)
                .expiresAt(exp)
                .claim("tv", tv == null ? 0 : tv)
                .build();
        String access = encoder.encode(JwtEncoderParameters.from(
                JwsHeader.with(MacAlgorithm.HS256).build(), claims)).getTokenValue();

        String refresh = Hashing.randomToken(32);
        jdbc.update("""
                INSERT INTO refresh_tokens (user_id, family_id, token_hash, device_label, expires_at)
                VALUES (?, ?, ?, ?, ?)""",
                userId, familyId, Hashing.sha256(refresh),
                deviceLabel == null ? null : deviceLabel.substring(0, Math.min(100, deviceLabel.length())),
                Timestamp.from(now.plus(props.jwt().refreshTtl())));
        return new Tokens(access, refresh, props.jwt().accessTtl().toSeconds());
    }

    private record Row(long id, long userId, UUID familyId, String deviceLabel, OffsetDateTime expiresAt,
                       OffsetDateTime rotatedAt, OffsetDateTime revokedAt) {
    }

    /**
     * 리프레시 회전. 이미 회전된 토큰이 다시 오면 탈취로 보고 같은 family 를 모두 폐기한다.
     */
    @Transactional(noRollbackFor = ApiException.class)
    public Tokens rotate(String refreshToken) {
        if (refreshToken == null || refreshToken.isBlank()) throw ApiException.unauthorized("TOKEN_INVALID");
        List<Row> rows = jdbc.query("""
                SELECT id, user_id, family_id, device_label, expires_at, rotated_at, revoked_at
                  FROM refresh_tokens WHERE token_hash = ? FOR UPDATE""",
                (rs, i) -> new Row(rs.getLong(1), rs.getLong(2), rs.getObject(3, UUID.class), rs.getString(4),
                        rs.getObject(5, OffsetDateTime.class), rs.getObject(6, OffsetDateTime.class),
                        rs.getObject(7, OffsetDateTime.class)),
                (Object) Hashing.sha256(refreshToken));
        if (rows.isEmpty()) throw ApiException.unauthorized("TOKEN_INVALID");
        Row r = rows.get(0);
        if (r.revokedAt() != null) throw ApiException.unauthorized("TOKEN_INVALID");
        if (r.rotatedAt() != null) {
            jdbc.update("""
                    UPDATE refresh_tokens SET revoked_at = now(), revoke_reason = 'REUSE_DETECTED'
                     WHERE family_id = ? AND revoked_at IS NULL""", r.familyId());
            throw ApiException.unauthorized("TOKEN_REUSED");
        }
        if (r.expiresAt().isBefore(OffsetDateTime.now())) throw ApiException.unauthorized("TOKEN_EXPIRED");

        String status = jdbc.queryForObject("SELECT status FROM users WHERE id = ?", String.class, r.userId());
        if (!"ACTIVE".equals(status)) {
            revokeAll(r.userId(), "ADMIN");
            throw ApiException.unauthorized("ACCOUNT_SUSPENDED");
        }
        jdbc.update("UPDATE refresh_tokens SET rotated_at = now() WHERE id = ?", r.id());
        return issue(r.userId(), r.familyId(), r.deviceLabel());
    }

    public void revoke(long userId, String refreshToken) {
        if (refreshToken == null) return;
        jdbc.update("""
                UPDATE refresh_tokens SET revoked_at = now(), revoke_reason = 'LOGOUT'
                 WHERE family_id = (SELECT family_id FROM refresh_tokens WHERE token_hash = ? AND user_id = ?)
                   AND revoked_at IS NULL""",
                Hashing.sha256(refreshToken), userId);
    }

    /** 모든 세션 종료 + 발급된 액세스 토큰 즉시 무효화 */
    public void revokeAll(long userId, String reason) {
        jdbc.update("UPDATE refresh_tokens SET revoked_at = now(), revoke_reason = ? WHERE user_id = ? AND revoked_at IS NULL",
                reason, userId);
        jdbc.update("UPDATE users SET token_version = token_version + 1 WHERE id = ?", userId);
    }
}
