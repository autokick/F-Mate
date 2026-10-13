package app.fmate.reservation;

import app.fmate.common.ApiException;
import app.fmate.config.FmateProperties;
import app.fmate.notification.NotificationService;
import app.fmate.payment.RefundProcessor;
import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;

import java.time.OffsetDateTime;
import java.time.ZoneId;
import java.time.format.DateTimeFormatter;
import java.util.List;
import java.util.Map;
import java.util.Set;

@Service
public class ReservationService {

    private static final Set<String> STATUSES = Set.of(
            "PENDING_PAYMENT", "CONFIRMED", "CANCELED", "REFUNDED", "EXPIRED", "COMPLETED", "NO_SHOW");
    static final DateTimeFormatter KOREAN = DateTimeFormatter.ofPattern("M/d(E) HH:mm", java.util.Locale.KOREAN)
            .withZone(ZoneId.of("Asia/Seoul"));

    private final JdbcTemplate jdbc;
    private final FmateProperties props;
    private final ObjectMapper mapper;
    private final NotificationService notifications;
    private final RefundProcessor refunds;

    public ReservationService(JdbcTemplate jdbc, FmateProperties props, ObjectMapper mapper,
                              NotificationService notifications, RefundProcessor refunds) {
        this.jdbc = jdbc;
        this.props = props;
        this.mapper = mapper;
        this.notifications = notifications;
        this.refunds = refunds;
    }

    // ------------------------------------------------------------- 조회 모델

    public record VenueRef(long id, String name, String roadAddress, String phone) {
    }

    public record CourtRef(long id, String name, boolean isIndoor, String sizeClass) {
    }

    public record PaymentInfo(String orderId, String status, String mode, String method, int amount,
                              Integer approvedAmount, Integer balanceAmount, String receiptUrl,
                              String failureCode, String failureMessage, OffsetDateTime approvedAt) {
    }

    public record RefundInfo(long id, int amount, String status, String reason, OffsetDateTime createdAt,
                             OffsetDateTime completedAt) {
    }

    public record HistoryItem(String fromStatus, String toStatus, OffsetDateTime at) {
    }

    public record ReservationView(String publicId, VenueRef venue, CourtRef court, OffsetDateTime startsAt,
                                  OffsetDateTime endsAt, int totalAmount, String status, OffsetDateTime holdExpiresAt,
                                  OffsetDateTime createdAt, OffsetDateTime canceledAt, String canceledBy,
                                  String cancelReason, JsonNode cancelPolicy, Integer refundIfCanceledNow,
                                  PaymentInfo payment, List<RefundInfo> refunds, List<HistoryItem> history) {
    }

    public record ReservationListItem(String publicId, String venueName, String courtName, OffsetDateTime startsAt,
                                      OffsetDateTime endsAt, int totalAmount, String status,
                                      OffsetDateTime holdExpiresAt) {
    }

    // ------------------------------------------------------------- 생성

    public ReservationView create(long userId, long courtId, OffsetDateTime startsAt, OffsetDateTime endsAt) {
        if (!props.payment().isConfigured()) throw ApiException.unavailable("PAYMENT_NOT_CONFIGURED");
        if (startsAt == null || endsAt == null) throw ApiException.badRequest("VALIDATION_FAILED");
        Long id = jdbc.queryForObject("SELECT fn_create_reservation_hold(?, ?, ?, ?, ?)", Long.class,
                userId, courtId, startsAt, endsAt, props.payment().holdMinutes());
        return view(id);
    }

    // ------------------------------------------------------------- 조회

    public List<ReservationListItem> list(long userId, String status, int page, int limit) {
        if (status != null && !STATUSES.contains(status)) throw ApiException.badRequest("VALIDATION_FAILED");
        return jdbc.query("""
                SELECT r.public_id::text, v.name, c.name, lower(r.period), upper(r.period), r.total_amount, r.status,
                       r.hold_expires_at, r.id
                  FROM reservations r JOIN futsal_venues v ON v.id = r.venue_id JOIN courts c ON c.id = r.court_id
                 WHERE r.user_id = ? AND (?::text IS NULL OR r.status = ?)
                 ORDER BY r.id DESC LIMIT ? OFFSET ?""",
                (rs, i) -> new ReservationListItem(rs.getString(1), rs.getString(2), rs.getString(3),
                        rs.getObject(4, OffsetDateTime.class), rs.getObject(5, OffsetDateTime.class), rs.getInt(6),
                        rs.getString(7), rs.getObject(8, OffsetDateTime.class)),
                userId, status, status, Math.min(Math.max(limit, 1), 50), Math.max(page, 0) * Math.min(Math.max(limit, 1), 50));
    }

    /** 소유자·해당 구장 운영자·관리자만 볼 수 있다. 권한 없으면 404 (존재 여부 비노출) */
    public ReservationView detail(long viewerId, boolean viewerIsAdmin, String publicId) {
        long id = idOf(publicId);
        Boolean allowed = jdbc.queryForObject("""
                SELECT r.user_id = ? OR EXISTS (SELECT 1 FROM venue_operators o WHERE o.venue_id = r.venue_id AND o.user_id = ?)
                  FROM reservations r WHERE r.id = ?""", Boolean.class, viewerId, viewerId, id);
        if (!viewerIsAdmin && !Boolean.TRUE.equals(allowed)) throw ApiException.notFound();
        return view(id);
    }

    long idOf(String publicId) {
        if (publicId == null || !publicId.matches("^[0-9a-fA-F-]{36}$")) throw ApiException.notFound();
        List<Long> ids = jdbc.queryForList("SELECT id FROM reservations WHERE public_id = ?::uuid", Long.class, publicId);
        if (ids.isEmpty()) throw ApiException.notFound();
        return ids.get(0);
    }

    ReservationView view(long id) {
        Map<String, Object> r = jdbc.queryForMap("""
                SELECT r.public_id::text AS public_id, r.user_id, r.status, r.total_amount, lower(r.period) AS starts_at,
                       upper(r.period) AS ends_at, r.hold_expires_at, r.created_at, r.canceled_at, r.canceled_by,
                       r.cancel_reason, r.cancel_policy_snapshot::text AS policy,
                       v.id AS venue_id, v.name AS venue_name, v.road_address, v.phone,
                       c.id AS court_id, c.name AS court_name, c.is_indoor, c.size_class,
                       CASE WHEN r.status = 'CONFIRMED' AND lower(r.period) > now()
                            THEN fn_refund_amount(r.total_amount, r.cancel_policy_snapshot, lower(r.period), now()) END AS refund_now
                  FROM reservations r JOIN futsal_venues v ON v.id = r.venue_id JOIN courts c ON c.id = r.court_id
                 WHERE r.id = ?""", id);

        List<PaymentInfo> pays = jdbc.query("""
                SELECT order_id, status, mode, method, amount, approved_amount, balance_amount, receipt_url,
                       failure_code, failure_message, approved_at
                  FROM payments WHERE reservation_id = ?
                 ORDER BY CASE WHEN status IN ('DONE','PARTIAL_CANCELED','CANCELED','IN_PROGRESS') THEN 0 ELSE 1 END, id DESC
                 LIMIT 1""",
                (rs, i) -> new PaymentInfo(rs.getString(1), rs.getString(2), rs.getString(3), rs.getString(4), rs.getInt(5),
                        (Integer) rs.getObject(6), (Integer) rs.getObject(7), rs.getString(8), rs.getString(9),
                        rs.getString(10), rs.getObject(11, OffsetDateTime.class)), id);
        List<RefundInfo> refundRows = jdbc.query("""
                SELECT id, amount, status, reason, created_at, completed_at FROM refunds WHERE reservation_id = ? ORDER BY id""",
                (rs, i) -> new RefundInfo(rs.getLong(1), rs.getInt(2), rs.getString(3), rs.getString(4),
                        rs.getObject(5, OffsetDateTime.class), rs.getObject(6, OffsetDateTime.class)), id);
        List<HistoryItem> history = jdbc.query("""
                SELECT from_status, to_status, changed_at FROM reservation_status_history WHERE reservation_id = ? ORDER BY id""",
                (rs, i) -> new HistoryItem(rs.getString(1), rs.getString(2), rs.getObject(3, OffsetDateTime.class)), id);

        return new ReservationView(
                (String) r.get("public_id"),
                new VenueRef(((Number) r.get("venue_id")).longValue(), (String) r.get("venue_name"),
                        (String) r.get("road_address"), (String) r.get("phone")),
                new CourtRef(((Number) r.get("court_id")).longValue(), (String) r.get("court_name"),
                        (Boolean) r.get("is_indoor"), (String) r.get("size_class")),
                toOffset(r.get("starts_at")), toOffset(r.get("ends_at")),
                ((Number) r.get("total_amount")).intValue(), (String) r.get("status"),
                toOffset(r.get("hold_expires_at")), toOffset(r.get("created_at")), toOffset(r.get("canceled_at")),
                (String) r.get("canceled_by"), (String) r.get("cancel_reason"), parse((String) r.get("policy")),
                r.get("refund_now") == null ? null : ((Number) r.get("refund_now")).intValue(),
                pays.isEmpty() ? null : pays.get(0), refundRows, history);
    }

    // ------------------------------------------------------------- 취소

    public ReservationView cancelByUser(long userId, String publicId, String reason) {
        long id = idOf(publicId);
        Long refundId = jdbc.queryForObject("SELECT fn_cancel_reservation(?, 'USER', ?, ?)", Long.class,
                id, userId, clip(reason, 200));
        afterCancel(id, refundId, false);
        return view(id);
    }

    public ReservationView cancelByOperator(long operatorId, String publicId, String reason) {
        long id = idOf(publicId);
        if (reason == null || reason.isBlank()) throw ApiException.badRequest("VALIDATION_FAILED", "취소 사유를 입력해 주세요");
        Long refundId = jdbc.queryForObject("SELECT fn_cancel_reservation(?, 'OPERATOR', ?, ?)", Long.class,
                id, operatorId, clip(reason, 200));
        afterCancel(id, refundId, true);
        return view(id);
    }

    public ReservationView cancelByAdmin(long adminId, long reservationId, String reason) {
        Long refundId = jdbc.queryForObject("SELECT fn_cancel_reservation(?, 'ADMIN', ?, ?)", Long.class,
                reservationId, adminId, clip(reason, 200));
        afterCancel(reservationId, refundId, true);
        return view(reservationId);
    }

    private void afterCancel(long id, Long refundId, boolean notifyOwner) {
        if (refundId != null) refunds.processSoon(refundId);
        if (notifyOwner) {
            Map<String, Object> r = jdbc.queryForMap("""
                    SELECT r.user_id, v.name, lower(r.period) AS starts_at, r.public_id::text AS pid
                      FROM reservations r JOIN futsal_venues v ON v.id = r.venue_id WHERE r.id = ?""", id);
            notifications.notify(((Number) r.get("user_id")).longValue(), "RESERVATION_CANCELED", null,
                    "RESERVATION", id, "예약이 취소되었어요",
                    r.get("name") + " " + KOREAN.format(toOffset(r.get("starts_at")))
                            + " 예약이 구장 사정으로 취소되었어요. 결제 금액은 전액 환불돼요.",
                    Map.of("reservationId", r.get("pid")));
        }
    }

    // ------------------------------------------------------------- 유틸

    static OffsetDateTime toOffset(Object o) {
        if (o == null) return null;
        if (o instanceof OffsetDateTime odt) return odt;
        if (o instanceof java.sql.Timestamp ts) return ts.toInstant().atZone(ZoneId.of("Asia/Seoul")).toOffsetDateTime();
        if (o instanceof java.time.Instant in) return in.atZone(ZoneId.of("Asia/Seoul")).toOffsetDateTime();
        throw new IllegalStateException("unexpected time type " + o.getClass());
    }

    private JsonNode parse(String json) {
        try {
            return json == null ? null : mapper.readTree(json);
        } catch (JsonProcessingException e) {
            return null;
        }
    }

    static String clip(String s, int max) {
        if (s == null) return null;
        String t = s.trim();
        if (t.isEmpty()) return null;
        return t.length() > max ? t.substring(0, max) : t;
    }
}
