package app.fmate.config;

import org.springframework.boot.context.properties.ConfigurationProperties;

import java.time.Duration;
import java.util.Arrays;
import java.util.List;

/**
 * application.yml 의 fmate.* 설정. 외부 서비스 키가 비어 있으면 각 isConfigured() 가 false 를 반환하고
 * 해당 기능은 "미설정" 상태로 동작한다 (가짜 성공 응답을 만들지 않는다).
 */
@ConfigurationProperties(prefix = "fmate")
public record FmateProperties(
        boolean devMode,
        boolean rateLimitEnabled,
        String publicBaseUrl,
        String corsAllowedOrigins,
        Jwt jwt,
        Mail mail,
        Payment payment,
        Storage storage,
        Push push,
        Social social,
        Maps maps,
        Encoder encoder,
        Places places
) {

    public record Jwt(String secret, String issuer, Duration accessTtl, Duration refreshTtl) {
    }

    public record Mail(String from) {
    }

    public record Payment(String mode, String tossClientKey, String tossSecretKey, String tossBaseUrl, int holdMinutes) {
        public boolean isConfigured() {
            return notBlank(tossClientKey) && notBlank(tossSecretKey);
        }

        public boolean isLive() {
            return "LIVE".equalsIgnoreCase(mode);
        }
    }

    /**
     * presignEndpoint: 앱(휴대폰)이 업로드할 때 접속하는 스토리지 주소가 서버가 접속하는 주소와 다를 때만 지정.
     * 예) 로컬 Docker: 서버는 http://storage:9000, 에뮬레이터는 http://10.0.2.2:9000
     */
    public record Storage(String endpoint, String presignEndpoint, String region, String accessKey, String secretKey,
                          String bucketRaw, String bucketPublic, String publicBaseUrl, boolean pathStyle) {
        public boolean isConfigured() {
            return notBlank(accessKey) && notBlank(secretKey) && notBlank(bucketRaw)
                    && notBlank(bucketPublic) && notBlank(publicBaseUrl);
        }
    }

    /**
     * 실제 풋살장 검색 (카카오 로컬 API). REST API 키는 서버에만 둔다.
     * 카카오 정책상 검색 결과는 저장하지 않고 요청마다 실시간으로 조회해 그대로 전달한다.
     */
    public record Places(String kakaoRestApiKey) {
        public boolean isConfigured() {
            return notBlank(kakaoRestApiKey);
        }
    }

    public record Push(String fcmCredentialsPath) {
        public boolean isConfigured() {
            return notBlank(fcmCredentialsPath);
        }
    }

    public record Social(String kakaoAppId, String googleClientIds, String appleAudiences) {
        public boolean kakaoEnabled() {
            return notBlank(kakaoAppId);
        }

        public List<String> googleClientIdList() {
            return splitCsv(googleClientIds);
        }

        public List<String> appleAudienceList() {
            return splitCsv(appleAudiences);
        }
    }

    public record Maps(boolean enabled) {
    }

    public record Encoder(boolean enabled, String ffmpegPath, String ffprobePath) {
    }

    public List<String> corsOriginList() {
        return splitCsv(corsAllowedOrigins);
    }

    static boolean notBlank(String s) {
        return s != null && !s.isBlank();
    }

    static List<String> splitCsv(String s) {
        if (s == null || s.isBlank()) return List.of();
        return Arrays.stream(s.split(",")).map(String::trim).filter(x -> !x.isEmpty()).toList();
    }
}
