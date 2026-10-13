package app.fmate.common;

import org.springframework.http.HttpStatus;

import java.sql.SQLException;
import java.util.Map;
import java.util.Optional;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * DB 함수·트리거·제약이 던진 오류를 API 오류로 변환한다.
 * DB 함수는 'SLOT_UNAVAILABLE' 처럼 오류 코드로 시작하는 메시지로 예외를 올린다 (V3 주석 참고).
 */
public final class DbErrors {

    private DbErrors() {
    }

    private static final Pattern CODE = Pattern.compile("ERROR:\\s+([A-Z][A-Z_]+)\\b");

    /** DB 함수 메시지 코드 → HTTP 상태 */
    private static final Map<String, HttpStatus> FUNCTION_CODES = Map.ofEntries(
            Map.entry("SLOT_UNAVAILABLE", HttpStatus.CONFLICT),
            Map.entry("SLOT_HAS_RESERVATION", HttpStatus.CONFLICT),
            Map.entry("HOLD_LIMIT", HttpStatus.CONFLICT),
            Map.entry("HOLD_EXPIRED", HttpStatus.CONFLICT),
            Map.entry("VENUE_NOT_BOOKABLE", HttpStatus.CONFLICT),
            Map.entry("ACCOUNT_NOT_ALLOWED", HttpStatus.FORBIDDEN),
            Map.entry("INVALID_STATE", HttpStatus.CONFLICT),
            Map.entry("NOT_CANCELABLE", HttpStatus.CONFLICT),
            Map.entry("FORBIDDEN", HttpStatus.FORBIDDEN),
            Map.entry("BLOCKED", HttpStatus.FORBIDDEN),
            Map.entry("INVALID_TARGET", HttpStatus.BAD_REQUEST),
            Map.entry("HAS_ACTIVE_RESERVATIONS", HttpStatus.CONFLICT),
            Map.entry("HAS_PENDING_REFUNDS", HttpStatus.CONFLICT)
    );

    /** 유일 제약 이름 → 오류 코드 */
    private static final Map<String, String> UNIQUE_CONSTRAINTS = Map.of(
            "ux_users_email", "EMAIL_TAKEN",
            "ux_profiles_nickname", "NICKNAME_TAKEN",
            "ux_reports_open", "ALREADY_REPORTED",
            "ux_payments_one_captured_per_reservation", "INVALID_STATE"
    );

    public static Optional<ApiException> translate(Throwable t) {
        SQLException sql = findSql(t);
        if (sql == null) return Optional.empty();
        String state = sql.getSQLState() == null ? "" : sql.getSQLState();
        String message = sql.getMessage() == null ? "" : sql.getMessage();

        switch (state) {
            case "23P01":
                return Optional.of(ApiException.conflict("SLOT_TAKEN"));
            case "23505": {
                for (var e : UNIQUE_CONSTRAINTS.entrySet()) {
                    if (message.contains(e.getKey())) {
                        return Optional.of(new ApiException(HttpStatus.CONFLICT, e.getValue()));
                    }
                }
                return Optional.of(ApiException.conflict("DUPLICATE"));
            }
            case "23503":
                return Optional.of(ApiException.notFound());
            case "40P01":
            case "40001":
                return Optional.of(ApiException.unavailable("RETRY"));
            default:
                break;
        }

        Matcher m = CODE.matcher(message);
        if (m.find()) {
            String code = m.group(1);
            HttpStatus status = FUNCTION_CODES.get(code);
            if (status != null) return Optional.of(new ApiException(status, code));
        }
        // 상태 머신 트리거가 막은 전이 (예: illegal reservation transition A -> B)
        if (message.contains("illegal ") && message.contains("transition")) {
            return Optional.of(ApiException.conflict("INVALID_STATE"));
        }
        // 그 외 체크 제약 위반은 입력 오류로 본다 (상세 메시지는 노출하지 않음)
        if ("23514".equals(state) || "22001".equals(state) || "22P02".equals(state) || "22023".equals(state)) {
            return Optional.of(ApiException.badRequest("VALIDATION_FAILED"));
        }
        return Optional.empty();
    }

    private static SQLException findSql(Throwable t) {
        Throwable cur = t;
        int depth = 0;
        while (cur != null && depth++ < 10) {
            if (cur instanceof SQLException s) return s;
            cur = cur.getCause();
        }
        return null;
    }
}
