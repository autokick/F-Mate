package app.fmate.common;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Service;

import java.util.Arrays;
import java.util.List;
import java.util.function.Supplier;
import java.util.regex.Pattern;

/**
 * 상태를 바꾸는 POST 요청의 멱등 처리.
 * 같은 (사용자, 엔드포인트, Idempotency-Key) 로 다시 오면 처음 결과를 그대로 돌려준다.
 * 같은 키 + 다른 본문 → 422, 처리 중 중복 요청 → 409.
 */
@Service
public class IdempotencyService {

    private static final Pattern KEY = Pattern.compile("^[A-Za-z0-9_-]{8,80}$");

    private final JdbcTemplate jdbc;
    private final ObjectMapper mapper;

    public IdempotencyService(JdbcTemplate jdbc, ObjectMapper mapper) {
        this.jdbc = jdbc;
        this.mapper = mapper;
    }

    public ResponseEntity<?> execute(long userId, String endpoint, String key, Object request,
                                     Supplier<ResponseEntity<?>> action) {
        if (key == null || !KEY.matcher(key).matches()) {
            throw ApiException.badRequest("IDEMPOTENCY_KEY_REQUIRED");
        }
        byte[] hash = Hashing.sha256(toJson(request));

        int inserted = jdbc.update("""
                INSERT INTO idempotency_keys (user_id, idem_key, endpoint, request_hash)
                VALUES (?, ?, ?, ?) ON CONFLICT DO NOTHING""", userId, key, endpoint, hash);

        if (inserted == 0) {
            record Stored(byte[] hash, Integer status, String body) {
            }
            List<Stored> rows = jdbc.query("""
                    SELECT request_hash, response_status, response_body::text AS body
                      FROM idempotency_keys WHERE user_id = ? AND endpoint = ? AND idem_key = ?""",
                    (rs, i) -> new Stored(rs.getBytes(1), (Integer) rs.getObject(2), rs.getString(3)),
                    userId, endpoint, key);
            if (rows.isEmpty()) throw ApiException.conflict("IDEMPOTENCY_IN_PROGRESS");
            Stored s = rows.get(0);
            if (!Arrays.equals(s.hash(), hash)) {
                throw new ApiException(HttpStatus.UNPROCESSABLE_ENTITY, "IDEMPOTENCY_CONFLICT");
            }
            if (s.status() == null) throw ApiException.conflict("IDEMPOTENCY_IN_PROGRESS");
            JsonNode body = parse(s.body());
            return ResponseEntity.status(s.status()).body(body);
        }

        ResponseEntity<?> response;
        try {
            response = action.get();
        } catch (RuntimeException e) {
            // 실패한 요청은 같은 키로 다시 시도할 수 있게 지운다
            jdbc.update("DELETE FROM idempotency_keys WHERE user_id = ? AND endpoint = ? AND idem_key = ?",
                    userId, endpoint, key);
            throw e;
        }
        jdbc.update("""
                UPDATE idempotency_keys SET response_status = ?, response_body = ?::jsonb
                 WHERE user_id = ? AND endpoint = ? AND idem_key = ?""",
                response.getStatusCode().value(), toJson(response.getBody()), userId, endpoint, key);
        return response;
    }

    @Scheduled(cron = "0 15 4 * * *", zone = "Asia/Seoul")
    void purgeOld() {
        jdbc.update("DELETE FROM idempotency_keys WHERE created_at < now() - interval '2 days'");
    }

    private String toJson(Object o) {
        try {
            return mapper.writeValueAsString(o);
        } catch (JsonProcessingException e) {
            throw new IllegalStateException(e);
        }
    }

    private JsonNode parse(String json) {
        try {
            return json == null ? null : mapper.readTree(json);
        } catch (JsonProcessingException e) {
            throw new IllegalStateException(e);
        }
    }
}
