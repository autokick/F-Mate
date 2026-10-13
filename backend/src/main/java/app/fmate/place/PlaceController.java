package app.fmate.place;

import app.fmate.common.ApiException;
import app.fmate.common.RateLimiter;
import jakarta.servlet.http.HttpServletRequest;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.time.Duration;
import java.util.Map;

/**
 * 실제 풋살장 찾기 (카카오 로컬 API 실시간 조회, 저장하지 않음).
 * F-Mate 와 제휴된 구장이 아니므로 예약은 되지 않고 정보만 보여준다.
 */
@RestController
@RequestMapping("/api/v1/places")
public class PlaceController {

    private final KakaoPlacesClient kakao;
    private final RateLimiter limiter;

    public PlaceController(KakaoPlacesClient kakao, RateLimiter limiter) {
        this.kakao = kakao;
        this.limiter = limiter;
    }

    @GetMapping("/futsal-nearby")
    public Map<String, Object> futsalNearby(@RequestParam(required = false) Double lat,
                                            @RequestParam(required = false) Double lng,
                                            @RequestParam(required = false) String area,
                                            @RequestParam(defaultValue = "10000") int radiusM,
                                            @RequestParam(defaultValue = "1") int page,
                                            HttpServletRequest req) {
        // 카카오 호출 한도(일 단위)를 지키기 위해 IP 당 제한
        limiter.check("places", req.getRemoteAddr(), 60, Duration.ofMinutes(1));
        boolean hasPoint = lat != null && lng != null;
        if (hasPoint && (lat < 33 || lat > 39.5 || lng < 124 || lng > 132)) {
            throw ApiException.badRequest("VALIDATION_FAILED", "국내 위치만 검색할 수 있어요");
        }
        if (!hasPoint && (area == null || area.isBlank())) {
            throw ApiException.badRequest("VALIDATION_FAILED", "위치 또는 지역을 알려 주세요");
        }
        if (area != null && area.length() > 30) throw ApiException.badRequest("VALIDATION_FAILED");
        int radius = Math.max(500, Math.min(radiusM, 20_000));
        int p = Math.max(1, Math.min(page, 3));
        KakaoPlacesClient.Result r = kakao.searchFutsal(lat, lng, area, radius, p);
        return Map.of(
                "items", r.items(),
                "page", p,
                "hasNext", r.hasNext(),
                // 앱이 목록 아래에 표시해야 하는 출처
                "attribution", "장소 정보 제공: 카카오");
    }
}
