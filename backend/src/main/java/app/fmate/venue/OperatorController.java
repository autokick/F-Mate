package app.fmate.venue;

import app.fmate.auth.AuthUser;
import app.fmate.common.IdempotencyService;
import app.fmate.reservation.ReservationService;
import org.springframework.format.annotation.DateTimeFormat;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PatchMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.time.LocalDate;
import java.util.List;
import java.util.Map;

@RestController
@RequestMapping("/api/v1/operator")
public class OperatorController {

    private final OperatorService ops;
    private final ReservationService reservations;
    private final IdempotencyService idempotency;

    public OperatorController(OperatorService ops, ReservationService reservations, IdempotencyService idempotency) {
        this.ops = ops;
        this.reservations = reservations;
        this.idempotency = idempotency;
    }

    @PostMapping("/venue-applications")
    public ResponseEntity<Map<String, Long>> apply(@AuthenticationPrincipal AuthUser me,
                                                   @RequestBody OperatorService.VenueInput in) {
        long id = ops.apply(me.id(), me.emailVerified(), in);
        return ResponseEntity.status(HttpStatus.CREATED).body(Map.of("venueId", id));
    }

    @GetMapping("/venues")
    public List<OperatorService.MyVenue> myVenues(@AuthenticationPrincipal AuthUser me) {
        return ops.myVenues(me.id());
    }

    @GetMapping("/venues/{venueId}")
    public VenueService.VenueDetail venue(@AuthenticationPrincipal AuthUser me, @PathVariable long venueId) {
        return ops.venue(me.id(), venueId);
    }

    @PatchMapping("/venues/{venueId}")
    public VenueService.VenueDetail update(@AuthenticationPrincipal AuthUser me, @PathVariable long venueId,
                                           @RequestBody OperatorService.VenueInput in) {
        ops.updateVenue(me.id(), venueId, in);
        return ops.venue(me.id(), venueId);
    }

    @PostMapping("/venues/{venueId}/courts")
    public ResponseEntity<Map<String, Long>> addCourt(@AuthenticationPrincipal AuthUser me, @PathVariable long venueId,
                                                      @RequestBody OperatorService.CourtInput in) {
        long id = ops.addCourt(me.id(), venueId, in);
        return ResponseEntity.status(HttpStatus.CREATED).body(Map.of("courtId", id));
    }

    @PatchMapping("/courts/{courtId}")
    public ResponseEntity<Void> updateCourt(@AuthenticationPrincipal AuthUser me, @PathVariable long courtId,
                                            @RequestBody OperatorService.CourtUpdate in) {
        ops.updateCourt(me.id(), courtId, in);
        return ResponseEntity.noContent().build();
    }

    @GetMapping("/courts/{courtId}/operating-hours")
    public List<OperatorService.HoursRow> hours(@AuthenticationPrincipal AuthUser me, @PathVariable long courtId) {
        return ops.hours(me.id(), courtId);
    }

    @PutMapping("/courts/{courtId}/operating-hours")
    public Map<String, Integer> replaceHours(@AuthenticationPrincipal AuthUser me, @PathVariable long courtId,
                                             @RequestBody List<OperatorService.HoursInput> in) {
        return Map.of("generatedSlots", ops.replaceHours(me.id(), courtId, in));
    }

    @GetMapping("/courts/{courtId}/slots")
    public List<OperatorService.OperatorSlot> slots(@AuthenticationPrincipal AuthUser me, @PathVariable long courtId,
                                                    @RequestParam @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate date) {
        return ops.slots(me.id(), courtId, date);
    }

    @PatchMapping("/slots/{slotId}")
    public ResponseEntity<Void> updateSlot(@AuthenticationPrincipal AuthUser me, @PathVariable long slotId,
                                           @RequestBody OperatorService.SlotUpdate in) {
        ops.updateSlot(me.id(), slotId, in);
        return ResponseEntity.noContent().build();
    }

    @GetMapping("/venues/{venueId}/closures")
    public List<OperatorService.Closure> closures(@AuthenticationPrincipal AuthUser me, @PathVariable long venueId) {
        return ops.closures(me.id(), venueId);
    }

    @PostMapping("/venues/{venueId}/closures")
    public ResponseEntity<Map<String, Long>> addClosure(@AuthenticationPrincipal AuthUser me, @PathVariable long venueId,
                                                        @RequestBody OperatorService.ClosureInput in) {
        return ResponseEntity.status(HttpStatus.CREATED).body(Map.of("closureId", ops.addClosure(me.id(), venueId, in)));
    }

    @DeleteMapping("/venues/{venueId}/closures/{closureId}")
    public ResponseEntity<Void> deleteClosure(@AuthenticationPrincipal AuthUser me, @PathVariable long venueId,
                                              @PathVariable long closureId) {
        ops.deleteClosure(me.id(), venueId, closureId);
        return ResponseEntity.noContent().build();
    }

    @GetMapping("/venues/{venueId}/reservations")
    public List<OperatorService.OperatorReservation> reservations(
            @AuthenticationPrincipal AuthUser me, @PathVariable long venueId,
            @RequestParam @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate date) {
        return ops.reservations(me.id(), venueId, date);
    }

    public record CancelRequest(String reason) {
    }

    @PostMapping("/reservations/{publicId}/cancel")
    public ResponseEntity<?> cancel(@AuthenticationPrincipal AuthUser me, @PathVariable String publicId,
                                    @RequestHeader("Idempotency-Key") String key, @RequestBody CancelRequest r) {
        return idempotency.execute(me.id(), "operator-cancel:" + publicId, key, r,
                () -> ResponseEntity.ok(reservations.cancelByOperator(me.id(), publicId, r.reason())));
    }

    @GetMapping("/venues/{venueId}/staff")
    public List<OperatorService.Staff> staff(@AuthenticationPrincipal AuthUser me, @PathVariable long venueId) {
        return ops.staff(me.id(), venueId);
    }

    public record StaffRequest(String email) {
    }

    @PostMapping("/venues/{venueId}/staff")
    public ResponseEntity<Void> addStaff(@AuthenticationPrincipal AuthUser me, @PathVariable long venueId,
                                         @RequestBody StaffRequest r) {
        ops.addStaff(me.id(), venueId, r.email());
        return ResponseEntity.noContent().build();
    }

    @DeleteMapping("/venues/{venueId}/staff/{userId}")
    public ResponseEntity<Void> removeStaff(@AuthenticationPrincipal AuthUser me, @PathVariable long venueId,
                                            @PathVariable long userId) {
        ops.removeStaff(me.id(), venueId, userId);
        return ResponseEntity.noContent().build();
    }
}
