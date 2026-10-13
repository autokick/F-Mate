package app.fmate.payment;

import app.fmate.notification.NotificationService;
import com.fasterxml.jackson.databind.JsonNode;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;
import org.springframework.transaction.support.TransactionTemplate;

import java.util.List;
import java.util.Map;

/**
 * 환불(토스 결제 취소) 처리기.
 *  - 같은 환불은 항상 같은 Idempotency-Key 로 요청 → 재시도해도 이중 환불 없음
 *  - 실패 시 REQUESTED 로 남기고 지수 백오프로 재시도 (최대 10회), 3회째 실패부터 관리자 알림
 */
@Component
public class RefundProcessor {

    private static final Logger log = LoggerFactory.getLogger(RefundProcessor.class);
    private static final int MAX_ATTEMPTS = 10;

    private final JdbcTemplate jdbc;
    private final TossClient toss;
    private final TransactionTemplate tx;
    private final NotificationService notifications;
    private final PaymentAudit audit;

    public RefundProcessor(JdbcTemplate jdbc, TossClient toss, TransactionTemplate tx,
                           NotificationService notifications, PaymentAudit audit) {
        this.jdbc = jdbc;
        this.toss = toss;
        this.tx = tx;
        this.notifications = notifications;
        this.audit = audit;
    }

    /** 취소 직후 바로 한 번 시도 (실패하면 배치가 이어서 재시도) */
    public void processSoon(long refundId) {
        Thread.ofVirtual().name("refund-" + refundId).start(() -> {
            try {
                process(refundId);
            } catch (Exception e) {
                log.warn("refund {} immediate attempt failed: {}", refundId, e.getClass().getSimpleName());
            }
        });
    }

    @Scheduled(fixedDelay = 60_000, initialDelay = 30_000)
    public void processDue() {
        List<Long> due = jdbc.queryForList("""
                SELECT id FROM refunds
                 WHERE status = 'REQUESTED' AND attempt_count < ?
                   AND created_at + (interval '1 minute' * power(2, attempt_count)) <= now()
                 ORDER BY id LIMIT 50""", Long.class, MAX_ATTEMPTS);
        for (Long id : due) {
            try {
                process(id);
            } catch (Exception e) {
                log.warn("refund {} retry failed: {}", id, e.getClass().getSimpleName());
            }
        }
    }

    private record Work(long refundId, long paymentId, long reservationId, long userId, int amount, String reason,
                        String idemKey, String paymentKey, int attempts) {
    }

    public void process(long refundId) {
        tx.executeWithoutResult(status -> {
            List<Work> rows = jdbc.query("""
                    SELECT f.id, f.payment_id, f.reservation_id, p.user_id, f.amount, f.reason, f.idempotency_key::text,
                           p.payment_key, f.attempt_count
                      FROM refunds f JOIN payments p ON p.id = f.payment_id
                     WHERE f.id = ? AND f.status = 'REQUESTED'
                     FOR UPDATE OF f SKIP LOCKED""",
                    (rs, i) -> new Work(rs.getLong(1), rs.getLong(2), rs.getLong(3), rs.getLong(4), rs.getInt(5),
                            rs.getString(6), rs.getString(7), rs.getString(8), rs.getInt(9)),
                    refundId);
            if (rows.isEmpty()) return;   // 이미 처리됐거나 다른 처리기가 잡고 있음
            Work w = rows.get(0);

            audit.log(w.paymentId(), w.refundId(), "CANCEL_REQUEST", "INFO", null, null, Map.of("amount", w.amount()));
            TossClient.Response res;
            try {
                res = toss.cancel(w.paymentKey(), w.reason(), w.amount(), w.idemKey());
            } catch (TossClient.Unreachable e) {
                audit.log(w.paymentId(), w.refundId(), "CANCEL_RESPONSE", "TIMEOUT", null, null, null);
                failed(w, "TIMEOUT", "응답 없음");
                return;
            }
            if (res.ok()) {
                String txKey = lastCancelTransactionKey(res.body());
                audit.log(w.paymentId(), w.refundId(), "CANCEL_RESPONSE", "OK", res.status(), null, null);
                jdbc.queryForObject("SELECT fn_refund_result(?, true, ?, NULL, NULL)", String.class, w.refundId(), txKey);
                notifications.notify(w.userId(), "REFUND_COMPLETED", null, "RESERVATION", w.reservationId(),
                        "환불이 완료되었어요", String.format("%,d원이 결제 수단으로 환불되었어요. 카드사에 따라 반영까지 며칠 걸릴 수 있어요.", w.amount()),
                        null);
            } else {
                audit.log(w.paymentId(), w.refundId(), "CANCEL_RESPONSE", "ERROR", res.status(), res.errorCode(), null);
                failed(w, res.errorCode(), res.errorMessage());
            }
        });
    }

    private void failed(Work w, String code, String message) {
        jdbc.queryForObject("SELECT fn_refund_result(?, false, NULL, ?, ?)", String.class, w.refundId(),
                code == null ? "UNKNOWN" : code, message == null ? "" : message);
        int attempts = w.attempts() + 1;
        if (attempts == 3 || attempts == MAX_ATTEMPTS) {
            notifications.notifyAdmins("환불 처리 실패 반복",
                    "환불 #" + w.refundId() + " 이(가) " + attempts + "회 실패했어요. 결제 관리 화면에서 확인해 주세요. (" + code + ")",
                    Map.of("refundId", w.refundId()));
        }
        if (attempts == MAX_ATTEMPTS) {
            notifications.notify(w.userId(), "REFUND_FAILED", null, "RESERVATION", w.reservationId(),
                    "환불이 지연되고 있어요", "환불 처리에 문제가 있어 운영팀이 확인 중이에요. 처리되면 다시 알려드릴게요.", null);
        }
    }

    static String lastCancelTransactionKey(JsonNode body) {
        if (body == null) return null;
        JsonNode cancels = body.path("cancels");
        if (cancels.isArray() && !cancels.isEmpty()) {
            return cancels.get(cancels.size() - 1).path("transactionKey").asText(null);
        }
        return null;
    }
}
