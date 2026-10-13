package app.fmate.payment;

import app.fmate.auth.AuthUser;
import app.fmate.common.ApiException;
import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.springframework.http.CacheControl;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.util.HtmlUtils;

import java.util.Map;

/**
 * 앱 WebView 에 띄우는 결제 페이지.
 *  /pay/checkout/{orderId}  : 토스 결제창 SDK(v2) 호출 (로그인 필요 — 앱이 Authorization 헤더로 로드)
 *  /pay/success             : 토스가 리다이렉트. 서버가 즉시 승인 API 를 호출하고 결과를 보여준다
 *  /pay/fail                : 사용자가 취소했거나 인증 실패
 * 앱은 success/fail URL 로드를 감지하면 GET /api/v1/payments/{orderId} 로 최종 상태를 확인한다.
 */
@RestController
public class PayPageController {

    private final PaymentService payments;
    private final ObjectMapper mapper;

    public PayPageController(PaymentService payments, ObjectMapper mapper) {
        this.payments = payments;
        this.mapper = mapper;
    }

    @GetMapping(value = "/pay/checkout/{orderId}", produces = MediaType.TEXT_HTML_VALUE)
    public ResponseEntity<String> checkout(@AuthenticationPrincipal AuthUser me, @PathVariable String orderId) {
        PaymentService.Checkout c;
        try {
            c = payments.checkout(me.id(), orderId);
        } catch (ApiException e) {
            return html(page("결제할 수 없어요", e.getMessage(), "error", orderId));
        }
        String config = json(Map.of(
                "clientKey", c.clientKey(),
                "customerKey", c.customerKey(),
                "orderId", c.orderId(),
                "orderName", c.orderName(),
                "amount", c.amount(),
                "successUrl", c.successUrl(),
                "failUrl", c.failUrl()));
        String body = """
                <div class="card">
                  %s
                  <p class="label">결제 내용</p>
                  <p class="title">%s</p>
                  <p class="amount">%s원</p>
                  <button id="pay" onclick="pay()">결제하기</button>
                  <p id="msg" class="muted"></p>
                </div>
                <script src="https://js.tosspayments.com/v2/standard"></script>
                <script>
                  const cfg = %s;
                  async function pay() {
                    const btn = document.getElementById('pay');
                    const msg = document.getElementById('msg');
                    btn.disabled = true; msg.textContent = '';
                    try {
                      const toss = TossPayments(cfg.clientKey);
                      const payment = toss.payment({ customerKey: cfg.customerKey });
                      await payment.requestPayment({
                        method: 'CARD',
                        amount: { currency: 'KRW', value: cfg.amount },
                        orderId: cfg.orderId,
                        orderName: cfg.orderName,
                        successUrl: cfg.successUrl,
                        failUrl: cfg.failUrl
                      });
                    } catch (e) {
                      msg.textContent = (e && e.message) ? e.message : '결제창을 열지 못했어요';
                      btn.disabled = false;
                    }
                  }
                  window.addEventListener('load', pay);
                </script>
                """.formatted(
                c.testMode() ? "<span class=\"badge\">테스트 결제 · 실제 청구되지 않아요</span>" : "",
                HtmlUtils.htmlEscape(c.orderName()),
                String.format("%,d", c.amount()),
                config);
        return html(layout("결제", body));
    }

    @GetMapping(value = "/pay/success", produces = MediaType.TEXT_HTML_VALUE)
    public ResponseEntity<String> success(@RequestParam String paymentKey, @RequestParam String orderId,
                                          @RequestParam int amount) {
        PaymentService.ConfirmResult r;
        try {
            r = payments.confirm(orderId, paymentKey, amount, null);
        } catch (ApiException e) {
            return html(page("결제를 확인할 수 없어요", e.getMessage(), "error", orderId));
        }
        return switch (r.outcome()) {
            case CONFIRMED -> html(page("예약이 확정되었어요", "앱으로 돌아가 예약 내역을 확인하세요.", "confirmed", orderId));
            case PENDING -> html(page("결제 결과를 확인하고 있어요", "잠시 후 앱의 예약 내역에서 확인할 수 있어요. 중복 결제되지 않아요.", "pending", orderId));
            default -> html(page("결제가 완료되지 않았어요", r.message() == null ? "다시 시도해 주세요." : r.message(), "failed", orderId));
        };
    }

    @GetMapping(value = "/pay/fail", produces = MediaType.TEXT_HTML_VALUE)
    public ResponseEntity<String> fail(@RequestParam(required = false) String code,
                                       @RequestParam(required = false) String message,
                                       @RequestParam(required = false) String orderId) {
        payments.markFailedFromRedirect(orderId, code, message);
        String text = "PAY_PROCESS_CANCELED".equals(code) ? "결제를 취소했어요." : (message == null ? "결제에 실패했어요." : message);
        return html(page("결제가 완료되지 않았어요", text, "failed", orderId));
    }

    // ------------------------------------------------------------- HTML

    private String page(String title, String message, String outcome, String orderId) {
        String body = """
                <div class="card" id="result" data-outcome="%s" data-order-id="%s">
                  <p class="title">%s</p>
                  <p class="muted">%s</p>
                </div>
                """.formatted(HtmlUtils.htmlEscape(outcome), HtmlUtils.htmlEscape(orderId == null ? "" : orderId),
                HtmlUtils.htmlEscape(title), HtmlUtils.htmlEscape(message == null ? "" : message));
        return layout(title, body);
    }

    private static String layout(String title, String body) {
        return """
                <!doctype html>
                <html lang="ko"><head><meta charset="utf-8">
                <meta name="viewport" content="width=device-width, initial-scale=1">
                <title>%s</title>
                <style>
                  body { margin:0; font-family:-apple-system, 'Noto Sans KR', sans-serif; background:#fff; color:#111827; }
                  .card { margin:24px 16px; padding:24px; border:1px solid #E5E7EB; border-radius:16px; }
                  .label { color:#6B7280; font-size:14px; margin:0 0 4px; }
                  .title { font-size:20px; font-weight:700; margin:0 0 8px; }
                  .amount { font-size:28px; font-weight:800; color:#15803D; margin:8px 0 24px; }
                  .muted { color:#6B7280; font-size:15px; line-height:1.5; }
                  .badge { display:inline-block; background:#FEF3C7; color:#92400E; font-size:13px; font-weight:700;
                           padding:4px 10px; border-radius:999px; margin-bottom:16px; }
                  button { width:100%%; height:52px; border:0; border-radius:12px; background:#15803D; color:#fff;
                           font-size:17px; font-weight:700; }
                  button:disabled { background:#9CA3AF; }
                </style></head>
                <body>%s</body></html>
                """.formatted(HtmlUtils.htmlEscape(title), body);
    }

    private String json(Object o) {
        try {
            // </script> 삽입 방지
            return mapper.writeValueAsString(o).replace("<", "\\u003c").replace(">", "\\u003e").replace("&", "\\u0026");
        } catch (JsonProcessingException e) {
            throw new IllegalStateException(e);
        }
    }

    private static ResponseEntity<String> html(String s) {
        return ResponseEntity.ok().contentType(new MediaType("text", "html", java.nio.charset.StandardCharsets.UTF_8))
                .cacheControl(CacheControl.noStore())
                // 결제창 SDK 가 여러 토스·카드사 도메인을 쓰므로 스크립트 출처는 제한하지 않고, 이 페이지를 남이 프레임에 넣지 못하게만 한다
                .header("Content-Security-Policy", "frame-ancestors 'none'")
                .body(s);
    }
}
