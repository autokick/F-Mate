package app.fmate.auth;

import org.springframework.core.convert.converter.Converter;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.authentication.AbstractAuthenticationToken;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.GrantedAuthority;
import org.springframework.security.core.authority.SimpleGrantedAuthority;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.security.oauth2.server.resource.InvalidBearerTokenException;
import org.springframework.stereotype.Component;

import java.util.ArrayList;
import java.util.List;

/**
 * JWT → 인증 객체. 매 요청 DB 에서 계정 상태와 token_version 을 확인해
 * 탈퇴·정지·비밀번호 변경 직후 이전 토큰을 즉시 무효화한다.
 */
@Component
public class JwtAuthConverter implements Converter<Jwt, AbstractAuthenticationToken> {

    private final JdbcTemplate jdbc;

    public JwtAuthConverter(JdbcTemplate jdbc) {
        this.jdbc = jdbc;
    }

    private record Row(String status, int tokenVersion, String role, boolean verified) {
    }

    @Override
    public AbstractAuthenticationToken convert(Jwt jwt) {
        long userId;
        try {
            userId = Long.parseLong(jwt.getSubject());
        } catch (NumberFormatException e) {
            throw new InvalidBearerTokenException("bad subject");
        }
        Object tvClaim = jwt.getClaim("tv");
        int tv = tvClaim instanceof Number n ? n.intValue() : -1;

        List<Row> rows = jdbc.query(
                "SELECT status, token_version, role, email_verified_at IS NOT NULL FROM users WHERE id = ?",
                (rs, i) -> new Row(rs.getString(1), rs.getInt(2), rs.getString(3), rs.getBoolean(4)),
                userId);
        if (rows.isEmpty()) throw new InvalidBearerTokenException("unknown user");
        Row row = rows.get(0);
        if (row.tokenVersion() != tv || "DELETED".equals(row.status())) {
            throw new InvalidBearerTokenException("revoked");
        }
        if ("SUSPENDED".equals(row.status())) {
            throw new InvalidBearerTokenException("suspended");
        }

        AuthUser principal = new AuthUser(userId, row.role(), row.verified());
        List<GrantedAuthority> authorities = new ArrayList<>();
        authorities.add(new SimpleGrantedAuthority("ROLE_" + row.role()));
        if ("ADMIN".equals(row.role())) authorities.add(new SimpleGrantedAuthority("ROLE_MODERATOR"));
        return new UsernamePasswordAuthenticationToken(principal, jwt, authorities);
    }
}
