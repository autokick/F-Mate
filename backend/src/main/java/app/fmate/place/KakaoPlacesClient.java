package app.fmate.place;

import app.fmate.common.ApiException;
import app.fmate.config.FmateProperties;
import com.fasterxml.jackson.databind.JsonNode;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.HttpHeaders;
import org.springframework.http.client.SimpleClientHttpRequestFactory;
import org.springframework.stereotype.Component;
import org.springframework.web.client.RestClient;
import org.springframework.web.client.RestClientException;

import java.util.ArrayList;
import java.util.List;
import java.util.Locale;

/**
 * 카카오 로컬 API 키워드 검색으로 실제 풋살장을 찾는다.
 *
 * 카카오 정책: 검색 결과를 DB·캐시에 저장하면 안 되고 실시간 호출로만 써야 한다.
 * 그래서 이 클래스는 결과를 어디에도 저장하지 않고, 요청마다 카카오에 묻고 그대로 돌려준다.
 * REST API 키는 서버에만 두고 앱에는 내려보내지 않는다.
 */
@Component
public class KakaoPlacesClient {

    private static final Logger log = LoggerFactory.getLogger(KakaoPlacesClient.class);

    public record Place(String id, String name, String category, String phone, String roadAddress, String address,
                        double lat, double lng, Integer distanceM, String placeUrl) {
    }

    public record Result(List<Place> items, boolean hasNext) {
    }

    private final FmateProperties.Places cfg;
    private final RestClient http;

    public KakaoPlacesClient(FmateProperties props, RestClient.Builder builder) {
        this.cfg = props.places();
        SimpleClientHttpRequestFactory rf = new SimpleClientHttpRequestFactory();
        rf.setConnectTimeout(3_000);
        rf.setReadTimeout(5_000);
        this.http = builder.requestFactory(rf).baseUrl("https://dapi.kakao.com").build();
    }

    public boolean isConfigured() {
        return cfg != null && cfg.isConfigured();
    }

    /**
     * @param lat,lng  기준 위치 (둘 다 있으면 거리순). 없으면 검색어만으로 찾는다.
     * @param area     지역 검색어 (예: "강남"). 위치가 없을 때 쓴다.
     * @param radiusM  반경 (미터, 최대 20000)
     * @param page     1~3 (카카오는 한 검색어당 최대 45건)
     */
    public Result searchFutsal(Double lat, Double lng, String area, int radiusM, int page) {
        if (!isConfigured()) throw ApiException.unavailable("PLACES_NOT_CONFIGURED");
        boolean hasPoint = lat != null && lng != null;
        String query = (area == null || area.isBlank() ? "" : area.trim() + " ") + "풋살장";
        JsonNode body;
        try {
            body = http.get()
                    .uri(u -> {
                        var b = u.path("/v2/local/search/keyword.json")
                                .queryParam("query", query)
                                .queryParam("size", 15)
                                .queryParam("page", page);
                        if (hasPoint) {
                            b = b.queryParam("x", lng).queryParam("y", lat)
                                    .queryParam("radius", radiusM).queryParam("sort", "distance");
                        }
                        return b.build();
                    })
                    .header(HttpHeaders.AUTHORIZATION, "KakaoAK " + cfg.kakaoRestApiKey())
                    .retrieve()
                    .body(JsonNode.class);
        } catch (RestClientException e) {
            // 키가 틀렸거나(401), 호출 한도 초과(429), 네트워크 문제 — 키 값은 로그에 남기지 않는다
            log.warn("kakao local search failed: {}", e.getClass().getSimpleName());
            throw ApiException.unavailable("PLACES_UNAVAILABLE");
        }
        if (body == null) throw ApiException.unavailable("PLACES_UNAVAILABLE");

        List<Place> items = new ArrayList<>();
        for (JsonNode d : body.path("documents")) {
            String category = d.path("category_name").asText("");
            String name = d.path("place_name").asText("");
            // "풋살장" 검색에는 용품점·학원 등도 섞여 나와서, 풋살 구장으로 보이는 것만 남긴다
            if (!looksLikeFutsalCourt(name, category)) continue;
            String dist = d.path("distance").asText("");
            items.add(new Place(
                    d.path("id").asText(),
                    name,
                    category,
                    blankToNull(d.path("phone").asText("")),
                    blankToNull(d.path("road_address_name").asText("")),
                    blankToNull(d.path("address_name").asText("")),
                    d.path("y").asDouble(),
                    d.path("x").asDouble(),
                    dist.isBlank() ? null : Integer.valueOf(dist),
                    blankToNull(d.path("place_url").asText(""))));
        }
        boolean isEnd = body.path("meta").path("is_end").asBoolean(true);
        return new Result(items, !isEnd && page < 3);
    }

    static boolean looksLikeFutsalCourt(String name, String category) {
        String n = name.toLowerCase(Locale.ROOT);
        String c = category.toLowerCase(Locale.ROOT);
        if (c.contains("풋살") || c.contains("축구장") || c.contains("운동장") || c.contains("체육시설")) return true;
        return (n.contains("풋살") || n.contains("futsal")) && !c.contains("용품") && !c.contains("쇼핑");
    }

    private static String blankToNull(String s) {
        return s == null || s.isBlank() ? null : s;
    }
}
