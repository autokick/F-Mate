package app.fmate.common;

import java.util.Map;

/** 오류 코드별 사용자 안내 문구 (한국어). 앱은 code 로 분기하고, 문구는 그대로 보여줘도 되게 작성한다. */
public final class ErrorMessages {

    private ErrorMessages() {
    }

    private static final Map<String, String> TITLES = Map.ofEntries(
            Map.entry("VALIDATION_FAILED", "입력값을 확인해 주세요"),
            Map.entry("BAD_REQUEST", "잘못된 요청이에요"),
            Map.entry("UNAUTHENTICATED", "로그인이 필요해요"),
            Map.entry("TOKEN_EXPIRED", "로그인이 만료되었어요"),
            Map.entry("TOKEN_INVALID", "로그인 정보가 올바르지 않아요"),
            Map.entry("TOKEN_REUSED", "보안을 위해 다시 로그인해 주세요"),
            Map.entry("INVALID_CREDENTIALS", "이메일 또는 비밀번호가 올바르지 않아요"),
            Map.entry("ACCOUNT_LOCKED", "로그인 시도가 많아 잠시 잠겼어요. 15분 뒤 다시 시도해 주세요"),
            Map.entry("ACCOUNT_SUSPENDED", "이용이 제한된 계정이에요"),
            Map.entry("ACCOUNT_NOT_ALLOWED", "이메일 인증을 마친 계정만 이용할 수 있어요"),
            Map.entry("EMAIL_NOT_VERIFIED", "이메일 인증을 먼저 완료해 주세요"),
            Map.entry("EMAIL_TAKEN", "이미 가입된 이메일이에요"),
            Map.entry("NICKNAME_TAKEN", "이미 사용 중인 닉네임이에요"),
            Map.entry("WEAK_PASSWORD", "비밀번호는 영문과 숫자를 포함해 8자 이상이어야 해요"),
            Map.entry("CONSENT_REQUIRED", "필수 약관에 동의해 주세요"),
            Map.entry("CODE_INVALID", "인증 코드가 올바르지 않아요"),
            Map.entry("CODE_EXPIRED", "인증 코드가 만료되었어요. 다시 받아 주세요"),
            Map.entry("CODE_ATTEMPTS_EXCEEDED", "시도 횟수를 넘었어요. 코드를 다시 받아 주세요"),
            Map.entry("EMAIL_NOT_CONFIGURED", "메일 발송이 아직 설정되지 않았어요"),
            Map.entry("SOCIAL_NOT_CONFIGURED", "이 로그인 방식은 아직 준비 중이에요"),
            Map.entry("PLACES_NOT_CONFIGURED", "주변 구장 검색은 아직 준비 중이에요"),
            Map.entry("PLACES_UNAVAILABLE", "주변 구장 정보를 불러오지 못했어요. 잠시 후 다시 시도해 주세요"),
            Map.entry("SOCIAL_TOKEN_INVALID", "소셜 로그인 정보를 확인할 수 없어요"),
            Map.entry("FORBIDDEN", "권한이 없어요"),
            Map.entry("BLOCKED", "차단 관계인 사용자와는 할 수 없어요"),
            Map.entry("NOT_FOUND", "찾을 수 없어요"),
            Map.entry("SLOT_TAKEN", "방금 다른 분이 예약한 시간이에요"),
            Map.entry("SLOT_UNAVAILABLE", "예약할 수 없는 시간이에요"),
            Map.entry("SLOT_HAS_RESERVATION", "예약이 있는 시간은 변경할 수 없어요"),
            Map.entry("HOLD_LIMIT", "결제 대기 중인 예약이 너무 많아요. 먼저 결제하거나 취소해 주세요"),
            Map.entry("HOLD_EXPIRED", "결제 시간이 지나 예약이 만료되었어요"),
            Map.entry("VENUE_NOT_BOOKABLE", "지금은 예약을 받지 않는 구장이에요"),
            Map.entry("INVALID_STATE", "지금 상태에서는 할 수 없는 작업이에요"),
            Map.entry("NOT_CANCELABLE", "이용 시작 이후에는 취소할 수 없어요"),
            Map.entry("HAS_ACTIVE_RESERVATIONS", "진행 중인 예약이 있어 탈퇴할 수 없어요. 먼저 예약을 취소해 주세요"),
            Map.entry("HAS_PENDING_REFUNDS", "환불이 진행 중이에요. 환불 완료 후 탈퇴할 수 있어요"),
            Map.entry("AMOUNT_MISMATCH", "결제 금액이 올바르지 않아요"),
            Map.entry("PAYMENT_NOT_CONFIGURED", "결제 기능이 아직 준비 중이에요"),
            Map.entry("PAYMENT_FAILED", "결제에 실패했어요"),
            Map.entry("PAYMENT_PENDING", "결제 결과를 확인하고 있어요"),
            Map.entry("MEDIA_NOT_CONFIGURED", "사진·영상 업로드가 아직 준비 중이에요"),
            Map.entry("UPLOAD_NOT_FOUND", "업로드된 파일을 찾을 수 없어요"),
            Map.entry("UNSUPPORTED_MEDIA", "지원하지 않는 파일 형식이에요"),
            Map.entry("FILE_TOO_LARGE", "파일 용량이 너무 커요"),
            Map.entry("ALREADY_REPORTED", "이미 신고한 내용이에요"),
            Map.entry("DUPLICATE", "이미 처리된 요청이에요"),
            Map.entry("IDEMPOTENCY_KEY_REQUIRED", "요청 식별 키가 필요해요"),
            Map.entry("IDEMPOTENCY_CONFLICT", "같은 요청 키로 다른 내용을 보낼 수 없어요"),
            Map.entry("IDEMPOTENCY_IN_PROGRESS", "같은 요청을 처리하고 있어요"),
            Map.entry("RATE_LIMITED", "요청이 너무 많아요. 잠시 후 다시 시도해 주세요"),
            Map.entry("RETRY", "잠시 후 다시 시도해 주세요"),
            Map.entry("INVALID_TARGET", "대상이 올바르지 않아요"),
            Map.entry("INTERNAL", "일시적인 오류가 발생했어요")
    );

    public static String title(String code) {
        return TITLES.getOrDefault(code, TITLES.get("INTERNAL"));
    }
}
