package app.fmate.admin;

import app.fmate.auth.AuthUser;
import app.fmate.auth.TokenService;
import app.fmate.common.ApiException;
import app.fmate.media.StorageService;
import app.fmate.notification.NotificationService;
import app.fmate.payment.PaymentService;
import app.fmate.payment.RefundProcessor;
import app.fmate.reservation.ReservationService;
import app.fmate.venue.OperatorService;
import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.Duration;
import java.time.LocalDate;
import java.time.OffsetDateTime;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;

/**
 * 관리자·모더레이터 기능. 상태를 바꾸는 모든 작업은 admin_audit_logs(추가 전용)에 기록한다.
 */
@Service
public class AdminService {

    private final JdbcTemplate jdbc;
    private final ObjectMapper mapper;
    private final StorageService storage;
    private final NotificationService notifications;
    private final TokenService tokens;
    private final ReservationService reservations;
    private final PaymentService payments;
    private final RefundProcessor refunds;

    public AdminService(JdbcTemplate jdbc, ObjectMapper mapper, StorageService storage, NotificationService notifications,
                        TokenService tokens, ReservationService reservations, PaymentService payments,
                        RefundProcessor refunds) {
        this.jdbc = jdbc;
        this.mapper = mapper;
        this.storage = storage;
        this.notifications = notifications;
        this.tokens = tokens;
        this.reservations = reservations;
        this.payments = payments;
        this.refunds = refunds;
    }

    // ------------------------------------------------------------- 감사 로그

    void audit(AuthUser actor, String action, String targetType, Long targetId, Object before, Object after,
               String reason, String ip) {
        jdbc.update("""
                INSERT INTO admin_audit_logs (actor_id, actor_role, action, target_type, target_id, before_state, after_state,
                                              reason, ip_address, request_id)
                VALUES (?, ?, ?, ?, ?, ?::jsonb, ?::jsonb, ?, ?::inet, ?)""",
                actor.id(), actor.role(), action, targetType, targetId, json(before), json(after),
                reason == null ? null : reason.substring(0, Math.min(500, reason.length())), ip,
                app.fmate.common.RequestContextFilter.currentRequestId());
    }

    private String json(Object o) {
        if (o == null) return null;
        try {
            return mapper.writeValueAsString(o);
        } catch (JsonProcessingException e) {
            return null;
        }
    }

    // ------------------------------------------------------------- 대시보드

    public Map<String, Object> dashboard() {
        Map<String, Object> d = new LinkedHashMap<>();
        d.putAll(jdbc.queryForMap("""
                SELECT (SELECT count(*) FROM users WHERE status <> 'DELETED') AS users_total,
                       (SELECT count(*) FROM users WHERE created_at > now() - interval '7 days') AS users_new_7d,
                       (SELECT count(*) FROM futsal_venues WHERE verification_status = 'VERIFIED') AS venues_verified,
                       (SELECT count(*) FROM futsal_venues WHERE verification_status = 'PENDING_REVIEW') AS venues_pending,
                       (SELECT count(*) FROM reservations WHERE status = 'CONFIRMED' AND lower(period) >= date_trunc('day', now())
                                                             AND lower(period) < date_trunc('day', now()) + interval '1 day') AS reservations_today,
                       (SELECT count(*) FROM reservations WHERE created_at > now() - interval '7 days' AND status IN ('CONFIRMED','COMPLETED')) AS reservations_7d,
                       (SELECT COALESCE(sum(approved_amount), 0) FROM payments WHERE status IN ('DONE','PARTIAL_CANCELED')
                                                                              AND approved_at > now() - interval '7 days') AS approved_amount_7d,
                       (SELECT count(*) FROM reports WHERE status IN ('OPEN','REVIEWING')) AS reports_open,
                       (SELECT count(*) FROM refunds WHERE status = 'REQUESTED') AS refunds_pending,
                       (SELECT count(*) FROM refunds WHERE status = 'REQUESTED' AND attempt_count >= 3) AS refunds_failing,
                       (SELECT count(*) FROM payments WHERE status = 'IN_PROGRESS' AND updated_at < now() - interval '10 minutes') AS payments_stuck,
                       (SELECT count(*) FROM app_error_logs WHERE created_at > now() - interval '24 hours') AS errors_24h,
                       (SELECT count(*) FROM videos WHERE status IN ('UPLOADED','PROCESSING')) AS videos_processing"""));
        return d;
    }

    // ------------------------------------------------------------- 회원

    public List<Map<String, Object>> users(String q, String status, int page) {
        String like = q == null || q.isBlank() ? null : "%" + q.trim().replace("%", "\\%").replace("_", "\\_") + "%";
        return jdbc.queryForList("""
                SELECT u.id, u.email::text AS email, u.role, u.status, u.suspended_until, u.created_at, u.last_login_at,
                       p.nickname::text AS nickname,
                       (SELECT count(*) FROM reports r WHERE r.target_type = 'USER' AND r.target_id = u.id) AS reported_count
                  FROM users u LEFT JOIN user_profiles p ON p.user_id = u.id
                 WHERE (?::text IS NULL OR u.email::text ILIKE ? OR p.nickname::text ILIKE ?)
                   AND (?::text IS NULL OR u.status = ?)
                 ORDER BY u.id DESC LIMIT 50 OFFSET ?""",
                like, like, like, status, status, Math.max(page, 0) * 50);
    }

    public Map<String, Object> user(long id) {
        List<Map<String, Object>> rows = jdbc.queryForList("""
                SELECT u.id, u.email::text AS email, u.role, u.status, u.suspended_until, u.email_verified_at, u.created_at,
                       u.last_login_at, p.nickname::text AS nickname, p.bio
                  FROM users u LEFT JOIN user_profiles p ON p.user_id = u.id WHERE u.id = ?""", id);
        if (rows.isEmpty()) throw ApiException.notFound();
        Map<String, Object> u = new LinkedHashMap<>(rows.get(0));
        u.put("sanctions", jdbc.queryForList("""
                SELECT id, kind, reason, starts_at, ends_at, revoked_at, created_by FROM user_sanctions
                 WHERE user_id = ? ORDER BY id DESC""", id));
        u.put("reports", jdbc.queryForList("""
                SELECT id, reason, status, created_at FROM reports WHERE target_type = 'USER' AND target_id = ?
                 ORDER BY id DESC LIMIT 20""", id));
        return u;
    }

    public record SanctionInput(String kind, Integer days, String reason, Long reportId) {
    }

    @Transactional
    public void sanction(AuthUser actor, long userId, SanctionInput in, String ip) {
        if (in.reason() == null || in.reason().isBlank()) throw ApiException.badRequest("VALIDATION_FAILED", "사유를 입력해 주세요");
        if (!Set.of("WARNING", "SUSPENSION", "PERMANENT_BAN").contains(in.kind())) throw ApiException.badRequest("VALIDATION_FAILED");
        if ("PERMANENT_BAN".equals(in.kind()) && !actor.isAdmin()) throw ApiException.forbidden("FORBIDDEN");
        String targetRole = jdbc.queryForObject("SELECT role FROM users WHERE id = ?", String.class, userId);
        if ("ADMIN".equals(targetRole) || ("MODERATOR".equals(targetRole) && !actor.isAdmin())) {
            throw ApiException.forbidden("FORBIDDEN");
        }
        Map<String, Object> before = jdbc.queryForMap("SELECT status, suspended_until FROM users WHERE id = ?", userId);
        OffsetDateTime ends = null;
        if ("SUSPENSION".equals(in.kind())) {
            int days = in.days() == null ? 7 : Math.min(Math.max(in.days(), 1), 365);
            ends = OffsetDateTime.now().plusDays(days);
        }
        jdbc.update("""
                INSERT INTO user_sanctions (user_id, kind, reason, report_id, ends_at, created_by) VALUES (?, ?, ?, ?, ?, ?)""",
                userId, in.kind(), in.reason().trim(), in.reportId(), ends, actor.id());
        if (!"WARNING".equals(in.kind())) {
            jdbc.update("UPDATE users SET status = 'SUSPENDED', suspended_until = ? WHERE id = ? AND status <> 'DELETED'",
                    ends, userId);
            tokens.revokeAll(userId, "ADMIN");
        }
        notifications.notify(userId, "CONTENT_ACTIONED", null, "USER", userId,
                "WARNING".equals(in.kind()) ? "운영정책 위반 경고" : "이용이 제한되었어요",
                in.reason().trim() + (ends == null ? "" : " (해제 예정: " + ends.toLocalDate() + ")"), null);
        audit(actor, "USER_" + in.kind(), "USER", userId, before, Map.of("kind", in.kind(), "endsAt", String.valueOf(ends)),
                in.reason(), ip);
    }

    @Transactional
    public void liftSanction(AuthUser actor, long userId, String reason, String ip) {
        jdbc.update("UPDATE user_sanctions SET revoked_at = now() WHERE user_id = ? AND revoked_at IS NULL", userId);
        jdbc.update("UPDATE users SET status = 'ACTIVE', suspended_until = NULL WHERE id = ? AND status = 'SUSPENDED'", userId);
        audit(actor, "USER_SANCTION_LIFT", "USER", userId, null, null, reason, ip);
    }

    @Transactional
    public void setRole(AuthUser actor, long userId, String role, String ip) {
        if (!actor.isAdmin()) throw ApiException.forbidden("FORBIDDEN");
        if (!Set.of("USER", "VENUE_OPERATOR", "MODERATOR", "ADMIN").contains(role)) throw ApiException.badRequest("VALIDATION_FAILED");
        if (userId == actor.id()) throw ApiException.badRequest("INVALID_TARGET", "자기 자신의 권한은 바꿀 수 없어요");
        String before = jdbc.queryForObject("SELECT role FROM users WHERE id = ?", String.class, userId);
        jdbc.update("UPDATE users SET role = ? WHERE id = ?", role, userId);
        tokens.revokeAll(userId, "ADMIN");
        audit(actor, "USER_ROLE_CHANGE", "USER", userId, Map.of("role", before), Map.of("role", role), null, ip);
    }

    // ------------------------------------------------------------- 구장 검증

    public List<Map<String, Object>> venues(String status, int page) {
        return jdbc.queryForList("""
                SELECT v.id, v.name, v.road_address, v.region_code, v.verification_status, v.business_reg_no, v.created_at,
                       (SELECT string_agg(p.nickname::text, ', ') FROM venue_operators o JOIN user_profiles p ON p.user_id = o.user_id
                         WHERE o.venue_id = v.id AND o.role = 'OWNER') AS owners
                  FROM futsal_venues v WHERE (?::text IS NULL OR v.verification_status = ?)
                 ORDER BY CASE WHEN v.verification_status = 'PENDING_REVIEW' THEN 0 ELSE 1 END, v.created_at
                 LIMIT 50 OFFSET ?""", status, status, Math.max(page, 0) * 50);
    }

    public Map<String, Object> venue(long venueId) {
        List<Map<String, Object>> rows = jdbc.queryForList("""
                SELECT id, name, description, road_address, detail_address, region_code, latitude, longitude, phone,
                       business_reg_no, verification_status, rejection_reason, verified_at, data_source, created_at
                  FROM futsal_venues WHERE id = ?""", venueId);
        if (rows.isEmpty()) throw ApiException.notFound();
        Map<String, Object> v = new LinkedHashMap<>(rows.get(0));
        List<Map<String, Object>> docs = new ArrayList<>();
        for (Map<String, Object> d : jdbc.queryForList(
                "SELECT id, kind, object_key, created_at FROM venue_documents WHERE venue_id = ? ORDER BY id", venueId)) {
            Map<String, Object> doc = new LinkedHashMap<>(d);
            String key = (String) d.get("object_key");
            doc.remove("object_key");
            // 서류는 비공개 버킷 — 10분짜리 열람 링크만 발급
            doc.put("viewUrl", storage.isConfigured() ? storage.presignGet(storage.rawBucket(), key, Duration.ofMinutes(10)) : null);
            docs.add(doc);
        }
        v.put("documents", docs);
        v.put("operators", jdbc.queryForList("""
                SELECT o.user_id, o.role, p.nickname::text AS nickname, u.email::text AS email FROM venue_operators o
                  JOIN users u ON u.id = o.user_id LEFT JOIN user_profiles p ON p.user_id = o.user_id WHERE o.venue_id = ?""", venueId));
        v.put("courts", jdbc.queryForList("SELECT id, name, is_indoor, surface, size_class, is_active FROM courts WHERE venue_id = ?", venueId));
        return v;
    }

    @Transactional
    public void decideVenue(AuthUser actor, long venueId, String decision, String reason, String ip) {
        if (!actor.isAdmin()) throw ApiException.forbidden("FORBIDDEN");
        String before = jdbc.queryForObject("SELECT verification_status FROM futsal_venues WHERE id = ? FOR UPDATE",
                String.class, venueId);
        String title;
        String body;
        switch (decision) {
            case "APPROVE" -> {
                jdbc.update("""
                        UPDATE futsal_venues SET verification_status = 'VERIFIED', verified_at = now(), verified_by = ?,
                               rejection_reason = NULL WHERE id = ?""", actor.id(), venueId);
                for (Long court : jdbc.queryForList("SELECT id FROM courts WHERE venue_id = ? AND is_active", Long.class, venueId)) {
                    jdbc.queryForObject("SELECT generate_time_slots(?, ?, ?)", Integer.class, court, LocalDate.now(),
                            OperatorService.SLOT_HORIZON_DAYS);
                }
                title = "구장 입점이 승인되었어요";
                body = "이제 F-Mate 에서 예약을 받을 수 있어요. 운영시간과 요금을 확인해 주세요.";
            }
            case "REJECT" -> {
                if (reason == null || reason.isBlank()) throw ApiException.badRequest("VALIDATION_FAILED", "반려 사유를 입력해 주세요");
                jdbc.update("UPDATE futsal_venues SET verification_status = 'REJECTED', rejection_reason = ? WHERE id = ?",
                        reason.trim(), venueId);
                title = "구장 입점 신청이 반려되었어요";
                body = reason.trim();
            }
            case "SUSPEND" -> {
                jdbc.update("UPDATE futsal_venues SET verification_status = 'SUSPENDED' WHERE id = ?", venueId);
                title = "구장 노출이 중지되었어요";
                body = reason == null ? "운영팀에 문의해 주세요." : reason.trim();
            }
            default -> throw ApiException.badRequest("VALIDATION_FAILED");
        }
        for (Long owner : jdbc.queryForList("SELECT user_id FROM venue_operators WHERE venue_id = ?", Long.class, venueId)) {
            notifications.notify(owner, "SYSTEM", null, null, null, title, body, Map.of("venueId", venueId));
        }
        audit(actor, "VENUE_" + decision, "VENUE", venueId, Map.of("status", before), null, reason, ip);
    }

    // ------------------------------------------------------------- 예약·결제

    public List<Map<String, Object>> reservations(String q, String status, int page) {
        String pid = q != null && q.matches("^[0-9a-fA-F-]{36}$") ? q : null;
        return jdbc.queryForList("""
                SELECT r.id, r.public_id::text AS public_id, v.name AS venue, c.name AS court, lower(r.period) AS starts_at,
                       r.total_amount, r.status, COALESCE(p.nickname::text, '(탈퇴)') AS user_nickname, r.created_at
                  FROM reservations r JOIN futsal_venues v ON v.id = r.venue_id JOIN courts c ON c.id = r.court_id
                  LEFT JOIN user_profiles p ON p.user_id = r.user_id
                 WHERE (?::uuid IS NULL OR r.public_id = ?::uuid) AND (?::text IS NULL OR r.status = ?)
                 ORDER BY r.id DESC LIMIT 50 OFFSET ?""", pid, pid, status, status, Math.max(page, 0) * 50);
    }

    public ReservationService.ReservationView cancelReservation(AuthUser actor, String publicId, String reason, String ip) {
        if (!actor.isAdmin()) throw ApiException.forbidden("FORBIDDEN");
        if (reason == null || reason.isBlank()) throw ApiException.badRequest("VALIDATION_FAILED", "취소 사유를 입력해 주세요");
        List<Long> ids = jdbc.queryForList("SELECT id FROM reservations WHERE public_id = ?::uuid", Long.class, publicId);
        if (ids.isEmpty()) throw ApiException.notFound();
        ReservationService.ReservationView v = reservations.cancelByAdmin(actor.id(), ids.get(0), reason);
        audit(actor, "RESERVATION_CANCEL", "RESERVATION", ids.get(0), null, Map.of("status", v.status()), reason, ip);
        return v;
    }

    public List<Map<String, Object>> payments(String status, int page) {
        return jdbc.queryForList("""
                SELECT p.id, p.order_id, p.mode, p.status, p.amount, p.approved_amount, p.balance_amount, p.method,
                       p.failure_code, p.created_at, p.approved_at, r.public_id::text AS reservation_id
                  FROM payments p JOIN reservations r ON r.id = p.reservation_id
                 WHERE (?::text IS NULL OR p.status = ?)
                 ORDER BY p.id DESC LIMIT 50 OFFSET ?""", status, status, Math.max(page, 0) * 50);
    }

    public Map<String, Object> payment(String orderId) {
        List<Map<String, Object>> rows = jdbc.queryForList("""
                SELECT p.*, r.public_id::text AS reservation_public_id FROM payments p
                  JOIN reservations r ON r.id = p.reservation_id WHERE p.order_id = ?""", orderId);
        if (rows.isEmpty()) throw ApiException.notFound();
        Map<String, Object> p = new LinkedHashMap<>(rows.get(0));
        p.remove("webhook_secret");   // 비밀값은 관리자 화면에도 노출하지 않는다
        long id = ((Number) p.get("id")).longValue();
        p.put("refunds", jdbc.queryForList("""
                SELECT id, amount, status, reason, requested_by, attempt_count, failure_code, failure_message, created_at, completed_at
                  FROM refunds WHERE payment_id = ? ORDER BY id""", id));
        p.put("auditLogs", jdbc.queryForList("""
                SELECT id, refund_id, action, outcome, http_status, provider_code, detail::text AS detail, created_at
                  FROM payment_audit_logs WHERE payment_id = ? ORDER BY id""", id));
        return p;
    }

    public PaymentService.ConfirmResult reconcile(AuthUser actor, String orderId, String ip) {
        PaymentService.ConfirmResult r = payments.reconcile(orderId);
        audit(actor, "PAYMENT_RECONCILE", "PAYMENT", null, null, Map.of("orderId", orderId, "outcome", r.outcome().name()), null, ip);
        return r;
    }

    public void retryRefund(AuthUser actor, long refundId, String ip) {
        if (!actor.isAdmin()) throw ApiException.forbidden("FORBIDDEN");
        refunds.process(refundId);
        audit(actor, "REFUND_RETRY", "REFUND", refundId, null, null, null, ip);
    }

    // ------------------------------------------------------------- 신고

    public List<Map<String, Object>> reports(String status, int page) {
        String s = status == null ? "OPEN" : status;
        return jdbc.queryForList("""
                SELECT r.target_type, r.target_id, count(*) AS report_count, count(DISTINCT r.reporter_id) AS reporter_count,
                       string_agg(DISTINCT r.reason, ',') AS reasons, min(r.created_at) AS first_reported_at,
                       CASE r.target_type
                         WHEN 'POST' THEN (SELECT left(coalesce(p.caption, '(사진/영상)'), 200) FROM posts p WHERE p.id = r.target_id)
                         WHEN 'COMMENT' THEN (SELECT left(c.body, 200) FROM comments c WHERE c.id = r.target_id)
                         WHEN 'USER' THEN (SELECT nickname::text FROM user_profiles WHERE user_id = r.target_id)
                         WHEN 'MESSAGE' THEN (SELECT left(m.body, 200) FROM messages m WHERE m.id = r.target_id)
                         WHEN 'VENUE' THEN (SELECT name FROM futsal_venues WHERE id = r.target_id)
                       END AS preview,
                       CASE r.target_type
                         WHEN 'POST' THEN (SELECT author_id FROM posts WHERE id = r.target_id)
                         WHEN 'COMMENT' THEN (SELECT author_id FROM comments WHERE id = r.target_id)
                         WHEN 'MESSAGE' THEN (SELECT sender_id FROM messages WHERE id = r.target_id)
                         WHEN 'USER' THEN r.target_id
                       END AS owner_user_id
                  FROM reports r WHERE r.status = ?
                 GROUP BY r.target_type, r.target_id
                 ORDER BY count(DISTINCT r.reporter_id) DESC, min(r.created_at)
                 LIMIT 50 OFFSET ?""", s, Math.max(page, 0) * 50);
    }

    public record Resolution(String action, String note, SanctionInput sanction) {
    }

    /** action: DISMISS | HIDE | DELETE | RESTORE. sanction 이 있으면 작성자 제재도 함께. */
    @Transactional
    public void resolveReports(AuthUser actor, String targetType, long targetId, Resolution r, String ip) {
        String action = r.action() == null ? "" : r.action();
        Long owner = null;
        switch (targetType) {
            case "POST" -> {
                owner = jdbc.query("SELECT author_id FROM posts WHERE id = ?", rs -> rs.next() ? rs.getLong(1) : null, targetId);
                switch (action) {
                    case "HIDE" -> jdbc.update("UPDATE posts SET status = 'HIDDEN_BY_MODERATION' WHERE id = ? AND status = 'ACTIVE'", targetId);
                    case "DELETE" -> jdbc.update("UPDATE posts SET status = 'DELETED', deleted_at = now() WHERE id = ?", targetId);
                    case "RESTORE", "DISMISS" -> jdbc.update("UPDATE posts SET status = 'ACTIVE' WHERE id = ? AND status = 'HIDDEN_BY_MODERATION'", targetId);
                    default -> throw ApiException.badRequest("VALIDATION_FAILED");
                }
                if ("DELETE".equals(action)) {
                    jdbc.update("UPDATE videos SET status = 'DELETED' WHERE post_id = ? AND status <> 'DELETED'", targetId);
                }
            }
            case "COMMENT" -> {
                owner = jdbc.query("SELECT author_id FROM comments WHERE id = ?", rs -> rs.next() ? rs.getLong(1) : null, targetId);
                switch (action) {
                    case "HIDE" -> jdbc.update("UPDATE comments SET status = 'HIDDEN_BY_MODERATION' WHERE id = ? AND status = 'ACTIVE'", targetId);
                    case "DELETE" -> jdbc.update("UPDATE comments SET status = 'DELETED' WHERE id = ?", targetId);
                    case "RESTORE", "DISMISS" -> jdbc.update("UPDATE comments SET status = 'ACTIVE' WHERE id = ? AND status = 'HIDDEN_BY_MODERATION'", targetId);
                    default -> throw ApiException.badRequest("VALIDATION_FAILED");
                }
            }
            case "MESSAGE" -> {
                owner = jdbc.query("SELECT sender_id FROM messages WHERE id = ?", rs -> rs.next() ? rs.getLong(1) : null, targetId);
                if ("DELETE".equals(action) || "HIDE".equals(action)) {
                    jdbc.update("UPDATE messages SET body = '(운영정책에 따라 삭제된 메시지)', deleted_at = now() WHERE id = ?", targetId);
                } else if (!"DISMISS".equals(action)) {
                    throw ApiException.badRequest("VALIDATION_FAILED");
                }
            }
            case "USER" -> {
                owner = targetId;
                if (!"DISMISS".equals(action) && r.sanction() == null) throw ApiException.badRequest("VALIDATION_FAILED");
            }
            case "VENUE" -> {
                if ("HIDE".equals(action)) {
                    if (!actor.isAdmin()) throw ApiException.forbidden("FORBIDDEN");
                    jdbc.update("UPDATE futsal_venues SET verification_status = 'SUSPENDED' WHERE id = ?", targetId);
                } else if (!"DISMISS".equals(action)) {
                    throw ApiException.badRequest("VALIDATION_FAILED");
                }
            }
            default -> throw ApiException.badRequest("VALIDATION_FAILED");
        }
        String reportStatus = "DISMISS".equals(action) ? "DISMISSED" : "ACTIONED";
        jdbc.update("""
                UPDATE reports SET status = ?, handled_by = ?, handled_at = now(), resolution_note = ?
                 WHERE target_type = ? AND target_id = ? AND status IN ('OPEN','REVIEWING')""",
                reportStatus, actor.id(), r.note(), targetType, targetId);
        if (r.sanction() != null && owner != null) {
            sanction(actor, owner, r.sanction(), ip);
        } else if (owner != null && !"DISMISS".equals(action) && !"RESTORE".equals(action)) {
            notifications.notify(owner, "CONTENT_ACTIONED", null, targetType, targetId, "운영정책에 따라 콘텐츠가 조치되었어요",
                    r.note() == null ? "커뮤니티 운영정책을 확인해 주세요." : r.note(), null);
        }
        audit(actor, "REPORT_" + action, targetType, targetId, null, Map.of("reportStatus", reportStatus), r.note(), ip);
    }

    // ------------------------------------------------------------- 로그

    public List<Map<String, Object>> auditLogs(int page) {
        return jdbc.queryForList("""
                SELECT a.id, a.actor_id, p.nickname::text AS actor_nickname, a.actor_role, a.action, a.target_type, a.target_id,
                       a.before_state::text AS before_state, a.after_state::text AS after_state, a.reason, a.created_at
                  FROM admin_audit_logs a LEFT JOIN user_profiles p ON p.user_id = a.actor_id
                 ORDER BY a.id DESC LIMIT 100 OFFSET ?""", Math.max(page, 0) * 100);
    }

    public List<Map<String, Object>> errorLogs(int page) {
        return jdbc.queryForList("""
                SELECT id, request_id, method, path, user_id, error_class, message, created_at FROM app_error_logs
                 ORDER BY id DESC LIMIT 100 OFFSET ?""", Math.max(page, 0) * 100);
    }
}
