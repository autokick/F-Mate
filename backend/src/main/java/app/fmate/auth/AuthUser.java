package app.fmate.auth;

/** 인증된 사용자 (컨트롤러에서 @AuthenticationPrincipal 로 받는다). role 은 매 요청 DB 값. */
public record AuthUser(long id, String role, boolean emailVerified) {

    public boolean isAdmin() {
        return "ADMIN".equals(role);
    }

    public boolean isModerator() {
        return "ADMIN".equals(role) || "MODERATOR".equals(role);
    }
}
