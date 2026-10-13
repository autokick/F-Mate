package app.fmate.auth;

import app.fmate.common.ApiException;
import app.fmate.config.FmateProperties;
import com.fasterxml.jackson.databind.JsonNode;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.HttpHeaders;
import org.springframework.http.client.SimpleClientHttpRequestFactory;
import org.springframework.security.oauth2.core.DelegatingOAuth2TokenValidator;
import org.springframework.security.oauth2.core.OAuth2Error;
import org.springframework.security.oauth2.core.OAuth2TokenValidator;
import org.springframework.security.oauth2.core.OAuth2TokenValidatorResult;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.security.oauth2.jwt.JwtDecoder;
import org.springframework.security.oauth2.jwt.JwtException;
import org.springframework.security.oauth2.jwt.JwtValidators;
import org.springframework.security.oauth2.jwt.NimbusJwtDecoder;
import org.springframework.stereotype.Service;
import org.springframework.web.client.RestClient;
import org.springframework.web.client.RestClientException;

import java.util.List;
import java.util.Set;
import java.util.concurrent.ConcurrentHashMap;

/**
 * 앱이 공급자 SDK 로 받은 토큰을 서버가 공급자에게 직접 검증한다.
 *  - 카카오: 액세스 토큰 → 토큰 정보 API(app_id 일치 확인) → 사용자 정보 API
 *  - 구글·애플: ID 토큰(JWT) → 공급자 공개키(JWKS)로 서명 검증 + iss/aud/exp 확인
 */
@Service
public class SocialVerifier {

    private static final Logger log = LoggerFactory.getLogger(SocialVerifier.class);

    public record SocialIdentity(String provider, String providerUserId, String email, boolean emailVerified) {
    }

    private final FmateProperties props;
    private final RestClient http;
    private final ConcurrentHashMap<String, JwtDecoder> decoders = new ConcurrentHashMap<>();

    public SocialVerifier(FmateProperties props, RestClient.Builder builder) {
        this.props = props;
        SimpleClientHttpRequestFactory rf = new SimpleClientHttpRequestFactory();
        rf.setConnectTimeout(5000);
        rf.setReadTimeout(5000);
        this.http = builder.requestFactory(rf).build();
    }

    public boolean isEnabled(String provider) {
        return switch (provider) {
            case "KAKAO" -> props.social().kakaoEnabled();
            case "GOOGLE" -> !props.social().googleClientIdList().isEmpty();
            case "APPLE" -> !props.social().appleAudienceList().isEmpty();
            default -> false;
        };
    }

    public SocialIdentity verify(String provider, String token) {
        if (!isEnabled(provider)) throw ApiException.unavailable("SOCIAL_NOT_CONFIGURED");
        if (token == null || token.isBlank()) throw ApiException.unauthorized("SOCIAL_TOKEN_INVALID");
        return switch (provider) {
            case "KAKAO" -> kakao(token);
            case "GOOGLE" -> idToken("GOOGLE", token, "https://www.googleapis.com/oauth2/v3/certs",
                    Set.of("accounts.google.com", "https://accounts.google.com"),
                    props.social().googleClientIdList());
            case "APPLE" -> idToken("APPLE", token, "https://appleid.apple.com/auth/keys",
                    Set.of("https://appleid.apple.com"), props.social().appleAudienceList());
            default -> throw ApiException.badRequest("BAD_REQUEST");
        };
    }

    private SocialIdentity kakao(String accessToken) {
        try {
            JsonNode info = http.get().uri("https://kapi.kakao.com/v1/user/access_token_info")
                    .header(HttpHeaders.AUTHORIZATION, "Bearer " + accessToken)
                    .retrieve().body(JsonNode.class);
            if (info == null || !props.social().kakaoAppId().trim().equals(info.path("app_id").asText())) {
                throw ApiException.unauthorized("SOCIAL_TOKEN_INVALID");
            }
            JsonNode me = http.get().uri("https://kapi.kakao.com/v2/user/me")
                    .header(HttpHeaders.AUTHORIZATION, "Bearer " + accessToken)
                    .retrieve().body(JsonNode.class);
            if (me == null || !me.hasNonNull("id")) throw ApiException.unauthorized("SOCIAL_TOKEN_INVALID");
            JsonNode account = me.path("kakao_account");
            String email = account.path("email").isTextual() ? account.path("email").asText() : null;
            boolean verified = account.path("is_email_verified").asBoolean(false)
                    && account.path("is_email_valid").asBoolean(false);
            return new SocialIdentity("KAKAO", me.get("id").asText(), email, verified);
        } catch (RestClientException e) {
            log.info("kakao token verification failed: {}", e.getClass().getSimpleName());
            throw ApiException.unauthorized("SOCIAL_TOKEN_INVALID");
        }
    }

    private SocialIdentity idToken(String provider, String token, String jwksUri, Set<String> issuers,
                                   List<String> audiences) {
        JwtDecoder decoder = decoders.computeIfAbsent(provider, p -> {
            NimbusJwtDecoder d = NimbusJwtDecoder.withJwkSetUri(jwksUri).build();
            OAuth2TokenValidator<Jwt> iss = jwt -> issuers.contains(jwt.getClaimAsString("iss"))
                    ? OAuth2TokenValidatorResult.success()
                    : OAuth2TokenValidatorResult.failure(new OAuth2Error("invalid_token", "bad issuer", null));
            OAuth2TokenValidator<Jwt> aud = jwt -> jwt.getAudience() != null
                    && jwt.getAudience().stream().anyMatch(audiences::contains)
                    ? OAuth2TokenValidatorResult.success()
                    : OAuth2TokenValidatorResult.failure(new OAuth2Error("invalid_token", "bad audience", null));
            d.setJwtValidator(new DelegatingOAuth2TokenValidator<>(JwtValidators.createDefault(), iss, aud));
            return d;
        });
        try {
            Jwt jwt = decoder.decode(token);
            Object ev = jwt.getClaim("email_verified");
            boolean verified = ev instanceof Boolean b ? b : "true".equals(String.valueOf(ev));
            return new SocialIdentity(provider, jwt.getSubject(), jwt.getClaimAsString("email"), verified);
        } catch (JwtException e) {
            log.info("{} id token rejected: {}", provider, e.getClass().getSimpleName());
            throw ApiException.unauthorized("SOCIAL_TOKEN_INVALID");
        }
    }
}
