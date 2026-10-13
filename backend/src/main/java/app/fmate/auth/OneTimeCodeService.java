package app.fmate.auth;

import app.fmate.common.ApiException;
import app.fmate.common.Hashing;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.OffsetDateTime;
import java.util.Arrays;
import java.util.List;

/**
 * 이메일 인증·비밀번호 재설정용 6자리 코드. DB 에는 해시만 저장한다.
 * 유효시간 15분, 코드당 5회까지 시도 가능.
 */
@Service
public class OneTimeCodeService {

    public static final String EMAIL_VERIFY = "EMAIL_VERIFY";
    public static final String PASSWORD_RESET = "PASSWORD_RESET";
    private static final int MAX_ATTEMPTS = 5;

    private final JdbcTemplate jdbc;

    public OneTimeCodeService(JdbcTemplate jdbc) {
        this.jdbc = jdbc;
    }

    @Transactional
    public String issue(long userId, String purpose) {
        // 이전에 발급한 미사용 코드는 무효화
        jdbc.update("UPDATE one_time_tokens SET used_at = now() WHERE user_id = ? AND purpose = ? AND used_at IS NULL",
                userId, purpose);
        String code = Hashing.randomDigits(6);
        jdbc.update("""
                INSERT INTO one_time_tokens (user_id, purpose, token_hash, expires_at)
                VALUES (?, ?, ?, now() + interval '15 minutes')""",
                userId, purpose, hash(userId, purpose, code));
        return code;
    }

    private record Row(long id, byte[] hash, OffsetDateTime expiresAt, int attempts) {
    }

    /** 코드가 맞으면 사용 처리. 틀리면 예외(시도 횟수 증가). */
    @Transactional(noRollbackFor = ApiException.class)
    public void verify(long userId, String purpose, String code) {
        if (code == null || !code.matches("\\d{6}")) throw ApiException.badRequest("CODE_INVALID");
        List<Row> rows = jdbc.query("""
                SELECT id, token_hash, expires_at, attempt_count FROM one_time_tokens
                 WHERE user_id = ? AND purpose = ? AND used_at IS NULL
                 ORDER BY id DESC LIMIT 1 FOR UPDATE""",
                (rs, i) -> new Row(rs.getLong(1), rs.getBytes(2),
                        rs.getObject(3, OffsetDateTime.class), rs.getInt(4)),
                userId, purpose);
        if (rows.isEmpty()) throw ApiException.badRequest("CODE_INVALID");
        Row r = rows.get(0);
        if (r.expiresAt().isBefore(OffsetDateTime.now())) throw ApiException.badRequest("CODE_EXPIRED");
        if (r.attempts() >= MAX_ATTEMPTS) throw ApiException.badRequest("CODE_ATTEMPTS_EXCEEDED");
        if (!Arrays.equals(r.hash(), hash(userId, purpose, code))) {
            jdbc.update("UPDATE one_time_tokens SET attempt_count = attempt_count + 1 WHERE id = ?", r.id());
            throw ApiException.badRequest(r.attempts() + 1 >= MAX_ATTEMPTS ? "CODE_ATTEMPTS_EXCEEDED" : "CODE_INVALID");
        }
        jdbc.update("UPDATE one_time_tokens SET used_at = now() WHERE id = ?", r.id());
    }

    private static byte[] hash(long userId, String purpose, String code) {
        return Hashing.sha256(userId + ":" + purpose + ":" + code);
    }
}
