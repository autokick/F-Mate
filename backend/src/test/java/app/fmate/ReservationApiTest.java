package app.fmate;

import com.fasterxml.jackson.databind.JsonNode;
import org.junit.jupiter.api.Test;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.MvcResult;

import java.time.Instant;
import java.time.OffsetDateTime;
import java.time.ZoneOffset;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import java.util.concurrent.Callable;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;

class ReservationApiTest extends IntegrationTest {

    private Map<String, Object> slot(long court, long startEpoch, int fromHour, int hours) {
        OffsetDateTime s = OffsetDateTime.ofInstant(Instant.ofEpochSecond(startEpoch), ZoneOffset.ofHours(9)).plusHours(fromHour);
        return Map.of("courtId", court, "startsAt", s.toString(), "endsAt", s.plusHours(hours).toString());
    }

    private MvcResult reserve(Session s, Map<String, Object> body, String key) throws Exception {
        return mvc.perform(authed(post("/api/v1/reservations"), s).header("Idempotency-Key", key)
                .contentType(MediaType.APPLICATION_JSON).content(json(body))).andReturn();
    }

    @Test
    void 같은_시간_동시_예약은_한_명만_성공() throws Exception {
        long[] c = bookableCourt(2);
        int n = 12;
        List<Session> users = new ArrayList<>();
        for (int i = 0; i < n; i++) users.add(verifiedUser("race" + i + "@fmate.test"));

        ExecutorService pool = Executors.newFixedThreadPool(n);
        CountDownLatch start = new CountDownLatch(1);
        List<Future<Integer>> results = new ArrayList<>();
        for (Session u : users) {
            Callable<Integer> call = () -> {
                start.await();
                return reserve(u, slot(c[0], c[1], 0, 1), UUID.randomUUID().toString()).getResponse().getStatus();
            };
            results.add(pool.submit(call));
        }
        start.countDown();
        int created = 0;
        int conflict = 0;
        for (Future<Integer> f : results) {
            int status = f.get();
            if (status == 201) created++;
            if (status == 409) conflict++;
        }
        pool.shutdown();
        assertThat(created).isEqualTo(1);
        assertThat(conflict).isEqualTo(n - 1);
        Integer active = jdbc.queryForObject(
                "SELECT count(*)::int FROM reservations WHERE court_id = ? AND status IN ('PENDING_PAYMENT','CONFIRMED')",
                Integer.class, c[0]);
        assertThat(active).isEqualTo(1);
    }

    @Test
    void 멱등키_재전송은_같은_결과_다른_본문은_422() throws Exception {
        long[] c = bookableCourt(3);
        Session u = verifiedUser("idem@fmate.test");
        String key = UUID.randomUUID().toString();
        MvcResult first = reserve(u, slot(c[0], c[1], 0, 1), key);
        MvcResult again = reserve(u, slot(c[0], c[1], 0, 1), key);
        assertThat(first.getResponse().getStatus()).isEqualTo(201);
        assertThat(again.getResponse().getStatus()).isEqualTo(201);
        assertThat(read(again).get("publicId").asText()).isEqualTo(read(first).get("publicId").asText());

        MvcResult other = reserve(u, slot(c[0], c[1], 1, 1), key);
        assertThat(other.getResponse().getStatus()).isEqualTo(422);
        assertThat(read(other).get("code").asText()).isEqualTo("IDEMPOTENCY_CONFLICT");

        MvcResult noKey = mvc.perform(authed(post("/api/v1/reservations"), u)
                .contentType(MediaType.APPLICATION_JSON).content(json(slot(c[0], c[1], 2, 1)))).andReturn();
        assertThat(read(noKey).get("code").asText()).isEqualTo("IDEMPOTENCY_KEY_REQUIRED");
    }

    @Test
    void 금액은_서버가_계산하고_미인증_계정은_예약_불가() throws Exception {
        long[] c = bookableCourt(2);
        Session u = verifiedUser("amount@fmate.test");
        JsonNode r = read(reserve(u, slot(c[0], c[1], 0, 2), UUID.randomUUID().toString()));
        assertThat(r.get("totalAmount").asInt()).isEqualTo(120000);
        assertThat(r.get("status").asText()).isEqualTo("PENDING_PAYMENT");

        Session unverified = signup("unverified@fmate.test");
        MvcResult denied = reserve(unverified, slot(c[0], c[1], 0, 1), UUID.randomUUID().toString());
        assertThat(denied.getResponse().getStatus()).isEqualTo(403);
        assertThat(read(denied).get("code").asText()).isEqualTo("ACCOUNT_NOT_ALLOWED");
    }

    @Test
    void 다른_사람_예약은_보이지_않음() throws Exception {
        long[] c = bookableCourt(1);
        Session owner = verifiedUser("owner-res@fmate.test");
        Session stranger = verifiedUser("stranger-res@fmate.test");
        String id = read(reserve(owner, slot(c[0], c[1], 0, 1), UUID.randomUUID().toString())).get("publicId").asText();

        assertThat(mvc.perform(authed(get("/api/v1/reservations/" + id), owner)).andReturn().getResponse().getStatus())
                .isEqualTo(200);
        assertThat(mvc.perform(authed(get("/api/v1/reservations/" + id), stranger)).andReturn().getResponse().getStatus())
                .isEqualTo(404);
        MvcResult cancel = mvc.perform(authed(post("/api/v1/reservations/" + id + "/cancel"), stranger)
                .header("Idempotency-Key", UUID.randomUUID().toString())
                .contentType(MediaType.APPLICATION_JSON).content("{}")).andReturn();
        assertThat(cancel.getResponse().getStatus()).isIn(403, 404);
    }

    @Test
    void 결제_전_취소하면_슬롯이_바로_풀림() throws Exception {
        long[] c = bookableCourt(1);
        Session a = verifiedUser("cancel-a@fmate.test");
        Session b = verifiedUser("cancel-b@fmate.test");
        String id = read(reserve(a, slot(c[0], c[1], 0, 1), UUID.randomUUID().toString())).get("publicId").asText();
        assertThat(reserve(b, slot(c[0], c[1], 0, 1), UUID.randomUUID().toString()).getResponse().getStatus()).isEqualTo(409);

        MvcResult cancel = mvc.perform(authed(post("/api/v1/reservations/" + id + "/cancel"), a)
                .header("Idempotency-Key", UUID.randomUUID().toString())
                .contentType(MediaType.APPLICATION_JSON).content("{\"reason\":\"일정 변경\"}")).andReturn();
        assertThat(cancel.getResponse().getStatus()).isEqualTo(200);
        assertThat(read(cancel).get("status").asText()).isEqualTo("CANCELED");
        assertThat(reserve(b, slot(c[0], c[1], 0, 1), UUID.randomUUID().toString()).getResponse().getStatus()).isEqualTo(201);
    }

    @Test
    void 구장_가능시간_조회는_비로그인도_가능() throws Exception {
        long[] c = bookableCourt(2);
        Long venue = jdbc.queryForObject("SELECT venue_id FROM courts WHERE id = ?", Long.class, c[0]);
        String date = OffsetDateTime.ofInstant(Instant.ofEpochSecond(c[1]), ZoneOffset.ofHours(9)).toLocalDate().toString();
        MvcResult r = mvc.perform(get("/api/v1/venues/" + venue + "/availability").param("date", date)).andReturn();
        assertThat(r.getResponse().getStatus()).isEqualTo(200);
        assertThat(read(r).get(0).get("slots").size()).isGreaterThanOrEqualTo(1);
    }
}
