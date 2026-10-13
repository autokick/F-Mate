package app.fmate.venue;

import app.fmate.common.ApiException;
import app.fmate.media.MediaController;
import app.fmate.media.MediaKeys;
import app.fmate.media.StorageService;
import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDate;
import java.time.OffsetDateTime;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.Set;

/** 구장 운영자 기능. 모든 메서드는 해당 구장의 운영자인지 먼저 확인한다. */
@Service
public class OperatorService {

    public static final int SLOT_HORIZON_DAYS = 30;
    private static final Set<String> SURFACES = Set.of("ARTIFICIAL_TURF", "URETHANE", "WOOD", "OTHER");
    private static final Set<String> SIZES = Set.of("4V4", "5V5", "6V6", "7V7");

    private final JdbcTemplate jdbc;
    private final MediaKeys mediaKeys;
    private final StorageService storage;
    private final ObjectMapper mapper;
    private final VenueService venues;

    public OperatorService(JdbcTemplate jdbc, MediaKeys mediaKeys, StorageService storage, ObjectMapper mapper,
                           VenueService venues) {
        this.jdbc = jdbc;
        this.mediaKeys = mediaKeys;
        this.storage = storage;
        this.mapper = mapper;
        this.venues = venues;
    }

    // ------------------------------------------------------------- 권한

    public void requireOperator(long userId, long venueId) {
        Boolean ok = jdbc.queryForObject(
                "SELECT EXISTS (SELECT 1 FROM venue_operators WHERE venue_id = ? AND user_id = ?)", Boolean.class, venueId, userId);
        if (!Boolean.TRUE.equals(ok)) throw ApiException.forbidden("FORBIDDEN");
    }

    public void requireOwner(long userId, long venueId) {
        Boolean ok = jdbc.queryForObject(
                "SELECT EXISTS (SELECT 1 FROM venue_operators WHERE venue_id = ? AND user_id = ? AND role = 'OWNER')",
                Boolean.class, venueId, userId);
        if (!Boolean.TRUE.equals(ok)) throw ApiException.forbidden("FORBIDDEN");
    }

    public long venueOfCourt(long courtId) {
        List<Long> v = jdbc.queryForList("SELECT venue_id FROM courts WHERE id = ?", Long.class, courtId);
        if (v.isEmpty()) throw ApiException.notFound();
        return v.get(0);
    }

    // ------------------------------------------------------------- 입점 신청

    public record CourtInput(String name, boolean isIndoor, String surface, String sizeClass, Double widthM,
                             Double lengthM) {
    }

    public record VenueInput(String name, String description, String roadAddress, String detailAddress,
                             String regionCode, Double latitude, Double longitude, String phone, String businessRegNo,
                             String rules, JsonNode cancelPolicy, List<String> facilities, List<String> photoKeys,
                             List<String> documentKeys, List<CourtInput> courts) {
    }

    @Transactional
    public long apply(long userId, boolean emailVerified, VenueInput in) {
        if (!emailVerified) throw ApiException.forbidden("EMAIL_NOT_VERIFIED");
        requireText(in.name(), 2, 100);
        requireText(in.roadAddress(), 5, 200);
        if (in.regionCode() == null || !in.regionCode().matches("^[0-9]{5,10}$")) throw ApiException.badRequest("VALIDATION_FAILED", "지역 코드를 확인해 주세요");
        if (in.latitude() == null || in.longitude() == null) throw ApiException.badRequest("VALIDATION_FAILED", "구장 위치(위도·경도)가 필요해요");
        if (in.businessRegNo() == null || !in.businessRegNo().replace("-", "").matches("^[0-9]{10}$")) {
            throw ApiException.badRequest("VALIDATION_FAILED", "사업자등록번호 10자리를 입력해 주세요");
        }
        if (in.documentKeys() == null || in.documentKeys().isEmpty()) {
            throw ApiException.badRequest("VALIDATION_FAILED", "사업자등록증을 첨부해 주세요");
        }
        if (in.courts() == null || in.courts().isEmpty() || in.courts().size() > 20) {
            throw ApiException.badRequest("VALIDATION_FAILED", "코트를 1개 이상 등록해 주세요");
        }
        Integer pending = jdbc.queryForObject("""
                SELECT count(*) FROM futsal_venues v JOIN venue_operators o ON o.venue_id = v.id
                 WHERE o.user_id = ? AND v.verification_status = 'PENDING_REVIEW'""", Integer.class, userId);
        if (pending != null && pending >= 3) throw ApiException.conflict("INVALID_STATE", "심사 대기 중인 신청이 너무 많아요");

        mediaKeys.requireOwnedUploads(MediaController.Purpose.VENUE_DOCUMENT, userId, in.documentKeys());
        mediaKeys.requireOwnedUploads(MediaController.Purpose.VENUE_PHOTO, userId, in.photoKeys());

        Long venueId = jdbc.queryForObject("""
                INSERT INTO futsal_venues (name, description, road_address, detail_address, region_code, latitude, longitude,
                                           phone, business_reg_no, rules, cancel_policy, data_source)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, COALESCE(?::jsonb, '[{"hoursBefore":72,"refundPercent":100},{"hoursBefore":24,"refundPercent":50},{"hoursBefore":0,"refundPercent":0}]'::jsonb), 'OPERATOR')
                RETURNING id""", Long.class,
                in.name().trim(), trimOrNull(in.description()), in.roadAddress().trim(), trimOrNull(in.detailAddress()),
                in.regionCode(), in.latitude(), in.longitude(), trimOrNull(in.phone()),
                in.businessRegNo().replace("-", ""), trimOrNull(in.rules()), policyJson(in.cancelPolicy()));
        jdbc.update("INSERT INTO venue_operators (venue_id, user_id, role) VALUES (?, ?, 'OWNER')", venueId, userId);
        jdbc.update("UPDATE users SET role = 'VENUE_OPERATOR' WHERE id = ? AND role = 'USER'", userId);
        for (String key : in.documentKeys()) {
            jdbc.update("INSERT INTO venue_documents (venue_id, kind, object_key, uploaded_by) VALUES (?, 'BUSINESS_REGISTRATION', ?, ?)",
                    venueId, key, userId);
        }
        replacePhotos(venueId, in.photoKeys());
        replaceFacilities(venueId, in.facilities());
        for (CourtInput c : in.courts()) addCourt(venueId, c);
        return venueId;
    }

    public record MyVenue(long id, String name, String roadAddress, String verificationStatus, String rejectionReason,
                          String role, int courtCount) {
    }

    public List<MyVenue> myVenues(long userId) {
        return jdbc.query("""
                SELECT v.id, v.name, v.road_address, v.verification_status, v.rejection_reason, o.role,
                       (SELECT count(*)::int FROM courts c WHERE c.venue_id = v.id)
                  FROM venue_operators o JOIN futsal_venues v ON v.id = o.venue_id
                 WHERE o.user_id = ? ORDER BY v.created_at DESC""",
                (rs, i) -> new MyVenue(rs.getLong(1), rs.getString(2), rs.getString(3), rs.getString(4),
                        rs.getString(5), rs.getString(6), rs.getInt(7)), userId);
    }

    public VenueService.VenueDetail venue(long userId, long venueId) {
        requireOperator(userId, venueId);
        return venues.detail(venueId, true);
    }

    @Transactional
    public void updateVenue(long userId, long venueId, VenueInput in) {
        requireOperator(userId, venueId);
        String status = jdbc.queryForObject("SELECT verification_status FROM futsal_venues WHERE id = ? FOR UPDATE",
                String.class, venueId);
        boolean locked = "VERIFIED".equals(status) || "SUSPENDED".equals(status);
        // 검증된 구장의 이름·주소·위치·사업자번호는 관리자 재검증 없이 바꿀 수 없다
        if (!locked) {
            if (in.name() != null) {
                requireText(in.name(), 2, 100);
                jdbc.update("UPDATE futsal_venues SET name = ? WHERE id = ?", in.name().trim(), venueId);
            }
            if (in.roadAddress() != null) {
                requireText(in.roadAddress(), 5, 200);
                jdbc.update("UPDATE futsal_venues SET road_address = ?, detail_address = ? WHERE id = ?",
                        in.roadAddress().trim(), trimOrNull(in.detailAddress()), venueId);
            }
            if (in.regionCode() != null && in.regionCode().matches("^[0-9]{5,10}$")) {
                jdbc.update("UPDATE futsal_venues SET region_code = ? WHERE id = ?", in.regionCode(), venueId);
            }
            if (in.latitude() != null && in.longitude() != null) {
                jdbc.update("UPDATE futsal_venues SET latitude = ?, longitude = ? WHERE id = ?", in.latitude(), in.longitude(), venueId);
            }
            if ("REJECTED".equals(status)) {
                // 보완 후 재심사
                jdbc.update("UPDATE futsal_venues SET verification_status = 'PENDING_REVIEW', rejection_reason = NULL WHERE id = ?", venueId);
            }
        } else if (in.name() != null || in.roadAddress() != null || in.latitude() != null) {
            throw ApiException.conflict("INVALID_STATE", "검증된 구장의 이름·주소 변경은 고객센터로 요청해 주세요");
        }
        if (in.description() != null) jdbc.update("UPDATE futsal_venues SET description = ? WHERE id = ?", trimOrNull(in.description()), venueId);
        if (in.phone() != null) jdbc.update("UPDATE futsal_venues SET phone = ? WHERE id = ?", trimOrNull(in.phone()), venueId);
        if (in.rules() != null) jdbc.update("UPDATE futsal_venues SET rules = ? WHERE id = ?", trimOrNull(in.rules()), venueId);
        if (in.cancelPolicy() != null) jdbc.update("UPDATE futsal_venues SET cancel_policy = ?::jsonb WHERE id = ?", policyJson(in.cancelPolicy()), venueId);
        if (in.facilities() != null) replaceFacilities(venueId, in.facilities());
        if (in.photoKeys() != null) {
            for (String k : in.photoKeys()) {
                boolean existing = Boolean.TRUE.equals(jdbc.queryForObject(
                        "SELECT EXISTS (SELECT 1 FROM venue_photos WHERE venue_id = ? AND object_key = ?)", Boolean.class, venueId, k));
                if (!existing) mediaKeys.requireOwnedUpload(MediaController.Purpose.VENUE_PHOTO, userId, k);
            }
            List<String> removed = jdbc.queryForList("SELECT object_key FROM venue_photos WHERE venue_id = ?", String.class, venueId)
                    .stream().filter(k -> !in.photoKeys().contains(k)).toList();
            replacePhotos(venueId, in.photoKeys());
            storage.deletePublicQuietly(removed);
        }
    }

    private void replacePhotos(long venueId, List<String> keys) {
        jdbc.update("DELETE FROM venue_photos WHERE venue_id = ?", venueId);
        if (keys == null) return;
        if (keys.size() > 20) throw ApiException.badRequest("VALIDATION_FAILED", "사진은 20장까지 올릴 수 있어요");
        for (int i = 0; i < keys.size(); i++) {
            jdbc.update("INSERT INTO venue_photos (venue_id, object_key, sort_order) VALUES (?, ?, ?)", venueId, keys.get(i), i);
        }
    }

    private void replaceFacilities(long venueId, List<String> codes) {
        jdbc.update("DELETE FROM venue_facilities WHERE venue_id = ?", venueId);
        if (codes == null) return;
        for (String code : codes.stream().distinct().toList()) {
            jdbc.update("INSERT INTO venue_facilities (venue_id, facility_code) VALUES (?, ?)", venueId, code);
        }
    }

    // ------------------------------------------------------------- 코트

    public long addCourt(long venueId, CourtInput c) {
        requireText(c.name(), 1, 50);
        if (!SURFACES.contains(c.surface()) || !SIZES.contains(c.sizeClass())) throw ApiException.badRequest("VALIDATION_FAILED");
        return jdbc.queryForObject("""
                INSERT INTO courts (venue_id, name, is_indoor, surface, size_class, width_m, length_m)
                VALUES (?, ?, ?, ?, ?, ?, ?) RETURNING id""", Long.class,
                venueId, c.name().trim(), c.isIndoor(), c.surface(), c.sizeClass(), c.widthM(), c.lengthM());
    }

    public long addCourt(long userId, long venueId, CourtInput c) {
        requireOperator(userId, venueId);
        return addCourt(venueId, c);
    }

    public record CourtUpdate(String name, Boolean isIndoor, String surface, String sizeClass, Double widthM,
                              Double lengthM, Boolean isActive) {
    }

    @Transactional
    public void updateCourt(long userId, long courtId, CourtUpdate u) {
        long venueId = venueOfCourt(courtId);
        requireOperator(userId, venueId);
        if (u.name() != null) {
            requireText(u.name(), 1, 50);
            jdbc.update("UPDATE courts SET name = ? WHERE id = ?", u.name().trim(), courtId);
        }
        if (u.isIndoor() != null) jdbc.update("UPDATE courts SET is_indoor = ? WHERE id = ?", u.isIndoor(), courtId);
        if (u.surface() != null) {
            if (!SURFACES.contains(u.surface())) throw ApiException.badRequest("VALIDATION_FAILED");
            jdbc.update("UPDATE courts SET surface = ? WHERE id = ?", u.surface(), courtId);
        }
        if (u.sizeClass() != null) {
            if (!SIZES.contains(u.sizeClass())) throw ApiException.badRequest("VALIDATION_FAILED");
            jdbc.update("UPDATE courts SET size_class = ? WHERE id = ?", u.sizeClass(), courtId);
        }
        if (u.widthM() != null) jdbc.update("UPDATE courts SET width_m = ? WHERE id = ?", u.widthM(), courtId);
        if (u.lengthM() != null) jdbc.update("UPDATE courts SET length_m = ? WHERE id = ?", u.lengthM(), courtId);
        if (u.isActive() != null) jdbc.update("UPDATE courts SET is_active = ? WHERE id = ?", u.isActive(), courtId);
    }

    // ------------------------------------------------------------- 운영시간 → 슬롯

    public record HoursInput(int dayOfWeek, int openMinute, int closeMinute, int slotMinutes, int pricePerSlot) {
    }

    public record HoursRow(long id, int dayOfWeek, int openMinute, int closeMinute, int slotMinutes, int pricePerSlot) {
    }

    public List<HoursRow> hours(long userId, long courtId) {
        requireOperator(userId, venueOfCourt(courtId));
        return jdbc.query("""
                SELECT id, day_of_week, open_minute, close_minute, slot_minutes, price_per_slot
                  FROM operating_hours WHERE court_id = ? ORDER BY day_of_week, open_minute""",
                (rs, i) -> new HoursRow(rs.getLong(1), rs.getInt(2), rs.getInt(3), rs.getInt(4), rs.getInt(5), rs.getInt(6)),
                courtId);
    }

    /**
     * 주간 운영시간을 통째로 교체하고, 앞으로의 템플릿 슬롯을 다시 만든다.
     * 예약이 걸린 슬롯은 그대로 두고(트리거로도 보호), 나머지 미래 템플릿 슬롯만 지우고 다시 생성한다.
     */
    @Transactional
    public int replaceHours(long userId, long courtId, List<HoursInput> hours) {
        requireOperator(userId, venueOfCourt(courtId));
        if (hours == null || hours.size() > 50) throw ApiException.badRequest("VALIDATION_FAILED");
        validateHours(hours);
        jdbc.update("DELETE FROM operating_hours WHERE court_id = ?", courtId);
        for (HoursInput h : hours) {
            jdbc.update("""
                    INSERT INTO operating_hours (court_id, day_of_week, open_minute, close_minute, slot_minutes, price_per_slot)
                    VALUES (?, ?, ?, ?, ?, ?)""",
                    courtId, h.dayOfWeek(), h.openMinute(), h.closeMinute(), h.slotMinutes(), h.pricePerSlot());
        }
        jdbc.update("""
                DELETE FROM time_slots t
                 WHERE t.court_id = ? AND t.source = 'TEMPLATE' AND lower(t.period) > now()
                   AND NOT EXISTS (SELECT 1 FROM reservations r WHERE r.court_id = t.court_id AND r.period && t.period
                                     AND r.status IN ('PENDING_PAYMENT','CONFIRMED'))""", courtId);
        Integer n = jdbc.queryForObject("SELECT generate_time_slots(?, ?, ?)", Integer.class,
                courtId, LocalDate.now(), SLOT_HORIZON_DAYS);
        return n == null ? 0 : n;
    }

    static void validateHours(List<HoursInput> hours) {
        for (HoursInput h : hours) {
            boolean ok = h.dayOfWeek() >= 0 && h.dayOfWeek() <= 6
                    && h.openMinute() >= 0 && h.openMinute() <= 1439
                    && h.closeMinute() > h.openMinute() && h.closeMinute() <= 1440
                    && Set.of(30, 60, 90, 120).contains(h.slotMinutes())
                    && (h.closeMinute() - h.openMinute()) % h.slotMinutes() == 0
                    && h.pricePerSlot() >= 0 && h.pricePerSlot() <= 10_000_000;
            if (!ok) {
                throw ApiException.badRequest("VALIDATION_FAILED",
                        "운영시간을 확인해 주세요 (운영 시간은 슬롯 길이로 나누어 떨어져야 해요)");
            }
        }
        for (int i = 0; i < hours.size(); i++) {
            for (int j = i + 1; j < hours.size(); j++) {
                HoursInput a = hours.get(i);
                HoursInput b = hours.get(j);
                if (a.dayOfWeek() == b.dayOfWeek() && a.openMinute() < b.closeMinute() && b.openMinute() < a.closeMinute()) {
                    throw ApiException.badRequest("VALIDATION_FAILED", "같은 요일의 운영시간이 겹쳐요");
                }
            }
        }
    }

    // ------------------------------------------------------------- 슬롯

    public record OperatorSlot(long id, OffsetDateTime startsAt, OffsetDateTime endsAt, int price, String status,
                               String source, String reservationStatus, String reservationPublicId,
                               String reservedBy) {
    }

    public List<OperatorSlot> slots(long userId, long courtId, LocalDate date) {
        requireOperator(userId, venueOfCourt(courtId));
        return jdbc.query("""
                SELECT t.id, lower(t.period), upper(t.period), t.price, t.status, t.source,
                       r.status, r.public_id::text, p.nickname::text
                  FROM time_slots t
                  LEFT JOIN LATERAL (SELECT * FROM reservations r WHERE r.court_id = t.court_id AND r.period && t.period
                                       AND r.status IN ('PENDING_PAYMENT','CONFIRMED','COMPLETED','NO_SHOW')
                                     ORDER BY r.id DESC LIMIT 1) r ON true
                  LEFT JOIN user_profiles p ON p.user_id = r.user_id
                 WHERE t.court_id = ?
                   AND t.period && tstzrange((?::date)::timestamp AT TIME ZONE 'Asia/Seoul',
                                             ((?::date) + 1)::timestamp AT TIME ZONE 'Asia/Seoul', '[)')
                 ORDER BY lower(t.period)""",
                (rs, i) -> new OperatorSlot(rs.getLong(1), rs.getObject(2, OffsetDateTime.class),
                        rs.getObject(3, OffsetDateTime.class), rs.getInt(4), rs.getString(5), rs.getString(6),
                        rs.getString(7), rs.getString(8), rs.getString(9)),
                courtId, date, date);
    }

    public record SlotUpdate(String status, Integer price) {
    }

    public void updateSlot(long userId, long slotId, SlotUpdate u) {
        List<Long> court = jdbc.queryForList("SELECT court_id FROM time_slots WHERE id = ?", Long.class, slotId);
        if (court.isEmpty()) throw ApiException.notFound();
        requireOperator(userId, venueOfCourt(court.get(0)));
        if (u.status() != null) {
            if (!Set.of("OPEN", "CLOSED").contains(u.status())) throw ApiException.badRequest("VALIDATION_FAILED");
            jdbc.update("UPDATE time_slots SET status = ? WHERE id = ?", u.status(), slotId);
        }
        if (u.price() != null) {
            if (u.price() < 0 || u.price() > 10_000_000) throw ApiException.badRequest("VALIDATION_FAILED");
            jdbc.update("UPDATE time_slots SET price = ?, source = 'MANUAL' WHERE id = ?", u.price(), slotId);
        }
    }

    // ------------------------------------------------------------- 휴무·대관

    public record ClosureInput(Long courtId, OffsetDateTime startsAt, OffsetDateTime endsAt, String reason) {
    }

    public record Closure(long id, Long courtId, OffsetDateTime startsAt, OffsetDateTime endsAt, String reason) {
    }

    public List<Closure> closures(long userId, long venueId) {
        requireOperator(userId, venueId);
        return jdbc.query("""
                SELECT id, court_id, lower(period), upper(period), reason FROM schedule_closures
                 WHERE venue_id = ? AND upper(period) > now() ORDER BY lower(period)""",
                (rs, i) -> new Closure(rs.getLong(1), (Long) rs.getObject(2), rs.getObject(3, OffsetDateTime.class),
                        rs.getObject(4, OffsetDateTime.class), rs.getString(5)), venueId);
    }

    public long addClosure(long userId, long venueId, ClosureInput in) {
        requireOperator(userId, venueId);
        if (in.startsAt() == null || in.endsAt() == null || !in.endsAt().isAfter(in.startsAt())) {
            throw ApiException.badRequest("VALIDATION_FAILED");
        }
        if (in.courtId() != null && venueOfCourt(in.courtId()) != venueId) throw ApiException.badRequest("VALIDATION_FAILED");
        Boolean hasBooking = jdbc.queryForObject("""
                SELECT EXISTS (SELECT 1 FROM reservations r WHERE r.venue_id = ? AND (?::bigint IS NULL OR r.court_id = ?)
                                 AND r.status IN ('PENDING_PAYMENT','CONFIRMED')
                                 AND r.period && tstzrange(?, ?, '[)'))""", Boolean.class,
                venueId, in.courtId(), in.courtId(), in.startsAt(), in.endsAt());
        if (Boolean.TRUE.equals(hasBooking)) {
            throw ApiException.conflict("SLOT_HAS_RESERVATION", "이 기간에 예약이 있어요. 예약을 먼저 취소해 주세요");
        }
        return jdbc.queryForObject("""
                INSERT INTO schedule_closures (venue_id, court_id, period, reason, created_by)
                VALUES (?, ?, tstzrange(?, ?, '[)'), ?, ?) RETURNING id""", Long.class,
                venueId, in.courtId(), in.startsAt(), in.endsAt(), trimOrNull(in.reason()), userId);
    }

    public void deleteClosure(long userId, long venueId, long closureId) {
        requireOperator(userId, venueId);
        jdbc.update("DELETE FROM schedule_closures WHERE id = ? AND venue_id = ?", closureId, venueId);
    }

    // ------------------------------------------------------------- 예약 현황

    public record OperatorReservation(String publicId, long courtId, String courtName, OffsetDateTime startsAt,
                                      OffsetDateTime endsAt, int totalAmount, String status, String userNickname,
                                      OffsetDateTime createdAt) {
    }

    public List<OperatorReservation> reservations(long userId, long venueId, LocalDate date) {
        requireOperator(userId, venueId);
        return jdbc.query("""
                SELECT r.public_id::text, r.court_id, c.name, lower(r.period), upper(r.period), r.total_amount, r.status,
                       COALESCE(p.nickname::text, '(탈퇴한 사용자)'), r.created_at
                  FROM reservations r JOIN courts c ON c.id = r.court_id
                  LEFT JOIN user_profiles p ON p.user_id = r.user_id
                 WHERE r.venue_id = ?
                   AND r.period && tstzrange((?::date)::timestamp AT TIME ZONE 'Asia/Seoul',
                                             ((?::date) + 1)::timestamp AT TIME ZONE 'Asia/Seoul', '[)')
                   AND r.status NOT IN ('EXPIRED')
                 ORDER BY lower(r.period), c.name""",
                (rs, i) -> new OperatorReservation(rs.getString(1), rs.getLong(2), rs.getString(3),
                        rs.getObject(4, OffsetDateTime.class), rs.getObject(5, OffsetDateTime.class), rs.getInt(6),
                        rs.getString(7), rs.getString(8), rs.getObject(9, OffsetDateTime.class)),
                venueId, date, date);
    }

    // ------------------------------------------------------------- 직원

    public record Staff(long userId, String nickname, String role) {
    }

    public List<Staff> staff(long userId, long venueId) {
        requireOperator(userId, venueId);
        return jdbc.query("""
                SELECT o.user_id, p.nickname::text, o.role FROM venue_operators o
                  JOIN user_profiles p ON p.user_id = o.user_id WHERE o.venue_id = ? ORDER BY o.role, p.nickname""",
                (rs, i) -> new Staff(rs.getLong(1), rs.getString(2), rs.getString(3)), venueId);
    }

    @Transactional
    public void addStaff(long userId, long venueId, String email) {
        requireOwner(userId, venueId);
        List<Long> ids = jdbc.queryForList("SELECT id FROM users WHERE email = ? AND status = 'ACTIVE'", Long.class,
                email == null ? "" : email.trim());
        if (ids.isEmpty()) throw ApiException.notFound();
        jdbc.update("INSERT INTO venue_operators (venue_id, user_id, role) VALUES (?, ?, 'STAFF') ON CONFLICT DO NOTHING",
                venueId, ids.get(0));
        jdbc.update("UPDATE users SET role = 'VENUE_OPERATOR' WHERE id = ? AND role = 'USER'", ids.get(0));
    }

    public void removeStaff(long userId, long venueId, long staffUserId) {
        requireOwner(userId, venueId);
        jdbc.update("DELETE FROM venue_operators WHERE venue_id = ? AND user_id = ? AND role = 'STAFF'", venueId, staffUserId);
    }

    // ------------------------------------------------------------- 유틸

    private String policyJson(JsonNode policy) {
        if (policy == null || policy.isNull()) return null;
        if (!policy.isArray() || policy.isEmpty() || policy.size() > 10) {
            throw ApiException.badRequest("VALIDATION_FAILED", "취소 정책 형식이 올바르지 않아요");
        }
        List<Map<String, Integer>> clean = new ArrayList<>();
        for (JsonNode rule : policy) {
            int hours = rule.path("hoursBefore").asInt(-1);
            int pct = rule.path("refundPercent").asInt(-1);
            if (hours < 0 || hours > 24 * 30 || pct < 0 || pct > 100) {
                throw ApiException.badRequest("VALIDATION_FAILED", "취소 정책 값이 올바르지 않아요");
            }
            clean.add(Map.of("hoursBefore", hours, "refundPercent", pct));
        }
        try {
            return mapper.writeValueAsString(clean);
        } catch (JsonProcessingException e) {
            throw new IllegalStateException(e);
        }
    }

    private static void requireText(String s, int min, int max) {
        if (s == null || s.trim().length() < min || s.trim().length() > max) throw ApiException.badRequest("VALIDATION_FAILED");
    }

    private static String trimOrNull(String s) {
        if (s == null) return null;
        String t = s.trim();
        return t.isEmpty() ? null : t;
    }
}
