package app.fmate.common;

import org.springframework.http.HttpStatus;

/**
 * API 오류. code 는 앱이 분기 처리에 쓰는 안정적인 문자열 (docs/02-api-spec.md 의 오류 코드 표).
 */
public class ApiException extends RuntimeException {

    private final HttpStatus status;
    private final String code;

    public ApiException(HttpStatus status, String code, String message) {
        super(message);
        this.status = status;
        this.code = code;
    }

    public ApiException(HttpStatus status, String code) {
        this(status, code, ErrorMessages.title(code));
    }

    public HttpStatus status() {
        return status;
    }

    public String code() {
        return code;
    }

    public static ApiException badRequest(String code) {
        return new ApiException(HttpStatus.BAD_REQUEST, code);
    }

    public static ApiException badRequest(String code, String message) {
        return new ApiException(HttpStatus.BAD_REQUEST, code, message);
    }

    public static ApiException unauthorized(String code) {
        return new ApiException(HttpStatus.UNAUTHORIZED, code);
    }

    public static ApiException forbidden(String code) {
        return new ApiException(HttpStatus.FORBIDDEN, code);
    }

    public static ApiException notFound() {
        return new ApiException(HttpStatus.NOT_FOUND, "NOT_FOUND");
    }

    public static ApiException conflict(String code) {
        return new ApiException(HttpStatus.CONFLICT, code);
    }

    public static ApiException conflict(String code, String message) {
        return new ApiException(HttpStatus.CONFLICT, code, message);
    }

    public static ApiException unavailable(String code) {
        return new ApiException(HttpStatus.SERVICE_UNAVAILABLE, code);
    }

    public static ApiException tooMany() {
        return new ApiException(HttpStatus.TOO_MANY_REQUESTS, "RATE_LIMITED");
    }
}
