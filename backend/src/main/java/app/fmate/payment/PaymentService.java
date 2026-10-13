package app.fmate.payment;

import app.fmate.common.ApiException;
import app.fmate.common.Hashing;
import app.fmate.config.FmateProperties;
import app.fmate.notification.NotificationService;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Service;

import java.time.OffsetDateTime;
import java.time.ZoneId;
import java.time.format.DateTimeFormatter;
import java.util.List;
import java.util.Locale;
import java.util.Map;

/**
 * 결제 흐름 (docs/01-architecture.md §4.4)
 *  주문 생성 → 결제창(토스) → /pay/success 리다이렉트에서 서버가 직접 승인 → 결과 반영
 *  응답 유실·타임아웃은 IN_PROGRESS 로 남기고 정산 배치(reconcile)가 토스 조회 API 로 확정한다.
 */
@Service
public class PaymentService {

    private static final Logger log = LoggerFactory.getLogger(PaymentService.class);
    private static final DateTimeFormatter ORDER_DATE = DateTimeFormatter.ofPattern("yyMMdd");
    private static final DateTimeFormatter KOREAN = DateTimeFormatter.ofPattern("M/d HH:mm", Locale.KOREAN)
            .withZone(ZoneId.of("Asia/Seoul"));

    private final JdbcTemplate jdbc;
    private final TossClient toss;
    private final FmateProperties props;
    private final PaymentAudit audit;
    private final RefundProcessor refunds;
    private final NotificationService notifications;
    private final ObjectMapper mapper;

    public PaymentService(JdbcTemplate jdbc, TossClient toss, FmateProperties props, PaymentAudit audit,
                          RefundProcessor refunds, NotificationService notifications, ObjectMapper mapper) {
        this.jdbc = jdbc;
        this.toss = toss;
        this.props = props;
        this.audit = audit;
        this.refunds = refunds;
        this.notifications = notifications;
        this.mapper = mapper;
    }

    // ------------------------------------------------------------- 주문

    public record Order(String orderId, int amount, String orderName, String checkoutUrl, String successUrlPrefix,
                        String failUrlPrefix, String mode, OffsetDateTime holdExpiresAt) {
    }

    public Order createOrder(long userId, String reservationPublicId) {
        if (!toss.isConfigured()) throw ApiException.unavailable("PAYMENT_NOT_CONFIGURED");
        List<Long> ids = jdbc.queryForList("SELECT id FROM reservations WHERE public_id = ?::uuid AND user_id = ?",
                Long.class, uuidOrThrow(reservationPublicId), userId);
        if (ids.isEmpty()) throw ApiException.notFound();
        String orderId = "FM" + ORDER_DATE.format(java.time.LocalDate.now()) + Hashing.randomToken(15).replace('_', 'x');
        String mode = props.payment().isLive() ? "LIVE" : "TEST";
        jdbc.queryForObject("SELECT fn_create_payment_order(?, ?, ?, ?)", Long.class, userId, ids.get(0), mode, orderId);
        return orderView(orderId);
    }

    private Order orderView(String orderId) {
        Map<String, Object> r = jdbc.queryForMap("""
                SELECT p.amount, p.mode, v.name AS venue, c.name AS court, lower(res.period) AS starts_at, res.hold_expires_at
                  FROM payments p JOIN reservations res ON res.id = p.reservation_id
                  JOIN futsal_venues v ON v.id = res.venue_id JOIN courts c ON c.id = res.court_id
                 WHERE p.order_id = ?""", orderId);
        String base = baseUrl();
        return new Order(orderId, ((Number) r.get("amount")).intValue(), orderName(r), base + "/pay/checkout/" + orderId,
                base + "/pay/success", base + "/pay/fail", (String) r.get("mode"),
                toOffset(r.get("hold_expires_at")));
    }

    private static String orderName(Map<String, Object> r) {
        String name = r.get("venue") + " " + r.get("court") + " " + KOREAN.format(toOffset(r.get("starts_at")));
        return name.length() > 100 ? name.substring(0, 100) : name;
    }

    // ------------------------------------------------------------- 결제창 데이터

    public record Checkout(String orderId, int amount, String orderName, String clientKey, String customerKey,
                           String successUrl, String failUrl, boolean testMode) {
    }

    public Checkout checkout(long userId, String orderId) {
        if (!toss.isConfigured()) throw ApiException.unavailable("PAYMENT_NOT_CONFIGURED");
        List<Map<String, Object>> rows = jdbc.queryForList("""
                SELECT p.user_id, p.status, res.status AS res_status, res.hold_expires_at < now() AS expired,
                       u.payment_customer_key::text AS customer_key
                  FROM payments p JOIN reservations res ON res.id = p.reservation_id JOIN users u ON u.id = p.user_id
                 WHERE p.order_id = ?""", orderId);
        if (rows.isEmpty() || ((Number) rows.get(0).get("user_id")).longValue() != userId) throw ApiException.notFound();
        Map<String, Object> r = rows.get(0);
        if (!"READY".equals(r.get("status")) || !"PENDING_PAYMENT".equals(r.get("res_status"))) {
            throw ApiException.conflict("INVALID_STATE");
        }
        if (Boolean.TRUE.equals(r.get("expired"))) throw ApiException.conflict("HOLD_EXPIRED");
        Order o = orderView(orderId);
        return new Checkout(orderId, o.amount(), o.orderName(), props.payment().tossClientKey(),
                (String) r.get("customer_key"), o.successUrlPrefix(), o.failUrlPrefix(), !props.payment().isLive());
    }

    // ------------------------------------------------------------- 승인

    public enum Outcome { CONFIRMED, FAILED, PENDING, AMOUNT_MISMATCH, HOLD_EXPIRED, COMPENSATED }

    public record ConfirmResult(Outcome outcome, String orderId, String reservationPublicId, String code, String message) {
    }

    /**
     * 승인. requestUserId 가 있으면(앱 호출) 주문 소유자인지 확인, 없으면(토스 리다이렉트) 주문의 소유자로 처리.
     * 금액은 DB 함수가 주문 금액과 대조한다 — 클라이언트 금액을 믿지 않는다.
     */
    public ConfirmResult confirm(String orderId, String paymentKey, int amount, Long requestUserId) {
        if (!toss.isConfigured()) throw ApiException.unavailable("PAYMENT_NOT_CONFIGURED");
        List<Map<String, Object>> rows = jdbc.queryForList("""
                SELECT p.id, p.user_id, p.status, res.public_id::text AS rid
                  FROM payments p JOIN reservations res ON res.id = p.reservation_id WHERE p.order_id = ?""", orderId);
        if (rows.isEmpty()) throw ApiException.notFound();
        Map<String, Object> p = rows.get(0);
        long paymentId = ((Number) p.get("id")).longValue();
        long ownerId = ((Number) p.get("user_id")).longValue();
        String rid = (String) p.get("rid");
        if (requestUserId != null && requestUserId != ownerId) throw ApiException.notFound();
        String status = (String) p.get("status");
        if ("DONE".equals(status)) return new ConfirmResult(Outcome.CONFIRMED, orderId, rid, null, null);
        if ("IN_PROGRESS".equals(status)) return new ConfirmResult(Outcome.PENDING, orderId, rid, null, null);

        Long begin = jdbc.queryForObject("SELECT fn_payment_confirm_begin(?, ?, ?, ?)", Long.class,
                ownerId, orderId, paymentKey, amount);
        if (begin == null || begin == -1) {
            return new ConfirmResult(Outcome.AMOUNT_MISMATCH, orderId, rid, "AMOUNT_MISMATCH", "결제 금액이 올바르지 않아 결제를 진행하지 않았어요");
        }
        if (begin == -2) {
            return new ConfirmResult(Outcome.HOLD_EXPIRED, orderId, rid, "HOLD_EXPIRED", "결제 가능 시간이 지나 예약이 만료되었어요. 결제는 청구되지 않아요");
        }
        return callConfirm(paymentId, orderId, paymentKey, amount, rid);
    }

    private ConfirmResult callConfirm(long paymentId, String orderId, String paymentKey, int amount, String rid) {
        TossClient.Response res;
        try {
            res = toss.confirm(paymentKey, orderId, amount, "confirm-" + orderId);
        } catch (TossClient.Unreachable e) {
            audit.log(paymentId, null, "CONFIRM_RESPONSE", "TIMEOUT", null, null, null);
            return new ConfirmResult(Outcome.PENDING, orderId, rid, "PAYMENT_PENDING", "결제 결과를 확인하고 있어요");
        }
        if (res.ok()) {
            audit.log(paymentId, null, "CONFIRM_RESPONSE", "OK", res.status(), null, null);
            return applyProviderState(paymentId, orderId, res.body(), rid);
        }
        audit.log(paymentId, null, "CONFIRM_RESPONSE", "ERROR", res.status(), res.errorCode(), null);
        if (res.status() >= 500) {
            // 토스 쪽 일시 오류: 실제 승인 여부를 알 수 없으므로 정산 배치가 조회로 확정
            return new ConfirmResult(Outcome.PENDING, orderId, rid, "PAYMENT_PENDING", "결제 결과를 확인하고 있어요");
        }
        if ("ALREADY_PROCESSED_PAYMENT".equals(res.errorCode())) {
            return reconcile(orderId);
        }
        jdbc.queryForObject("SELECT 1 FROM fn_payment_confirm_failed(?, ?, ?)", Integer.class,
                orderId, res.errorCode() == null ? "UNKNOWN" : res.errorCode(), res.errorMessage() == null ? "" : res.errorMessage());
        return new ConfirmResult(Outcome.FAILED, orderId, rid, res.errorCode(),
                res.errorMessage() == null ? "결제에 실패했어요" : res.errorMessage());
    }

    /** 토스가 돌려준 결제 객체를 우리 상태에 반영 */
    private ConfirmResult applyProviderState(long paymentId, String orderId, JsonNode payment, String rid) {
        String providerStatus = payment == null ? "" : payment.path("status").asText("");
        if ("DONE".equals(providerStatus)) {
            int approved = payment.path("totalAmount").asInt(-1);
            String method = payment.path("method").asText(null);
            String receipt = payment.path("receipt").path("url").asText(null);
            String secret = payment.path("secret").asText(null);
            OffsetDateTime approvedAt = parseTime(payment.path("approvedAt").asText(null));
            if (approved < 0) {
                audit.log(paymentId, null, "MALFORMED_PROVIDER_RESPONSE", "ERROR", null, null, null);
                return new ConfirmResult(Outcome.PENDING, orderId, rid, "PAYMENT_PENDING", "결제 결과를 확인하고 있어요");
            }
            String result = jdbc.queryForObject("SELECT fn_payment_confirm_succeeded(?, ?, ?, ?, ?, ?)", String.class,
                    orderId, approved, method, receipt, secret, approvedAt);
            if ("NEEDS_COMPENSATION".equals(result)) {
                Long refundId = jdbc.queryForObject("SELECT fn_request_compensation_refund(?)", Long.class, orderId);
                if (refundId != null) refunds.processSoon(refundId);
                log.warn("payment {} approved but reservation not confirmable — compensation refund {}", orderId, refundId);
                return new ConfirmResult(Outcome.COMPENSATED, orderId, rid, "INVALID_STATE",
                        "예약을 확정할 수 없어 결제를 자동으로 취소했어요");
            }
            if ("CONFIRMED".equals(result)) notifyConfirmed(orderId);
            return new ConfirmResult(Outcome.CONFIRMED, orderId, rid, null, null);
        }
        if ("ABORTED".equals(providerStatus) || "EXPIRED".equals(providerStatus)) {
            jdbc.queryForObject("SELECT 1 FROM fn_payment_confirm_failed(?, ?, ?)", Integer.class,
                    orderId, "PROVIDER_" + providerStatus, "결제가 완료되지 않았어요");
            return new ConfirmResult(Outcome.FAILED, orderId, rid, "PAYMENT_FAILED", "결제가 완료되지 않았어요");
        }
        // WAITING_FOR_DEPOSIT 등: 이 서비스는 카드·간편결제만 사용하므로 확정하지 않고 관리자 확인 대상으로 둔다
        audit.log(paymentId, null, "UNEXPECTED_PROVIDER_STATUS", "INFO", null, providerStatus, null);
        return new ConfirmResult(Outcome.PENDING, orderId, rid, "PAYMENT_PENDING", "결제 결과를 확인하고 있어요");
    }

    private void notifyConfirmed(String orderId) {
        Map<String, Object> r = jdbc.queryForMap("""
                SELECT res.id, res.user_id, res.public_id::text AS pid, v.name, c.name AS court, lower(res.period) AS starts_at
                  FROM payments p JOIN reservations res ON res.id = p.reservation_id
                  JOIN futsal_venues v ON v.id = res.venue_id JOIN courts c ON c.id = res.court_id
                 WHERE p.order_id = ?""", orderId);
        notifications.notify(((Number) r.get("user_id")).longValue(), "RESERVATION_CONFIRMED", null, "RESERVATION",
                ((Number) r.get("id")).longValue(), "예약이 확정되었어요",
                r.get("name") + " " + r.get("court") + " · " + KOREAN.format(toOffset(r.get("starts_at"))),
                Map.of("reservationId", r.get("pid")));
    }

    // ------------------------------------------------------------- 정산(조회로 확정)

    public ConfirmResult reconcile(String orderId) {
        List<Map<String, Object>> rows = jdbc.queryForList("""
                SELECT p.id, p.status, p.payment_key, p.amount, p.updated_at < now() - interval '15 minutes' AS stale,
                       res.public_id::text AS rid
                  FROM payments p JOIN reservations res ON res.id = p.reservation_id WHERE p.order_id = ?""", orderId);
        if (rows.isEmpty()) throw ApiException.notFound();
        Map<String, Object> p = rows.get(0);
        long paymentId = ((Number) p.get("id")).longValue();
        String rid = (String) p.get("rid");
        String status = (String) p.get("status");
        if (!"IN_PROGRESS".equals(status)) {
            Outcome o = "DONE".equals(status) ? Outcome.CONFIRMED : "READY".equals(status) ? Outcome.PENDING : Outcome.FAILED;
            return new ConfirmResult(o, orderId, rid, null, null);
        }
        TossClient.Response res;
        try {
            res = toss.getByOrderId(orderId);
        } catch (TossClient.Unreachable e) {
            return new ConfirmResult(Outcome.PENDING, orderId, rid, "PAYMENT_PENDING", null);
        }
        audit.log(paymentId, null, "RECONCILE", res.ok() ? "OK" : "ERROR", res.status(), res.errorCode(), null);
        if (res.ok()) {
            String providerStatus = res.body().path("status").asText("");
            if ("IN_PROGRESS".equals(providerStatus)) {
                // 인증은 됐지만 승인 요청이 토스에 닿지 않은 경우 → 같은 멱등키로 승인 재시도
                return callConfirm(paymentId, orderId, (String) p.get("payment_key"),
                        ((Number) p.get("amount")).intValue(), rid);
            }
            return applyProviderState(paymentId, orderId, res.body(), rid);
        }
        if (res.status() == 404 && Boolean.TRUE.equals(p.get("stale"))) {
            jdbc.queryForObject("SELECT 1 FROM fn_payment_confirm_failed(?, ?, ?)", Integer.class,
                    orderId, "NOT_FOUND_PAYMENT", "결제 내역을 찾을 수 없어요");
            return new ConfirmResult(Outcome.FAILED, orderId, rid, "PAYMENT_FAILED", null);
        }
        return new ConfirmResult(Outcome.PENDING, orderId, rid, "PAYMENT_PENDING", null);
    }

    @Scheduled(fixedDelay = 60_000, initialDelay = 20_000)
    public void reconcileStuck() {
        if (!toss.isConfigured()) return;
        List<String> stuck = jdbc.queryForList("""
                SELECT order_id FROM payments WHERE status = 'IN_PROGRESS' AND updated_at < now() - interval '1 minute'
                 ORDER BY updated_at LIMIT 50""", String.class);
        for (String orderId : stuck) {
            try {
                reconcile(orderId);
            } catch (Exception e) {
                log.warn("reconcile {} failed: {}", orderId, e.getClass().getSimpleName());
            }
        }
    }

    // ------------------------------------------------------------- 실패 리다이렉트

    public void markFailedFromRedirect(String orderId, String code, String message) {
        if (orderId == null || orderId.length() > 64) return;
        jdbc.update("""
                UPDATE payments SET status = 'ABORTED', failure_code = ?, failure_message = ?
                 WHERE order_id = ? AND status = 'READY'""",
                code == null ? "USER_CANCELED" : code.substring(0, Math.min(80, code.length())),
                message == null ? null : message.substring(0, Math.min(300, message.length())), orderId);
    }

    // ------------------------------------------------------------- 조회

    public record PaymentStatus(String orderId, String status, String mode, int amount, Integer approvedAmount,
                                Integer balanceAmount, String method, String receiptUrl, String failureCode,
                                String failureMessage, String reservationPublicId, String reservationStatus) {
    }

    public PaymentStatus status(long userId, String orderId) {
        List<PaymentStatus> rows = jdbc.query("""
                SELECT p.order_id, p.status, p.mode, p.amount, p.approved_amount, p.balance_amount, p.method, p.receipt_url,
                       p.failure_code, p.failure_message, res.public_id::text, res.status
                  FROM payments p JOIN reservations res ON res.id = p.reservation_id
                 WHERE p.order_id = ? AND p.user_id = ?""",
                (rs, i) -> new PaymentStatus(rs.getString(1), rs.getString(2), rs.getString(3), rs.getInt(4),
                        (Integer) rs.getObject(5), (Integer) rs.getObject(6), rs.getString(7), rs.getString(8),
                        rs.getString(9), rs.getString(10), rs.getString(11), rs.getString(12)),
                orderId, userId);
        if (rows.isEmpty()) throw ApiException.notFound();
        return rows.get(0);
    }

    // ------------------------------------------------------------- 웹훅

    /**
     * 토스 웹훅. 원문을 저장(중복 수신 제거)하고, 본문을 그대로 믿지 않고 조회 API 로 재확인한다.
     * secret 이 저장된 값과 일치하면 VERIFIED 로 표시한다.
     */
    public void handleWebhook(String rawBody) {
        byte[] dedupe = Hashing.sha256(rawBody);
        JsonNode root;
        try {
            root = mapper.readTree(rawBody);
        } catch (Exception e) {
            return;
        }
        String eventType = root.path("eventType").asText("UNKNOWN");
        JsonNode data = root.path("data");
        String orderId = data.path("orderId").asText(null);
        String paymentKey = data.path("paymentKey").asText(null);
        int inserted = jdbc.update("""
                INSERT INTO payment_webhook_events (event_type, dedupe_key, order_id, payment_key, payload)
                VALUES (?, ?, ?, ?, ?::jsonb) ON CONFLICT (dedupe_key) DO NOTHING""",
                eventType.substring(0, Math.min(60, eventType.length())), dedupe, orderId, paymentKey, rawBody);
        if (inserted == 0) return;
        processWebhook(dedupe, orderId, data.path("secret").asText(null));
    }

    private void processWebhook(byte[] dedupe, String orderId, String secret) {
        String verification = "PENDING";
        String error = null;
        try {
            List<String> stored = orderId == null ? List.of()
                    : jdbc.queryForList("SELECT COALESCE(webhook_secret, '') FROM payments WHERE order_id = ?", String.class, orderId);
            if (stored.isEmpty()) {
                verification = "REJECTED";
                error = "unknown order";
            } else {
                if (secret != null && Hashing.constantTimeEquals(secret, stored.get(0))) verification = "VERIFIED";
                reconcile(orderId);   // 조회 API 가 최종 근거
            }
        } catch (Exception e) {
            error = e.getClass().getSimpleName();
        }
        jdbc.update("UPDATE payment_webhook_events SET verification = ?, processed_at = now(), process_error = ? WHERE dedupe_key = ?",
                verification, error, dedupe);
    }

    // ------------------------------------------------------------- 유틸

    private String baseUrl() {
        String b = props.publicBaseUrl();
        return b.endsWith("/") ? b.substring(0, b.length() - 1) : b;
    }

    private static String uuidOrThrow(String s) {
        if (s == null || !s.matches("^[0-9a-fA-F-]{36}$")) throw ApiException.notFound();
        return s;
    }

    private static OffsetDateTime parseTime(String s) {
        if (s == null || s.isBlank()) return OffsetDateTime.now();
        try {
            return OffsetDateTime.parse(s);
        } catch (Exception e) {
            return OffsetDateTime.now();
        }
    }

    static OffsetDateTime toOffset(Object o) {
        if (o == null) return null;
        if (o instanceof OffsetDateTime odt) return odt;
        if (o instanceof java.sql.Timestamp ts) return ts.toInstant().atZone(ZoneId.of("Asia/Seoul")).toOffsetDateTime();
        throw new IllegalStateException("unexpected time type " + o.getClass());
    }
}
