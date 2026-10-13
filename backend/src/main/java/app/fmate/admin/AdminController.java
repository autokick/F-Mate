package app.fmate.admin;

import app.fmate.auth.AuthUser;
import app.fmate.payment.PaymentService;
import app.fmate.reservation.ReservationService;
import jakarta.servlet.http.HttpServletRequest;
import org.springframework.http.ResponseEntity;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;
import java.util.Map;

/** /api/v1/admin/** 는 SecurityConfig 에서 MODERATOR 이상만 접근. 결제·구장·권한 변경은 ADMIN 전용. */
@RestController
@RequestMapping("/api/v1/admin")
public class AdminController {

    private final AdminService admin;

    public AdminController(AdminService admin) {
        this.admin = admin;
    }

    @GetMapping("/dashboard")
    public Map<String, Object> dashboard() {
        return admin.dashboard();
    }

    // 회원
    @GetMapping("/users")
    public List<Map<String, Object>> users(@RequestParam(required = false) String q,
                                           @RequestParam(required = false) String status,
                                           @RequestParam(defaultValue = "0") int page) {
        return admin.users(q, status, page);
    }

    @GetMapping("/users/{id}")
    public Map<String, Object> user(@PathVariable long id) {
        return admin.user(id);
    }

    @PostMapping("/users/{id}/sanctions")
    public ResponseEntity<Void> sanction(@AuthenticationPrincipal AuthUser me, @PathVariable long id,
                                         @RequestBody AdminService.SanctionInput in, HttpServletRequest req) {
        admin.sanction(me, id, in, req.getRemoteAddr());
        return ResponseEntity.noContent().build();
    }

    public record ReasonRequest(String reason) {
    }

    @PostMapping("/users/{id}/sanctions/lift")
    public ResponseEntity<Void> lift(@AuthenticationPrincipal AuthUser me, @PathVariable long id,
                                     @RequestBody(required = false) ReasonRequest r, HttpServletRequest req) {
        admin.liftSanction(me, id, r == null ? null : r.reason(), req.getRemoteAddr());
        return ResponseEntity.noContent().build();
    }

    public record RoleRequest(String role) {
    }

    @PreAuthorize("hasRole('ADMIN')")
    @PostMapping("/users/{id}/role")
    public ResponseEntity<Void> role(@AuthenticationPrincipal AuthUser me, @PathVariable long id, @RequestBody RoleRequest r,
                                     HttpServletRequest req) {
        admin.setRole(me, id, r.role(), req.getRemoteAddr());
        return ResponseEntity.noContent().build();
    }

    // 구장
    @GetMapping("/venues")
    public List<Map<String, Object>> venues(@RequestParam(required = false) String status,
                                            @RequestParam(defaultValue = "0") int page) {
        return admin.venues(status, page);
    }

    @GetMapping("/venues/{id}")
    public Map<String, Object> venue(@PathVariable long id) {
        return admin.venue(id);
    }

    public record DecisionRequest(String decision, String reason) {
    }

    @PreAuthorize("hasRole('ADMIN')")
    @PostMapping("/venues/{id}/decision")
    public ResponseEntity<Void> decide(@AuthenticationPrincipal AuthUser me, @PathVariable long id,
                                       @RequestBody DecisionRequest r, HttpServletRequest req) {
        admin.decideVenue(me, id, r.decision(), r.reason(), req.getRemoteAddr());
        return ResponseEntity.noContent().build();
    }

    // 예약·결제
    @GetMapping("/reservations")
    public List<Map<String, Object>> reservations(@RequestParam(required = false) String q,
                                                  @RequestParam(required = false) String status,
                                                  @RequestParam(defaultValue = "0") int page) {
        return admin.reservations(q, status, page);
    }

    @PreAuthorize("hasRole('ADMIN')")
    @PostMapping("/reservations/{publicId}/cancel")
    public ReservationService.ReservationView cancel(@AuthenticationPrincipal AuthUser me, @PathVariable String publicId,
                                                     @RequestBody ReasonRequest r, HttpServletRequest req) {
        return admin.cancelReservation(me, publicId, r.reason(), req.getRemoteAddr());
    }

    @PreAuthorize("hasRole('ADMIN')")
    @GetMapping("/payments")
    public List<Map<String, Object>> payments(@RequestParam(required = false) String status,
                                              @RequestParam(defaultValue = "0") int page) {
        return admin.payments(status, page);
    }

    @PreAuthorize("hasRole('ADMIN')")
    @GetMapping("/payments/{orderId}")
    public Map<String, Object> payment(@PathVariable String orderId) {
        return admin.payment(orderId);
    }

    @PreAuthorize("hasRole('ADMIN')")
    @PostMapping("/payments/{orderId}/reconcile")
    public PaymentService.ConfirmResult reconcile(@AuthenticationPrincipal AuthUser me, @PathVariable String orderId,
                                                  HttpServletRequest req) {
        return admin.reconcile(me, orderId, req.getRemoteAddr());
    }

    @PreAuthorize("hasRole('ADMIN')")
    @PostMapping("/refunds/{id}/retry")
    public ResponseEntity<Void> retryRefund(@AuthenticationPrincipal AuthUser me, @PathVariable long id,
                                            HttpServletRequest req) {
        admin.retryRefund(me, id, req.getRemoteAddr());
        return ResponseEntity.noContent().build();
    }

    // 신고
    @GetMapping("/reports")
    public List<Map<String, Object>> reports(@RequestParam(required = false) String status,
                                             @RequestParam(defaultValue = "0") int page) {
        return admin.reports(status, page);
    }

    @PostMapping("/reports/{targetType}/{targetId}/resolve")
    public ResponseEntity<Void> resolve(@AuthenticationPrincipal AuthUser me, @PathVariable String targetType,
                                        @PathVariable long targetId, @RequestBody AdminService.Resolution r,
                                        HttpServletRequest req) {
        admin.resolveReports(me, targetType, targetId, r, req.getRemoteAddr());
        return ResponseEntity.noContent().build();
    }

    // 로그
    @PreAuthorize("hasRole('ADMIN')")
    @GetMapping("/audit-logs")
    public List<Map<String, Object>> auditLogs(@RequestParam(defaultValue = "0") int page) {
        return admin.auditLogs(page);
    }

    @PreAuthorize("hasRole('ADMIN')")
    @GetMapping("/error-logs")
    public List<Map<String, Object>> errorLogs(@RequestParam(defaultValue = "0") int page) {
        return admin.errorLogs(page);
    }
}
