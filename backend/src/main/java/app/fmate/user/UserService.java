package app.fmate.user;

import app.fmate.auth.AuthService;
import app.fmate.common.ApiException;
import app.fmate.media.MediaController;
import app.fmate.media.MediaKeys;
import app.fmate.media.StorageService;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;

@Service
public class UserService {

    private static final Set<String> POSITIONS = Set.of("PIVO", "ALA", "FIXO", "GOLEIRO", "ANY");

    private final JdbcTemplate jdbc;
    private final StorageService storage;
    private final MediaKeys mediaKeys;

    public UserService(JdbcTemplate jdbc, StorageService storage, MediaKeys mediaKeys) {
        this.jdbc = jdbc;
        this.storage = storage;
        this.mediaKeys = mediaKeys;
    }

    public record Counts(long posts, long followers, long following) {
    }

    public record Me(long id, String email, boolean emailVerified, String role, String nickname, String bio,
                     String avatarUrl, String regionCode, String preferredPosition, boolean isPrivate,
                     Counts counts, boolean hasPassword, List<String> socialProviders,
                     Map<String, Boolean> consents, List<Long> operatorVenueIds, boolean needsProfile) {
    }

    public Me me(long userId) {
        Map<String, Object> u = jdbc.queryForMap("""
                SELECT u.id, u.email::text AS email, u.email_verified_at IS NOT NULL AS verified, u.role,
                       u.password_hash IS NOT NULL AS has_password,
                       p.nickname::text AS nickname, p.bio, p.avatar_object_key, p.region_code,
                       p.preferred_position, p.is_private
                  FROM users u JOIN user_profiles p ON p.user_id = u.id WHERE u.id = ?""", userId);
        List<String> providers = jdbc.queryForList(
                "SELECT provider FROM social_accounts WHERE user_id = ? ORDER BY provider", String.class, userId);
        Map<String, Boolean> consents = new LinkedHashMap<>();
        jdbc.query("""
                SELECT DISTINCT ON (consent_type) consent_type, agreed FROM consents
                 WHERE user_id = ? ORDER BY consent_type, created_at DESC""",
                rs -> {
                    consents.put(rs.getString(1), rs.getBoolean(2));
                }, userId);
        List<Long> venues = jdbc.queryForList(
                "SELECT venue_id FROM venue_operators WHERE user_id = ? ORDER BY venue_id", Long.class, userId);
        boolean needsProfile = !(Boolean.TRUE.equals(consents.get("AGE_14")) && Boolean.TRUE.equals(consents.get("TERMS"))
                && Boolean.TRUE.equals(consents.get("PRIVACY")));
        return new Me(userId, (String) u.get("email"), (Boolean) u.get("verified"), (String) u.get("role"),
                (String) u.get("nickname"), (String) u.get("bio"), storage.publicUrl((String) u.get("avatar_object_key")),
                (String) u.get("region_code"), (String) u.get("preferred_position"), (Boolean) u.get("is_private"),
                counts(userId), (Boolean) u.get("has_password"), providers, consents, venues, needsProfile);
    }

    public Counts counts(long userId) {
        return jdbc.queryForObject("""
                SELECT (SELECT count(*) FROM posts WHERE author_id = ? AND status = 'ACTIVE'),
                       (SELECT count(*) FROM follows WHERE followee_id = ? AND status = 'ACCEPTED'),
                       (SELECT count(*) FROM follows WHERE follower_id = ? AND status = 'ACCEPTED')""",
                (rs, i) -> new Counts(rs.getLong(1), rs.getLong(2), rs.getLong(3)), userId, userId, userId);
    }

    public record ProfileUpdate(String nickname, String bio, String regionCode, String preferredPosition,
                                Boolean isPrivate) {
    }

    @Transactional
    public void updateProfile(long userId, ProfileUpdate u) {
        if (u.nickname() != null) {
            String n = u.nickname().trim();
            if (!AuthService.NICKNAME.matcher(n).matches()) {
                throw ApiException.badRequest("VALIDATION_FAILED", "닉네임은 한글·영문·숫자·_ . 2~20자예요");
            }
            jdbc.update("UPDATE user_profiles SET nickname = ? WHERE user_id = ?", n, userId);
        }
        if (u.bio() != null) {
            String b = u.bio().strip();
            if (b.length() > 300) throw ApiException.badRequest("VALIDATION_FAILED");
            jdbc.update("UPDATE user_profiles SET bio = ? WHERE user_id = ?", b.isEmpty() ? null : b, userId);
        }
        if (u.regionCode() != null) {
            String r = u.regionCode().trim();
            if (!r.isEmpty() && !r.matches("^[0-9]{2,10}$")) throw ApiException.badRequest("VALIDATION_FAILED");
            jdbc.update("UPDATE user_profiles SET region_code = ? WHERE user_id = ?", r.isEmpty() ? null : r, userId);
        }
        if (u.preferredPosition() != null) {
            String p = u.preferredPosition().trim();
            if (!p.isEmpty() && !POSITIONS.contains(p)) throw ApiException.badRequest("VALIDATION_FAILED");
            jdbc.update("UPDATE user_profiles SET preferred_position = ? WHERE user_id = ?", p.isEmpty() ? null : p, userId);
        }
        if (u.isPrivate() != null) {
            jdbc.update("UPDATE user_profiles SET is_private = ? WHERE user_id = ?", u.isPrivate(), userId);
            if (!u.isPrivate()) {
                // 공개 전환 시 대기 중인 팔로우 요청은 모두 수락
                jdbc.update("UPDATE follows SET status = 'ACCEPTED' WHERE followee_id = ? AND status = 'PENDING'", userId);
            }
        }
    }

    public void setAvatar(long userId, String objectKey) {
        String old = jdbc.queryForObject("SELECT avatar_object_key FROM user_profiles WHERE user_id = ?", String.class, userId);
        if (objectKey != null) mediaKeys.requireOwnedUpload(MediaController.Purpose.AVATAR, userId, objectKey);
        jdbc.update("UPDATE user_profiles SET avatar_object_key = ? WHERE user_id = ?", objectKey, userId);
        if (old != null && !old.equals(objectKey)) storage.deletePublicQuietly(List.of(old));
    }

    // ---------------------------------------------------------------- 타인 프로필

    public record ProfileView(long id, String nickname, String bio, String avatarUrl, String regionCode,
                              String preferredPosition, boolean isPrivate, Counts counts,
                              String followStatus, boolean followsMe, boolean blockedByMe, boolean canViewPosts) {
    }

    public ProfileView profile(long viewerId, long targetId) {
        Boolean blockedMe = jdbc.queryForObject(
                "SELECT EXISTS (SELECT 1 FROM blocks WHERE blocker_id = ? AND blocked_id = ?)", Boolean.class, targetId, viewerId);
        if (Boolean.TRUE.equals(blockedMe)) throw ApiException.notFound();
        List<Map<String, Object>> rows = jdbc.queryForList("""
                SELECT p.nickname::text AS nickname, p.bio, p.avatar_object_key, p.region_code, p.preferred_position, p.is_private
                  FROM users u JOIN user_profiles p ON p.user_id = u.id WHERE u.id = ? AND u.status = 'ACTIVE'""", targetId);
        if (rows.isEmpty()) throw ApiException.notFound();
        Map<String, Object> p = rows.get(0);
        String followStatus = jdbc.query(
                "SELECT status FROM follows WHERE follower_id = ? AND followee_id = ?",
                rs -> rs.next() ? rs.getString(1) : "NONE", viewerId, targetId);
        Boolean followsMe = jdbc.queryForObject(
                "SELECT EXISTS (SELECT 1 FROM follows WHERE follower_id = ? AND followee_id = ? AND status = 'ACCEPTED')",
                Boolean.class, targetId, viewerId);
        Boolean blockedByMe = jdbc.queryForObject(
                "SELECT EXISTS (SELECT 1 FROM blocks WHERE blocker_id = ? AND blocked_id = ?)", Boolean.class, viewerId, targetId);
        boolean isPrivate = (Boolean) p.get("is_private");
        boolean canView = viewerId == targetId
                || (!Boolean.TRUE.equals(blockedByMe) && (!isPrivate || "ACCEPTED".equals(followStatus)));
        return new ProfileView(targetId, (String) p.get("nickname"), (String) p.get("bio"),
                storage.publicUrl((String) p.get("avatar_object_key")), (String) p.get("region_code"),
                (String) p.get("preferred_position"), isPrivate, counts(targetId),
                "ACCEPTED".equals(followStatus) ? "FOLLOWING" : followStatus,
                Boolean.TRUE.equals(followsMe), Boolean.TRUE.equals(blockedByMe), canView);
    }

    public List<UserSummary> search(long viewerId, String q, int limit) {
        if (q == null || q.trim().length() < 1) return List.of();
        String like = "%" + q.trim().replace("\\", "\\\\").replace("%", "\\%").replace("_", "\\_") + "%";
        List<UserSummary> out = new ArrayList<>();
        jdbc.query("""
                SELECT p.user_id, p.nickname::text, p.avatar_object_key
                  FROM user_profiles p JOIN users u ON u.id = p.user_id
                 WHERE u.status = 'ACTIVE' AND p.nickname::text ILIKE ?
                   AND p.user_id <> ? AND NOT is_blocked_between(?, p.user_id)
                 ORDER BY length(p.nickname::text), p.nickname LIMIT ?""",
                rs -> {
                    out.add(new UserSummary(rs.getLong(1), rs.getString(2), storage.publicUrl(rs.getString(3))));
                }, like, viewerId, viewerId, Math.min(Math.max(limit, 1), 30));
        return out;
    }

    public UserSummary summary(long userId) {
        return jdbc.queryForObject(
                "SELECT user_id, nickname::text, avatar_object_key FROM user_profiles WHERE user_id = ?",
                (rs, i) -> new UserSummary(rs.getLong(1), rs.getString(2), storage.publicUrl(rs.getString(3))), userId);
    }
}
