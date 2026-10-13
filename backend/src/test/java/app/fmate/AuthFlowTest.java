package app.fmate;

import app.fmate.auth.OneTimeCodeService;
import com.fasterxml.jackson.databind.JsonNode;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.MvcResult;

import java.util.Map;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put;

class AuthFlowTest extends IntegrationTest {

    @Autowired
    OneTimeCodeService codes;

    private MvcResult login(String email, String password) throws Exception {
        return mvc.perform(post("/api/v1/auth/login").contentType(MediaType.APPLICATION_JSON)
                .content(json(Map.of("email", email, "password", password)))).andReturn();
    }

    private MvcResult refresh(String token) throws Exception {
        return mvc.perform(post("/api/v1/auth/refresh").contentType(MediaType.APPLICATION_JSON)
                .content(json(Map.of("refreshToken", token)))).andReturn();
    }

    @Test
    void 가입_로그인_내정보() throws Exception {
        Session s = signup("flow1@fmate.test");
        JsonNode me = read(me(s));
        assertThat(me.get("email").asText()).isEqualTo("flow1@fmate.test");
        assertThat(me.get("emailVerified").asBoolean()).isFalse();
        assertThat(me.get("needsProfile").asBoolean()).isFalse();

        MvcResult ok = login("FLOW1@fmate.test", "abc12345");
        assertThat(ok.getResponse().getStatus()).as("대소문자 무시 로그인").isEqualTo(200);
    }

    @Test
    void 중복_이메일과_약한_비밀번호_거부() throws Exception {
        signup("dup@fmate.test");
        MvcResult dup = mvc.perform(post("/api/v1/auth/signup").contentType(MediaType.APPLICATION_JSON)
                .content(json(Map.of("email", "DUP@fmate.test", "password", "abc12345", "nickname", "다른닉네임",
                        "consents", new Object[]{Map.of("type", "AGE_14", "agreed", true),
                                Map.of("type", "TERMS", "agreed", true), Map.of("type", "PRIVACY", "agreed", true)}))))
                .andReturn();
        assertThat(dup.getResponse().getStatus()).isEqualTo(409);
        assertThat(read(dup).get("code").asText()).isEqualTo("EMAIL_TAKEN");

        MvcResult weak = mvc.perform(post("/api/v1/auth/signup").contentType(MediaType.APPLICATION_JSON)
                .content(json(Map.of("email", "weak@fmate.test", "password", "abcdefgh", "nickname", "약한비번",
                        "consents", new Object[]{Map.of("type", "AGE_14", "agreed", true),
                                Map.of("type", "TERMS", "agreed", true), Map.of("type", "PRIVACY", "agreed", true)}))))
                .andReturn();
        assertThat(read(weak).get("code").asText()).isEqualTo("WEAK_PASSWORD");

        MvcResult noConsent = mvc.perform(post("/api/v1/auth/signup").contentType(MediaType.APPLICATION_JSON)
                .content(json(Map.of("email", "noconsent@fmate.test", "password", "abc12345", "nickname", "동의안함"))))
                .andReturn();
        assertThat(read(noConsent).get("code").asText()).isEqualTo("CONSENT_REQUIRED");
    }

    @Test
    void 로그인_5회_실패하면_잠금() throws Exception {
        signup("lock@fmate.test");
        for (int i = 0; i < 5; i++) {
            assertThat(login("lock@fmate.test", "wrong1234").getResponse().getStatus()).isEqualTo(401);
        }
        MvcResult locked = login("lock@fmate.test", "abc12345");
        assertThat(locked.getResponse().getStatus()).isEqualTo(423);
        assertThat(read(locked).get("code").asText()).isEqualTo("ACCOUNT_LOCKED");
    }

    @Test
    void 이메일_인증_코드() throws Exception {
        Session s = signup("verify@fmate.test");
        MvcResult wrong = mvc.perform(authed(post("/api/v1/auth/email/verify"), s).contentType(MediaType.APPLICATION_JSON)
                .content(json(Map.of("code", "000000")))).andReturn();
        assertThat(wrong.getResponse().getStatus()).isEqualTo(400);

        String code = codes.issue(s.userId(), OneTimeCodeService.EMAIL_VERIFY);
        MvcResult ok = mvc.perform(authed(post("/api/v1/auth/email/verify"), s).contentType(MediaType.APPLICATION_JSON)
                .content(json(Map.of("code", code)))).andReturn();
        assertThat(ok.getResponse().getStatus()).isEqualTo(204);
        assertThat(read(me(s)).get("emailVerified").asBoolean()).isTrue();

        // 사용한 코드는 다시 쓸 수 없다
        MvcResult reuse = mvc.perform(authed(post("/api/v1/auth/email/verify"), s).contentType(MediaType.APPLICATION_JSON)
                .content(json(Map.of("code", code)))).andReturn();
        assertThat(reuse.getResponse().getStatus()).isEqualTo(400);
    }

    @Test
    void 리프레시_회전과_재사용_탐지() throws Exception {
        Session s = signup("refresh@fmate.test");
        MvcResult first = refresh(s.refresh());
        assertThat(first.getResponse().getStatus()).isEqualTo(200);
        String rotated = read(first).get("refreshToken").asText();
        assertThat(rotated).isNotEqualTo(s.refresh());

        // 이미 회전된 토큰 재사용 → 탈취로 간주, 같은 계열의 새 토큰까지 폐기
        MvcResult reused = refresh(s.refresh());
        assertThat(reused.getResponse().getStatus()).isEqualTo(401);
        assertThat(read(reused).get("code").asText()).isEqualTo("TOKEN_REUSED");
        assertThat(refresh(rotated).getResponse().getStatus()).isEqualTo(401);
    }

    @Test
    void 비밀번호_변경하면_기존_토큰_즉시_무효() throws Exception {
        Session s = signup("pwchange@fmate.test");
        MvcResult changed = mvc.perform(authed(put("/api/v1/auth/password"), s).contentType(MediaType.APPLICATION_JSON)
                .content(json(Map.of("currentPassword", "abc12345", "newPassword", "xyz98765")))).andReturn();
        assertThat(changed.getResponse().getStatus()).isEqualTo(204);
        assertThat(me(s).getResponse().getStatus()).as("이전 액세스 토큰").isEqualTo(401);
        assertThat(refresh(s.refresh()).getResponse().getStatus()).as("이전 리프레시 토큰").isEqualTo(401);
        assertThat(login("pwchange@fmate.test", "xyz98765").getResponse().getStatus()).isEqualTo(200);
    }

    @Test
    void 비밀번호_재설정_요청은_계정_존재여부를_숨김() throws Exception {
        MvcResult unknown = mvc.perform(post("/api/v1/auth/password/reset-request").contentType(MediaType.APPLICATION_JSON)
                .content(json(Map.of("email", "nobody@fmate.test")))).andReturn();
        signup("exists@fmate.test");
        MvcResult known = mvc.perform(post("/api/v1/auth/password/reset-request").contentType(MediaType.APPLICATION_JSON)
                .content(json(Map.of("email", "exists@fmate.test")))).andReturn();
        assertThat(unknown.getResponse().getStatus()).isEqualTo(202);
        assertThat(known.getResponse().getStatus()).isEqualTo(202);
    }

    @Test
    void 회원_탈퇴() throws Exception {
        Session s = signup("leave@fmate.test");
        MvcResult wrongPw = mvc.perform(authed(post("/api/v1/me/delete"), s).contentType(MediaType.APPLICATION_JSON)
                .content(json(Map.of("password", "nope12345", "confirm", "탈퇴")))).andReturn();
        assertThat(wrongPw.getResponse().getStatus()).isEqualTo(400);

        MvcResult ok = mvc.perform(authed(post("/api/v1/me/delete"), s).contentType(MediaType.APPLICATION_JSON)
                .content(json(Map.of("password", "abc12345", "confirm", "탈퇴")))).andReturn();
        assertThat(ok.getResponse().getStatus()).isEqualTo(204);
        assertThat(me(s).getResponse().getStatus()).isEqualTo(401);
        assertThat(login("leave@fmate.test", "abc12345").getResponse().getStatus()).isEqualTo(401);
        // 같은 이메일로 새로 가입 가능
        signup("leave@fmate.test");
    }

    @Test
    void 비로그인_보호_API는_401_JSON() throws Exception {
        MvcResult r = mvc.perform(get("/api/v1/me")).andReturn();
        assertThat(r.getResponse().getStatus()).isEqualTo(401);
        assertThat(read(r).get("code").asText()).isEqualTo("UNAUTHENTICATED");
    }

    @Test
    void 기능_설정_조회는_비밀값을_노출하지_않음() throws Exception {
        MvcResult r = mvc.perform(get("/api/v1/config")).andReturn();
        assertThat(r.getResponse().getStatus()).isEqualTo(200);
        assertThat(body(r)).doesNotContain("test_sk_");
        assertThat(read(r).at("/features/payment/mode").asText()).isEqualTo("TEST");
    }
}
