package app.fmate;

import com.fasterxml.jackson.databind.JsonNode;
import org.junit.jupiter.api.Test;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.MvcResult;

import java.util.Map;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.delete;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.patch;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put;

class SocialAndAdminTest extends IntegrationTest {

    private long textPost(Session s, String caption, String visibility) throws Exception {
        MvcResult r = mvc.perform(authed(post("/api/v1/posts"), s).header("Idempotency-Key", UUID.randomUUID().toString())
                .contentType(MediaType.APPLICATION_JSON)
                .content(json(Map.of("kind", "TEXT", "caption", caption, "visibility", visibility)))).andReturn();
        assertThat(r.getResponse().getStatus()).as(body(r)).isEqualTo(201);
        return read(r).get("id").asLong();
    }

    @Test
    void 게시물_공개범위와_팔로우() throws Exception {
        Session a = verifiedUser("post-a@fmate.test");
        Session b = verifiedUser("post-b@fmate.test");
        long pub = textPost(a, "오늘 풋살 #화성 #풋살", "PUBLIC");
        long fol = textPost(a, "팔로워만", "FOLLOWERS");

        assertThat(mvc.perform(authed(get("/api/v1/posts/" + pub), b)).andReturn().getResponse().getStatus()).isEqualTo(200);
        assertThat(mvc.perform(authed(get("/api/v1/posts/" + fol), b)).andReturn().getResponse().getStatus()).isEqualTo(404);

        MvcResult f = mvc.perform(authed(put("/api/v1/users/" + a.userId() + "/follow"), b)).andReturn();
        assertThat(read(f).get("followStatus").asText()).isEqualTo("FOLLOWING");
        assertThat(mvc.perform(authed(get("/api/v1/posts/" + fol), b)).andReturn().getResponse().getStatus()).isEqualTo(200);

        JsonNode tag = read(mvc.perform(authed(get("/api/v1/hashtags/화성/posts"), b)).andReturn());
        assertThat(tag.get("items").size()).isEqualTo(1);

        // 좋아요는 멱등, 카운트 1
        mvc.perform(authed(put("/api/v1/posts/" + pub + "/like"), b)).andReturn();
        mvc.perform(authed(put("/api/v1/posts/" + pub + "/like"), b)).andReturn();
        JsonNode post = read(mvc.perform(authed(get("/api/v1/posts/" + pub), b)).andReturn());
        assertThat(post.get("likeCount").asInt()).isEqualTo(1);
        assertThat(post.get("likedByMe").asBoolean()).isTrue();

        // 작성자에게 팔로우·좋아요 알림
        JsonNode notes = read(mvc.perform(authed(get("/api/v1/notifications"), a)).andReturn());
        assertThat(notes.size()).isGreaterThanOrEqualTo(2);
    }

    @Test
    void 비공개_계정은_팔로우_요청_후_승인() throws Exception {
        Session a = verifiedUser("private-a@fmate.test");
        Session b = verifiedUser("private-b@fmate.test");
        mvc.perform(authed(patch("/api/v1/me/profile"), a).contentType(MediaType.APPLICATION_JSON)
                .content(json(Map.of("isPrivate", true)))).andReturn();
        long p = textPost(a, "비공개 계정 글", "PUBLIC");

        MvcResult f = mvc.perform(authed(put("/api/v1/users/" + a.userId() + "/follow"), b)).andReturn();
        assertThat(read(f).get("followStatus").asText()).isEqualTo("PENDING");
        assertThat(mvc.perform(authed(get("/api/v1/posts/" + p), b)).andReturn().getResponse().getStatus()).isEqualTo(404);

        mvc.perform(authed(post("/api/v1/me/follow-requests/" + b.userId() + "/accept"), a)).andReturn();
        assertThat(mvc.perform(authed(get("/api/v1/posts/" + p), b)).andReturn().getResponse().getStatus()).isEqualTo(200);
    }

    @Test
    void 차단하면_팔로우_채팅_열람_모두_불가() throws Exception {
        Session a = verifiedUser("block-a@fmate.test");
        Session b = verifiedUser("block-b@fmate.test");
        long p = textPost(a, "공개 글", "PUBLIC");
        mvc.perform(authed(put("/api/v1/users/" + b.userId() + "/block"), a)).andReturn();

        MvcResult follow = mvc.perform(authed(put("/api/v1/users/" + a.userId() + "/follow"), b)).andReturn();
        assertThat(follow.getResponse().getStatus()).isEqualTo(403);
        assertThat(read(follow).get("code").asText()).isEqualTo("BLOCKED");

        MvcResult chat = mvc.perform(authed(post("/api/v1/chats"), b).contentType(MediaType.APPLICATION_JSON)
                .content(json(Map.of("userId", a.userId())))).andReturn();
        assertThat(chat.getResponse().getStatus()).isEqualTo(403);

        assertThat(mvc.perform(authed(get("/api/v1/posts/" + p), b)).andReturn().getResponse().getStatus()).isEqualTo(404);
        assertThat(mvc.perform(authed(get("/api/v1/users/" + a.userId()), b)).andReturn().getResponse().getStatus()).isEqualTo(404);

        mvc.perform(authed(delete("/api/v1/users/" + b.userId() + "/block"), a)).andReturn();
        assertThat(mvc.perform(authed(get("/api/v1/posts/" + p), b)).andReturn().getResponse().getStatus()).isEqualTo(200);
    }

    @Test
    void 채팅_메시지_중복전송은_한_건만_저장() throws Exception {
        Session a = verifiedUser("chat-a@fmate.test");
        Session b = verifiedUser("chat-b@fmate.test");
        long chatId = read(mvc.perform(authed(post("/api/v1/chats"), a).contentType(MediaType.APPLICATION_JSON)
                .content(json(Map.of("userId", b.userId())))).andReturn()).get("id").asLong();
        String cmid = UUID.randomUUID().toString();
        for (int i = 0; i < 3; i++) {
            MvcResult r = mvc.perform(authed(post("/api/v1/chats/" + chatId + "/messages"), a).contentType(MediaType.APPLICATION_JSON)
                    .content(json(Map.of("clientMessageId", cmid, "body", "내일 7시 풋살 어때요?")))).andReturn();
            assertThat(r.getResponse().getStatus()).isEqualTo(200);
        }
        JsonNode msgs = read(mvc.perform(authed(get("/api/v1/chats/" + chatId + "/messages"), b)).andReturn());
        assertThat(msgs.size()).isEqualTo(1);
        JsonNode list = read(mvc.perform(authed(get("/api/v1/chats"), b)).andReturn());
        assertThat(list.get(0).get("unreadCount").asInt()).isEqualTo(1);

        Session c = verifiedUser("chat-c@fmate.test");
        assertThat(mvc.perform(authed(get("/api/v1/chats/" + chatId + "/messages"), c)).andReturn().getResponse().getStatus())
                .as("참여자가 아니면 404").isEqualTo(404);
    }

    @Test
    void 관리자_API는_일반회원_403_관리자_작업은_감사로그() throws Exception {
        Session user = verifiedUser("plain@fmate.test");
        assertThat(mvc.perform(authed(get("/api/v1/admin/dashboard"), user)).andReturn().getResponse().getStatus())
                .isEqualTo(403);

        Session admin = verifiedUser("admin@fmate.test");
        jdbc.update("UPDATE users SET role = 'ADMIN' WHERE id = ?", admin.userId());
        assertThat(mvc.perform(authed(get("/api/v1/admin/dashboard"), admin)).andReturn().getResponse().getStatus())
                .isEqualTo(200);

        MvcResult sanction = mvc.perform(authed(post("/api/v1/admin/users/" + user.userId() + "/sanctions"), admin)
                .contentType(MediaType.APPLICATION_JSON)
                .content(json(Map.of("kind", "SUSPENSION", "days", 3, "reason", "욕설 반복")))).andReturn();
        assertThat(sanction.getResponse().getStatus()).isEqualTo(204);
        assertThat(me(user).getResponse().getStatus()).as("정지 즉시 토큰 무효").isEqualTo(401);

        Integer audits = jdbc.queryForObject(
                "SELECT count(*)::int FROM admin_audit_logs WHERE action = 'USER_SUSPENSION' AND target_id = ?",
                Integer.class, user.userId());
        assertThat(audits).isEqualTo(1);
    }

    @Test
    void 신고_5건_누적되면_자동_숨김() throws Exception {
        Session author = verifiedUser("reported@fmate.test");
        long p = textPost(author, "문제 글", "PUBLIC");
        for (int i = 0; i < 5; i++) {
            Session r = verifiedUser("reporter" + i + "@fmate.test");
            MvcResult res = mvc.perform(authed(post("/api/v1/reports"), r).contentType(MediaType.APPLICATION_JSON)
                    .content(json(Map.of("targetType", "POST", "targetId", p, "reason", "SPAM")))).andReturn();
            assertThat(res.getResponse().getStatus()).isEqualTo(201);
        }
        String status = jdbc.queryForObject("SELECT status FROM posts WHERE id = ?", String.class, p);
        assertThat(status).isEqualTo("HIDDEN_BY_MODERATION");
    }

    @Test
    void 미디어_미설정이면_업로드는_준비중() throws Exception {
        Session u = verifiedUser("media@fmate.test");
        MvcResult r = mvc.perform(authed(post("/api/v1/media/upload-urls"), u).contentType(MediaType.APPLICATION_JSON)
                .content(json(Map.of("purpose", "POST_IMAGE",
                        "files", new Object[]{Map.of("contentType", "image/jpeg", "sizeBytes", 1000)})))).andReturn();
        assertThat(r.getResponse().getStatus()).isEqualTo(503);
        assertThat(read(r).get("code").asText()).isEqualTo("MEDIA_NOT_CONFIGURED");
    }
}
