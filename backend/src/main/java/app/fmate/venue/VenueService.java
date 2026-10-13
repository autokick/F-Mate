package app.fmate.venue;

import app.fmate.common.ApiException;
import app.fmate.media.StorageService;
import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.springframework.jdbc.core.namedparam.MapSqlParameterSource;
import org.springframework.jdbc.core.namedparam.NamedParameterJdbcTemplate;
import org.springframework.stereotype.Service;

import java.time.LocalDate;
import java.time.OffsetDateTime;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;
import java.util.Map;

/** 공개 구장 조회 (관리자 검증 VERIFIED 구장만) */
@Service
public class VenueService {

    private final NamedParameterJdbcTemplate db;
    private final StorageService storage;
    private final ObjectMapper mapper;

    public VenueService(NamedParameterJdbcTemplate db, StorageService storage, ObjectMapper mapper) {
        this.db = db;
        this.storage = storage;
        this.mapper = mapper;
    }

    public record SearchQuery(String q, List<String> regionPrefixes, Double lat, Double lng, Double radiusKm,
                              Boolean indoor, String size, List<String> facilities, LocalDate date,
                              Integer fromHour, Integer toHour, Integer minPrice, Integer maxPrice,
                              int page, int pageSize) {
    }

    public record VenueCard(long id, String name, String roadAddress, String regionCode, double latitude,
                            double longitude, String thumbnailUrl, Integer minPrice, boolean hasIndoor,
                            boolean hasOutdoor, List<String> sizes, List<String> facilities, Double distanceKm,
                            Integer availableSlots, String dataSource) {
    }

    public record Page<T>(List<T> items, int page, boolean hasNext) {
    }

    public Page<VenueCard> search(SearchQuery s) {
        MapSqlParameterSource p = new MapSqlParameterSource();
        StringBuilder where = new StringBuilder(" WHERE v.verification_status = 'VERIFIED' ");

        if (s.q() != null && !s.q().isBlank()) {
            where.append(" AND (v.name ILIKE :q OR v.road_address ILIKE :q) ");
            p.addValue("q", "%" + escapeLike(s.q().trim()) + "%");
        }
        if (s.regionPrefixes() != null && !s.regionPrefixes().isEmpty()) {
            List<String> ors = new ArrayList<>();
            for (int i = 0; i < s.regionPrefixes().size(); i++) {
                String code = s.regionPrefixes().get(i);
                if (code == null || !code.matches("^[0-9]{2,10}$")) throw ApiException.badRequest("VALIDATION_FAILED");
                ors.add("v.region_code LIKE :r" + i);
                p.addValue("r" + i, code + "%");
            }
            where.append(" AND (").append(String.join(" OR ", ors)).append(") ");
        }
        boolean geo = s.lat() != null && s.lng() != null;
        String distanceExpr = "NULL::float8";
        if (geo) {
            double radius = s.radiusKm() == null ? 10 : Math.min(Math.max(s.radiusKm(), 0.5), 100);
            // 위경도 사각형으로 먼저 거른 뒤 하버사인 거리로 정확히 계산
            double dLat = radius / 111.0;
            double dLng = radius / (111.0 * Math.max(Math.cos(Math.toRadians(s.lat())), 0.1));
            p.addValue("lat", s.lat()).addValue("lng", s.lng()).addValue("radius", radius)
                    .addValue("latMin", s.lat() - dLat).addValue("latMax", s.lat() + dLat)
                    .addValue("lngMin", s.lng() - dLng).addValue("lngMax", s.lng() + dLng);
            distanceExpr = "(6371 * 2 * asin(sqrt(power(sin(radians(v.latitude - :lat) / 2), 2) "
                    + "+ cos(radians(:lat)) * cos(radians(v.latitude)) * power(sin(radians(v.longitude - :lng) / 2), 2))))";
            where.append(" AND v.latitude BETWEEN :latMin AND :latMax AND v.longitude BETWEEN :lngMin AND :lngMax ")
                    .append(" AND ").append(distanceExpr).append(" <= :radius ");
        }
        if (s.indoor() != null) {
            where.append(" AND EXISTS (SELECT 1 FROM courts c WHERE c.venue_id = v.id AND c.is_active AND c.is_indoor = :indoor) ");
            p.addValue("indoor", s.indoor());
        }
        if (s.size() != null && !s.size().isBlank()) {
            where.append(" AND EXISTS (SELECT 1 FROM courts c WHERE c.venue_id = v.id AND c.is_active AND c.size_class = :size) ");
            p.addValue("size", s.size());
        }
        if (s.facilities() != null && !s.facilities().isEmpty()) {
            where.append(" AND (SELECT count(*) FROM venue_facilities vf WHERE vf.venue_id = v.id AND vf.facility_code IN (:facilities)) = :facilityCount ");
            p.addValue("facilities", s.facilities()).addValue("facilityCount", s.facilities().size());
        }

        // 날짜·시간대·가격 조건: 실제 예약 가능한 슬롯이 하나 이상 있는 구장만
        String availability = "NULL::int";
        if (s.date() != null) {
            int from = s.fromHour() == null ? 0 : Math.max(0, Math.min(23, s.fromHour()));
            int to = s.toHour() == null ? 24 : Math.max(1, Math.min(24, s.toHour()));
            p.addValue("date", s.date()).addValue("fromHour", from).addValue("toHour", to)
                    .addValue("minPrice", s.minPrice() == null ? 0 : s.minPrice())
                    .addValue("maxPrice", s.maxPrice() == null ? Integer.MAX_VALUE : s.maxPrice());
            availability = """
                    (SELECT count(*)::int FROM courts c, LATERAL fn_available_slots(c.id, :date) a
                      WHERE c.venue_id = v.id AND c.is_active AND a.available
                        AND extract(hour FROM a.starts_at AT TIME ZONE 'Asia/Seoul') >= :fromHour
                        AND extract(hour FROM a.starts_at AT TIME ZONE 'Asia/Seoul') < :toHour
                        AND a.price BETWEEN :minPrice AND :maxPrice)""";
            where.append(" AND ").append(availability).append(" > 0 ");
        }

        int size = Math.min(Math.max(s.pageSize(), 1), 50);
        int page = Math.max(s.page(), 0);
        p.addValue("limit", size + 1).addValue("offset", page * size);

        String sql = """
                SELECT v.id, v.name, v.road_address, v.region_code, v.latitude, v.longitude, v.data_source,
                       (SELECT object_key FROM venue_photos ph WHERE ph.venue_id = v.id ORDER BY sort_order, id LIMIT 1) AS thumb,
                       (SELECT min(t.price) FROM time_slots t JOIN courts c ON c.id = t.court_id
                         WHERE c.venue_id = v.id AND c.is_active AND t.status = 'OPEN'
                           AND lower(t.period) > now() AND lower(t.period) < now() + interval '14 days') AS min_price,
                       EXISTS (SELECT 1 FROM courts c WHERE c.venue_id = v.id AND c.is_active AND c.is_indoor) AS has_indoor,
                       EXISTS (SELECT 1 FROM courts c WHERE c.venue_id = v.id AND c.is_active AND NOT c.is_indoor) AS has_outdoor,
                       (SELECT string_agg(DISTINCT c.size_class, ',') FROM courts c WHERE c.venue_id = v.id AND c.is_active) AS sizes,
                       (SELECT string_agg(vf.facility_code, ',' ORDER BY vf.facility_code) FROM venue_facilities vf WHERE vf.venue_id = v.id) AS facilities,
                       %s AS distance_km,
                       %s AS available_slots
                  FROM futsal_venues v
                """.formatted(distanceExpr, availability)
                + where
                + (geo ? " ORDER BY distance_km, v.id " : " ORDER BY v.name, v.id ")
                + " LIMIT :limit OFFSET :offset";

        List<VenueCard> rows = db.query(sql, p, (rs, i) -> new VenueCard(
                rs.getLong("id"), rs.getString("name"), rs.getString("road_address"), rs.getString("region_code"),
                rs.getDouble("latitude"), rs.getDouble("longitude"), storage.publicUrl(rs.getString("thumb")),
                (Integer) rs.getObject("min_price"), rs.getBoolean("has_indoor"), rs.getBoolean("has_outdoor"),
                csv(rs.getString("sizes")), csv(rs.getString("facilities")),
                rs.getObject("distance_km") == null ? null : Math.round(rs.getDouble("distance_km") * 10) / 10.0,
                (Integer) rs.getObject("available_slots"), rs.getString("data_source")));
        boolean hasNext = rows.size() > size;
        return new Page<>(hasNext ? rows.subList(0, size) : rows, page, hasNext);
    }

    public record Court(long id, String name, boolean isIndoor, String surface, String sizeClass,
                        Double widthM, Double lengthM, boolean isActive) {
    }

    public record Facility(String code, String label, String note) {
    }

    public record Photo(long id, String url, String objectKey) {
    }

    public record VenueDetail(long id, String name, String description, String roadAddress, String detailAddress,
                              String regionCode, double latitude, double longitude, String phone, String rules,
                              JsonNode cancelPolicy, String verificationStatus, String rejectionReason,
                              List<Photo> photos, List<Court> courts, List<Facility> facilities,
                              /** OPERATOR(입점) / PARTNER_API(공공데이터 등 외부 자료) / ADMIN */
                              String dataSource) {
    }

    /** 공개 상세: VERIFIED 만. 운영자 화면은 includeUnverified=true */
    public VenueDetail detail(long venueId, boolean includeUnverified) {
        MapSqlParameterSource p = new MapSqlParameterSource("id", venueId);
        List<Map<String, Object>> rows = db.queryForList("""
                SELECT id, name, description, road_address, detail_address, region_code, latitude, longitude, phone,
                       rules, cancel_policy::text AS cancel_policy, verification_status, rejection_reason, data_source
                  FROM futsal_venues WHERE id = :id""", p);
        if (rows.isEmpty()) throw ApiException.notFound();
        Map<String, Object> v = rows.get(0);
        if (!includeUnverified && !"VERIFIED".equals(v.get("verification_status"))) throw ApiException.notFound();

        List<Photo> photos = db.query(
                "SELECT id, object_key FROM venue_photos WHERE venue_id = :id ORDER BY sort_order, id", p,
                (rs, i) -> new Photo(rs.getLong(1), storage.publicUrl(rs.getString(2)), rs.getString(2)));
        List<Court> courts = db.query("""
                SELECT id, name, is_indoor, surface, size_class, width_m, length_m, is_active
                  FROM courts WHERE venue_id = :id %s ORDER BY name, id""".formatted(includeUnverified ? "" : "AND is_active"), p,
                (rs, i) -> new Court(rs.getLong(1), rs.getString(2), rs.getBoolean(3), rs.getString(4), rs.getString(5),
                        rs.getObject(6) == null ? null : rs.getDouble(6), rs.getObject(7) == null ? null : rs.getDouble(7),
                        rs.getBoolean(8)));
        List<Facility> facilities = db.query("""
                SELECT f.code, f.label_ko, vf.note FROM venue_facilities vf JOIN facilities f ON f.code = vf.facility_code
                 WHERE vf.venue_id = :id ORDER BY f.code""", p,
                (rs, i) -> new Facility(rs.getString(1), rs.getString(2), rs.getString(3)));

        return new VenueDetail(venueId, (String) v.get("name"), (String) v.get("description"),
                (String) v.get("road_address"), (String) v.get("detail_address"), (String) v.get("region_code"),
                ((Number) v.get("latitude")).doubleValue(), ((Number) v.get("longitude")).doubleValue(),
                (String) v.get("phone"), (String) v.get("rules"), parse((String) v.get("cancel_policy")),
                (String) v.get("verification_status"), (String) v.get("rejection_reason"),
                photos, courts, facilities, (String) v.get("data_source"));
    }

    public record Slot(long slotId, OffsetDateTime startsAt, OffsetDateTime endsAt, int price, boolean available) {
    }

    public record CourtAvailability(long courtId, String courtName, boolean isIndoor, String sizeClass, List<Slot> slots) {
    }

    public List<CourtAvailability> availability(long venueId, LocalDate date) {
        LocalDate today = LocalDate.now();
        if (date.isBefore(today) || date.isAfter(today.plusDays(60))) throw ApiException.badRequest("VALIDATION_FAILED");
        VenueDetail v = detail(venueId, false);
        List<CourtAvailability> out = new ArrayList<>();
        for (Court c : v.courts()) {
            List<Slot> slots = db.query(
                    "SELECT slot_id, starts_at, ends_at, price, available FROM fn_available_slots(:court, :date)",
                    new MapSqlParameterSource("court", c.id()).addValue("date", date),
                    (rs, i) -> new Slot(rs.getLong(1), rs.getObject(2, OffsetDateTime.class),
                            rs.getObject(3, OffsetDateTime.class), rs.getInt(4), rs.getBoolean(5)));
            out.add(new CourtAvailability(c.id(), c.name(), c.isIndoor(), c.sizeClass(), slots));
        }
        return out;
    }

    public List<Facility> facilities() {
        return db.query("SELECT code, label_ko FROM facilities ORDER BY code", new MapSqlParameterSource(),
                (rs, i) -> new Facility(rs.getString(1), rs.getString(2), null));
    }

    private JsonNode parse(String json) {
        try {
            return json == null ? null : mapper.readTree(json);
        } catch (JsonProcessingException e) {
            return null;
        }
    }

    static List<String> csv(String s) {
        if (s == null || s.isBlank()) return List.of();
        return Arrays.asList(s.split(","));
    }

    static String escapeLike(String s) {
        return s.replace("\\", "\\\\").replace("%", "\\%").replace("_", "\\_");
    }
}
