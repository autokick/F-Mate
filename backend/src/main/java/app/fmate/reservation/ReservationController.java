package app.fmate.reservation;

import app.fmate.auth.AuthUser;
import app.fmate.common.IdempotencyService;
import jakarta.validation.Valid;
import jakarta.validation.constraints.NotNull;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.time.OffsetDateTime;
import java.util.List;

@RestController
@RequestMapping("/api/v1/reservations")
public class ReservationController {

    private final ReservationService reservations;
    private final IdempotencyService idempotency;

    public ReservationController(ReservationService reservations, IdempotencyService idempotency) {
        this.reservations = reservations;
        this.idempotency = idempotency;
    }

    public record CreateRequest(@NotNull Long courtId, @NotNull OffsetDateTime startsAt, @NotNull OffsetDateTime endsAt) {
    }

    @PostMapping
    public ResponseEntity<?> create(@AuthenticationPrincipal AuthUser me, @RequestHeader("Idempotency-Key") String key,
                                    @Valid @RequestBody CreateRequest r) {
        return idempotency.execute(me.id(), "reservation-create", key, r,
                () -> ResponseEntity.status(HttpStatus.CREATED)
                        .body(reservations.create(me.id(), r.courtId(), r.startsAt(), r.endsAt())));
    }

    @GetMapping
    public List<ReservationService.ReservationListItem> list(@AuthenticationPrincipal AuthUser me,
                                                             @RequestParam(required = false) String status,
                                                             @RequestParam(defaultValue = "0") int page,
                                                             @RequestParam(defaultValue = "20") int limit) {
        return reservations.list(me.id(), status, page, limit);
    }

    @GetMapping("/{publicId}")
    public ReservationService.ReservationView detail(@AuthenticationPrincipal AuthUser me, @PathVariable String publicId) {
        return reservations.detail(me.id(), me.isAdmin(), publicId);
    }

    public record CancelRequest(String reason) {
    }

    @PostMapping("/{publicId}/cancel")
    public ResponseEntity<?> cancel(@AuthenticationPrincipal AuthUser me, @PathVariable String publicId,
                                    @RequestHeader("Idempotency-Key") String key, @RequestBody(required = false) CancelRequest r) {
        CancelRequest body = r == null ? new CancelRequest(null) : r;
        return idempotency.execute(me.id(), "reservation-cancel:" + publicId, key, body,
                () -> ResponseEntity.ok(reservations.cancelByUser(me.id(), publicId, body.reason())));
    }
}
