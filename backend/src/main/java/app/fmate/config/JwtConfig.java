package app.fmate.config;

import com.nimbusds.jose.jwk.source.ImmutableSecret;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.security.oauth2.jose.jws.MacAlgorithm;
import org.springframework.security.oauth2.jwt.JwtDecoder;
import org.springframework.security.oauth2.jwt.JwtEncoder;
import org.springframework.security.oauth2.jwt.NimbusJwtDecoder;
import org.springframework.security.oauth2.jwt.NimbusJwtEncoder;

import javax.crypto.SecretKey;
import javax.crypto.spec.SecretKeySpec;
import java.security.SecureRandom;
import java.util.Base64;

/**
 * 액세스 토큰 서명 키 (HS256).
 * 운영: JWT_SECRET 필수(Base64, 32바이트 이상). 개발: 비어 있으면 임시 키 생성(재시작 시 모든 로그인 만료).
 */
@Configuration
public class JwtConfig {

    private static final Logger log = LoggerFactory.getLogger(JwtConfig.class);

    @Bean
    public SecretKey jwtSecretKey(FmateProperties props) {
        String secret = props.jwt().secret();
        byte[] bytes;
        if (secret == null || secret.isBlank()) {
            if (!props.devMode()) {
                throw new IllegalStateException("JWT_SECRET 환경변수가 필요합니다 (운영 모드)");
            }
            bytes = new byte[32];
            new SecureRandom().nextBytes(bytes);
            log.warn("JWT_SECRET 미설정: 개발용 임시 서명 키를 생성했습니다. 서버 재시작 시 로그인이 모두 만료됩니다.");
        } else {
            bytes = Base64.getDecoder().decode(secret.trim());
            if (bytes.length < 32) {
                throw new IllegalStateException("JWT_SECRET 은 Base64 로 인코딩된 32바이트 이상이어야 합니다");
            }
        }
        return new SecretKeySpec(bytes, "HmacSHA256");
    }

    @Bean
    public JwtEncoder jwtEncoder(SecretKey jwtSecretKey) {
        return new NimbusJwtEncoder(new ImmutableSecret<>(jwtSecretKey));
    }

    @Bean
    public JwtDecoder jwtDecoder(SecretKey jwtSecretKey) {
        return NimbusJwtDecoder.withSecretKey(jwtSecretKey).macAlgorithm(MacAlgorithm.HS256).build();
    }
}
