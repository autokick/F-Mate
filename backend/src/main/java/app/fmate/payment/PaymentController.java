package app.fmate.payment;

import app.fmate.auth.AuthUser;
import app.fmate.common.IdempotencyService;
import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Positive;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/v1")
public class PaymentController {

    private final PaymentService payments;
    private final IdempotencyService idempotency;

    public PaymentController(PaymentService payments, IdempotencyService idempotency) {
        this.payments = payments;
        this.idempotency = idempotency;
    }

    public record OrderRequest(@NotBlank String reservationId) {
    }

    @PostMapping("/payments/orders")
    public ResponseEntity<?> order(@AuthenticationPrincipal AuthUser me, @RequestHeader("Idempotency-Key") String key,
                                   @Valid @RequestBody OrderRequest r) {
        return idempotency.execute(me.id(), "payment-order", key, r,
                () -> ResponseEntity.status(HttpStatus.CREATED).body(payments.createOrder(me.id(), r.reservationId())));
    }

    public record ConfirmRequest(@NotBlank String paymentKey, @NotBlank String orderId, @Positive int amount) {
    }

    /** 앱이 직접 승인을 요청하는 경로 (결제창 성공 리다이렉트에서 서버가 이미 처리했다면 결과만 돌려준다) */
    @PostMapping("/payments/confirm")
    public ResponseEntity<?> confirm(@AuthenticationPrincipal AuthUser me, @RequestHeader("Idempotency-Key") String key,
                                     @Valid @RequestBody ConfirmRequest r) {
        return idempotency.execute(me.id(), "payment-confirm", key, r,
                () -> ResponseEntity.ok(payments.confirm(r.orderId(), r.paymentKey(), r.amount(), me.id())));
    }

    @GetMapping("/payments/{orderId}")
    public PaymentService.PaymentStatus status(@AuthenticationPrincipal AuthUser me, @PathVariable String orderId) {
        return payments.status(me.id(), orderId);
    }

    /** 결과 미확정(PENDING) 상태에서 앱이 확인을 재촉할 때 */
    @PostMapping("/payments/{orderId}/reconcile")
    public PaymentService.ConfirmResult reconcile(@AuthenticationPrincipal AuthUser me, @PathVariable String orderId) {
        payments.status(me.id(), orderId);   // 소유자 확인
        return payments.reconcile(orderId);
    }

    /** 토스 웹훅. 처리 결과와 무관하게 200 을 빠르게 돌려준다 (재전송은 중복 제거됨). */
    @PostMapping("/webhooks/toss")
    public ResponseEntity<Void> webhook(@RequestBody String raw) {
        if (raw != null && raw.length() < 200_000) payments.handleWebhook(raw);
        return ResponseEntity.ok().build();
    }
}
