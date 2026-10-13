package app.fmate.common;

import app.fmate.config.FmateProperties;
import org.junit.jupiter.api.Test;
import org.springframework.dao.DataIntegrityViolationException;

import java.sql.SQLException;
import java.time.Duration;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

/** 스프링 컨텍스트 없이 도는 단위 테스트 */
class UnitTests {

    private static FmateProperties props(boolean rateLimit) {
        return new FmateProperties(true, rateLimit, "http://localhost", "", null, null, null, null, null, null, null, null);
    }

    @Test
    void 요청제한은_한도를_넘으면_429() {
        RateLimiter limiter = new RateLimiter(props(true));
        for (int i = 0; i < 3; i++) limiter.check("t", "k", 3, Duration.ofMinutes(1));
        assertThatThrownBy(() -> limiter.check("t", "k", 3, Duration.ofMinutes(1)))
                .isInstanceOf(ApiException.class)
                .extracting(e -> ((ApiException) e).code()).isEqualTo("RATE_LIMITED");
        // 다른 키는 별도 계산
        limiter.check("t", "other", 3, Duration.ofMinutes(1));
    }

    @Test
    void 요청제한_비활성화() {
        RateLimiter limiter = new RateLimiter(props(false));
        for (int i = 0; i < 100; i++) limiter.check("t", "k", 1, Duration.ofMinutes(1));
    }

    private static DataIntegrityViolationException db(String state, String message) {
        return new DataIntegrityViolationException("x", new SQLException(message, state));
    }

    @Test
    void DB_오류_변환() {
        assertThat(DbErrors.translate(db("23P01", "ERROR: conflicting key value violates exclusion constraint \"no_double_booking\"")))
                .get().extracting(ApiException::code).isEqualTo("SLOT_TAKEN");
        assertThat(DbErrors.translate(db("P0001", "ERROR: HOLD_LIMIT\n  Where: PL/pgSQL function")))
                .get().extracting(ApiException::code).isEqualTo("HOLD_LIMIT");
        assertThat(DbErrors.translate(db("23514", "ERROR: BLOCKED")))
                .get().extracting(ApiException::code).isEqualTo("BLOCKED");
        assertThat(DbErrors.translate(db("23505", "ERROR: duplicate key value violates unique constraint \"ux_users_email\"")))
                .get().extracting(ApiException::code).isEqualTo("EMAIL_TAKEN");
        assertThat(DbErrors.translate(db("23514", "ERROR: illegal reservation transition CONFIRMED -> PENDING_PAYMENT")))
                .get().extracting(ApiException::code).isEqualTo("INVALID_STATE");
        assertThat(DbErrors.translate(db("23514", "ERROR: new row violates check constraint \"nickname_format\"")))
                .get().extracting(ApiException::code).isEqualTo("VALIDATION_FAILED");
        assertThat(DbErrors.translate(new RuntimeException("not sql"))).isEmpty();
    }

    @Test
    void 해시와_코드() {
        assertThat(Hashing.randomDigits(6)).matches("\\d{6}");
        assertThat(Hashing.randomToken(32)).hasSizeGreaterThanOrEqualTo(43);
        assertThat(Hashing.constantTimeEquals("abc", "abc")).isTrue();
        assertThat(Hashing.constantTimeEquals("abc", "abd")).isFalse();
        assertThat(Hashing.constantTimeEquals(null, "abc")).isFalse();
    }
}
