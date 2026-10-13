package app.fmate;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.testcontainers.service.connection.ServiceConnection;
import org.springframework.http.MediaType;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.MvcResult;
import org.springframework.test.web.servlet.request.MockHttpServletRequestBuilder;
import org.testcontainers.containers.PostgreSQLContainer;

import java.nio.charset.StandardCharsets;
import java.util.Map;
import java.util.UUID;

import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;

/**
 * 통합 테스트 기반: 실제 PostgreSQL 16 컨테이너 + Flyway 마이그레이션 + 전체 Spring 컨텍스트.
 * 실행 조건: Docker 가 켜져 있어야 한다 (./gradlew test).
 */
@SpringBootTest
@AutoConfigureMockMvc
public abstract class IntegrationTest {

    /** 모든 테스트 클래스가 공유하는 컨테이너 (한 번만 시작). Spring 컨텍스트 캐시와 수명이 맞도록 싱글턴으로 둔다. */
    @ServiceConnection
    static final PostgreSQLContainer<?> POSTGRES = new PostgreSQLContainer<>("postgres:16-alpine");

    static {
        POSTGRES.start();
    }

    @DynamicPropertySource
    static void props(DynamicPropertyRegistry r) {
        r.add("fmate.dev-mode", () -> "true");
        r.add("fmate.rate-limit-enabled", () -> "false");   // 한 IP 에서 많은 계정을 만들기 때문 (RateLimiterTest 에서 따로 검증)
        // 토스 테스트 키 형식의 더미 값: 예약(선점) 생성까지만 쓰고 실제 토스 API 는 호출하지 않는다
        r.add("fmate.payment.toss-client-key", () -> "test_ck_dummy_for_tests");
        r.add("fmate.payment.toss-secret-key", () -> "test_sk_dummy_for_tests");
        r.add("fmate.payment.toss-base-url", () -> "http://127.0.0.1:9");
    }

    @Autowired
    protected MockMvc mvc;
    @Autowired
    protected ObjectMapper om;
    @Autowired
    protected JdbcTemplate jdbc;

    protected record Session(long userId, String access, String refresh) {
    }

    protected Session signup(String email) throws Exception {
        String nick = "u" + UUID.randomUUID().toString().substring(0, 8);
        MvcResult r = mvc.perform(post("/api/v1/auth/signup").contentType(MediaType.APPLICATION_JSON)
                        .content(json(Map.of(
                                "email", email, "password", "abc12345", "nickname", nick,
                                "consents", new Object[]{
                                        Map.of("type", "AGE_14", "agreed", true),
                                        Map.of("type", "TERMS", "agreed", true),
                                        Map.of("type", "PRIVACY", "agreed", true)}))))
                .andReturn();
        if (r.getResponse().getStatus() != 201) {
            throw new AssertionError("signup failed: " + r.getResponse().getStatus() + " " + body(r));
        }
        JsonNode n = om.readTree(body(r));
        return new Session(n.get("userId").asLong(), n.get("accessToken").asText(), n.get("refreshToken").asText());
    }

    /** 이메일 인증을 마친 사용자 (인증 코드 흐름은 AuthFlowTest 에서 따로 검증) */
    protected Session verifiedUser(String email) throws Exception {
        Session s = signup(email);
        jdbc.update("UPDATE users SET email_verified_at = now() WHERE id = ?", s.userId());
        return s;
    }

    /** 검증 완료 구장 + 코트 1면 + 이틀 뒤 1시간 슬롯 n개. 반환: [courtId, 첫 슬롯 시작 epoch 초] */
    protected long[] bookableCourt(int slots) {
        Long venue = jdbc.queryForObject("""
                INSERT INTO futsal_venues (name, road_address, region_code, latitude, longitude, verification_status, verified_at)
                VALUES ('테스트구장', '경기도 화성시 테스트로 1', '41590', 37.2, 127.0, 'VERIFIED', now()) RETURNING id""", Long.class);
        Long court = jdbc.queryForObject("""
                INSERT INTO courts (venue_id, name, is_indoor, surface, size_class)
                VALUES (?, 'A', true, 'ARTIFICIAL_TURF', '5V5') RETURNING id""", Long.class, venue);
        Long start = jdbc.queryForObject(
                "SELECT extract(epoch FROM date_trunc('hour', now()) + interval '48 hours')::bigint", Long.class);
        for (int i = 0; i < slots; i++) {
            jdbc.update("""
                    INSERT INTO time_slots (court_id, period, price)
                    VALUES (?, tstzrange(to_timestamp(?) + make_interval(hours => ?), to_timestamp(?) + make_interval(hours => ?), '[)'), 60000)""",
                    court, start, i, start, i + 1);
        }
        return new long[]{court, start};
    }

    protected String json(Object o) throws Exception {
        return om.writeValueAsString(o);
    }

    protected static String body(MvcResult r) throws Exception {
        return r.getResponse().getContentAsString(StandardCharsets.UTF_8);
    }

    protected JsonNode read(MvcResult r) throws Exception {
        return om.readTree(body(r));
    }

    protected static MockHttpServletRequestBuilder authed(MockHttpServletRequestBuilder b, Session s) {
        return b.header("Authorization", "Bearer " + s.access());
    }

    protected MvcResult me(Session s) throws Exception {
        return mvc.perform(authed(get("/api/v1/me"), s)).andReturn();
    }
}
