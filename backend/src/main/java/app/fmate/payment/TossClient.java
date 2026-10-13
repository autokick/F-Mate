package app.fmate.payment;

import app.fmate.common.ApiException;
import app.fmate.config.FmateProperties;
import com.fasterxml.jackson.databind.JsonNode;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.http.client.SimpleClientHttpRequestFactory;
import org.springframework.stereotype.Component;
import org.springframework.web.client.ResourceAccessException;
import org.springframework.web.client.RestClient;

import java.nio.charset.StandardCharsets;
import java.util.Base64;
import java.util.LinkedHashMap;
import java.util.Map;

/**
 * 토스페이먼츠 코어 API 호출 (승인·조회·취소).
 * 시크릿 키는 서버에만 둔다. 응답은 상태코드 + 본문(JSON)으로 돌려주고 해석은 PaymentService 가 한다.
 * 네트워크 오류·타임아웃은 Unreachable 로 구분해 "결과 미확정"으로 다룬다.
 */
@Component
public class TossClient {

    public record Response(int status, JsonNode body) {
        public boolean ok() {
            return status >= 200 && status < 300;
        }

        public String errorCode() {
            return body == null ? null : body.path("code").asText(null);
        }

        public String errorMessage() {
            return body == null ? null : body.path("message").asText(null);
        }
    }

    /** 응답을 받지 못함 (타임아웃 등) — 실제 결과는 조회 API 로 확인해야 한다 */
    public static class Unreachable extends RuntimeException {
        public Unreachable(Throwable cause) {
            super(cause);
        }
    }

    private final FmateProperties.Payment cfg;
    private final RestClient http;

    public TossClient(FmateProperties props, RestClient.Builder builder) {
        this.cfg = props.payment();
        SimpleClientHttpRequestFactory rf = new SimpleClientHttpRequestFactory();
        rf.setConnectTimeout(5_000);
        rf.setReadTimeout(30_000);
        this.http = builder.requestFactory(rf).baseUrl(cfg.tossBaseUrl()).build();
    }

    public boolean isConfigured() {
        return cfg.isConfigured();
    }

    public Response confirm(String paymentKey, String orderId, int amount, String idempotencyKey) {
        Map<String, Object> body = new LinkedHashMap<>();
        body.put("paymentKey", paymentKey);
        body.put("orderId", orderId);
        body.put("amount", amount);
        return post("/v1/payments/confirm", body, idempotencyKey);
    }

    public Response getByOrderId(String orderId) {
        ensure();
        try {
            return http.get().uri("/v1/payments/orders/{orderId}", orderId)
                    .header(HttpHeaders.AUTHORIZATION, auth())
                    .exchange((req, res) -> new Response(res.getStatusCode().value(), res.bodyTo(JsonNode.class)));
        } catch (ResourceAccessException e) {
            throw new Unreachable(e);
        }
    }

    public Response cancel(String paymentKey, String reason, int amount, String idempotencyKey) {
        Map<String, Object> body = new LinkedHashMap<>();
        body.put("cancelReason", reason.length() > 200 ? reason.substring(0, 200) : reason);
        body.put("cancelAmount", amount);
        return post("/v1/payments/" + paymentKey + "/cancel", body, idempotencyKey);
    }

    private Response post(String path, Object body, String idempotencyKey) {
        ensure();
        try {
            return http.post().uri(path)
                    .header(HttpHeaders.AUTHORIZATION, auth())
                    .header("Idempotency-Key", idempotencyKey)
                    .contentType(MediaType.APPLICATION_JSON)
                    .body(body)
                    .exchange((req, res) -> new Response(res.getStatusCode().value(), res.bodyTo(JsonNode.class)));
        } catch (ResourceAccessException e) {
            throw new Unreachable(e);
        }
    }

    private void ensure() {
        if (!isConfigured()) throw ApiException.unavailable("PAYMENT_NOT_CONFIGURED");
    }

    private String auth() {
        String raw = cfg.tossSecretKey() + ":";
        return "Basic " + Base64.getEncoder().encodeToString(raw.getBytes(StandardCharsets.UTF_8));
    }
}
