package app.fmate.config;

import app.fmate.auth.JwtAuthConverter;
import app.fmate.common.ApiException;
import app.fmate.common.ErrorBody;
import app.fmate.common.RequestContextFilter;
import com.fasterxml.jackson.databind.ObjectMapper;
import jakarta.servlet.http.HttpServletResponse;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.http.HttpMethod;
import org.springframework.http.MediaType;
import org.springframework.security.config.Customizer;
import org.springframework.security.config.annotation.method.configuration.EnableMethodSecurity;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.config.http.SessionCreationPolicy;
import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.security.web.AuthenticationEntryPoint;
import org.springframework.security.web.SecurityFilterChain;
import org.springframework.security.web.access.AccessDeniedHandler;
import org.springframework.web.cors.CorsConfiguration;
import org.springframework.web.cors.CorsConfigurationSource;
import org.springframework.web.cors.UrlBasedCorsConfigurationSource;

import java.io.IOException;
import java.util.List;

@Configuration
@EnableMethodSecurity
public class SecurityConfig {

    @Bean
    public PasswordEncoder passwordEncoder() {
        return new BCryptPasswordEncoder(12);
    }

    @Bean
    public SecurityFilterChain api(HttpSecurity http, JwtAuthConverter converter, ObjectMapper mapper)
            throws Exception {
        AuthenticationEntryPoint unauthenticated = (req, res, ex) ->
                write(res, mapper, ApiException.unauthorized("UNAUTHENTICATED"));
        AccessDeniedHandler denied = (req, res, ex) ->
                write(res, mapper, ApiException.forbidden("FORBIDDEN"));

        http
                .csrf(c -> c.disable())   // 쿠키 세션을 쓰지 않는 토큰 기반 API
                .cors(Customizer.withDefaults())
                .sessionManagement(s -> s.sessionCreationPolicy(SessionCreationPolicy.STATELESS))
                .httpBasic(b -> b.disable())
                .formLogin(f -> f.disable())
                .authorizeHttpRequests(a -> a
                        .requestMatchers("/actuator/health", "/actuator/health/**", "/actuator/info").permitAll()
                        .requestMatchers(HttpMethod.POST,
                                "/api/v1/auth/signup", "/api/v1/auth/login", "/api/v1/auth/refresh",
                                "/api/v1/auth/password/reset-request", "/api/v1/auth/password/reset",
                                "/api/v1/auth/social/*").permitAll()
                        .requestMatchers(HttpMethod.GET,
                                "/api/v1/config", "/api/v1/facilities",
                                "/api/v1/venues", "/api/v1/venues/**", "/api/v1/places/**").permitAll()
                        // 결제창 리다이렉트(토스 → 서버)와 웹훅은 토큰 없이 들어온다. 서버가 토스 API 로 재검증.
                        .requestMatchers("/pay/success", "/pay/fail", "/api/v1/webhooks/**").permitAll()
                        // WebSocket 은 연결 후 첫 메시지로 JWT 인증 (ChatSocketHandler)
                        .requestMatchers("/ws/chat").permitAll()
                        .requestMatchers("/api/v1/admin/**").hasAnyRole("ADMIN", "MODERATOR")
                        .anyRequest().authenticated())
                .oauth2ResourceServer(o -> o
                        .jwt(j -> j.jwtAuthenticationConverter(converter))
                        .authenticationEntryPoint(unauthenticated)
                        .accessDeniedHandler(denied))
                .exceptionHandling(e -> e
                        .authenticationEntryPoint(unauthenticated)
                        .accessDeniedHandler(denied))
                .headers(h -> h
                        .contentTypeOptions(Customizer.withDefaults())
                        .frameOptions(f -> f.deny()));
        return http.build();
    }

    @Bean
    public CorsConfigurationSource corsConfigurationSource(FmateProperties props) {
        CorsConfiguration cfg = new CorsConfiguration();
        List<String> origins = props.corsOriginList();
        // 모바일 앱은 CORS 와 무관. 웹 관리자 화면을 따로 두는 경우에만 출처를 지정한다.
        cfg.setAllowedOrigins(origins);
        cfg.setAllowedMethods(List.of("GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"));
        cfg.setAllowedHeaders(List.of("Authorization", "Content-Type", "Idempotency-Key", RequestContextFilter.HEADER));
        cfg.setExposedHeaders(List.of(RequestContextFilter.HEADER));
        cfg.setMaxAge(3600L);
        UrlBasedCorsConfigurationSource source = new UrlBasedCorsConfigurationSource();
        source.registerCorsConfiguration("/**", cfg);
        return source;
    }

    private static void write(HttpServletResponse res, ObjectMapper mapper, ApiException e) throws IOException {
        res.setStatus(e.status().value());
        res.setContentType(MediaType.APPLICATION_JSON_VALUE);
        res.setCharacterEncoding("UTF-8");
        mapper.writeValue(res.getOutputStream(), ErrorBody.of(e, RequestContextFilter.currentRequestId()));
    }
}
