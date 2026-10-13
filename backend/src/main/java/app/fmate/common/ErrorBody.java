package app.fmate.common;

import java.util.Map;

/** RFC 9457 Problem Details 기반 오류 응답 본문 */
public record ErrorBody(
        String type,
        String title,
        int status,
        String code,
        String requestId,
        Map<String, String> fieldErrors
) {
    public static ErrorBody of(ApiException e, String requestId) {
        return new ErrorBody(
                "https://fmate.app/errors/" + e.code().toLowerCase().replace('_', '-'),
                e.getMessage(),
                e.status().value(),
                e.code(),
                requestId,
                null);
    }
}
