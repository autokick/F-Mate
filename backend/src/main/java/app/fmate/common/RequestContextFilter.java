package app.fmate.common;

import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.slf4j.MDC;
import org.springframework.core.Ordered;
import org.springframework.core.annotation.Order;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;

import java.io.IOException;
import java.util.UUID;
import java.util.regex.Pattern;

/**
 * 요청마다 requestId 를 부여하고, 요청 요약(메서드·경로·상태·소요시간)만 기록한다.
 * 본문, 쿼리스트링, 헤더(토큰)는 로그에 남기지 않는다 — 개인정보·비밀값 노출 방지.
 */
@Component("fmateRequestContextFilter") // Spring Boot 기본 빈 이름(requestContextFilter)과 겹치지 않게
@Order(Ordered.HIGHEST_PRECEDENCE)
public class RequestContextFilter extends OncePerRequestFilter {

    public static final String HEADER = "X-Request-Id";
    public static final String MDC_KEY = "requestId";
    private static final Logger log = LoggerFactory.getLogger("access");
    private static final Pattern SAFE_ID = Pattern.compile("^[A-Za-z0-9-]{8,64}$");

    @Override
    protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response, FilterChain chain)
            throws ServletException, IOException {
        String incoming = request.getHeader(HEADER);
        String requestId = incoming != null && SAFE_ID.matcher(incoming).matches()
                ? incoming : UUID.randomUUID().toString();
        long start = System.nanoTime();
        MDC.put(MDC_KEY, requestId);
        response.setHeader(HEADER, requestId);
        try {
            chain.doFilter(request, response);
        } finally {
            long ms = (System.nanoTime() - start) / 1_000_000;
            String path = request.getRequestURI();
            if (!path.startsWith("/actuator")) {
                log.info("{} {} -> {} ({}ms)", request.getMethod(), path, response.getStatus(), ms);
            }
            MDC.remove(MDC_KEY);
        }
    }

    public static String currentRequestId() {
        return MDC.get(MDC_KEY);
    }
}
