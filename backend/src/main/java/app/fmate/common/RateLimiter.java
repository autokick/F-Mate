package app.fmate.common;

import app.fmate.config.FmateProperties;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

import java.time.Duration;
import java.util.concurrent.ConcurrentHashMap;

/**
 * 고정 창(fixed window) 요청 제한. 단일 서버 인스턴스 기준.
 * 서버를 여러 대로 늘리면 Redis 기반(Bucket4j 등)으로 교체해야 한다 — docs/05-deploy.md 참고.
 */
@Component
public class RateLimiter {

    private record Window(long startMillis, long windowMillis, int count) {
    }

    private final ConcurrentHashMap<String, Window> windows = new ConcurrentHashMap<>();
    private final boolean enabled;

    public RateLimiter(FmateProperties props) {
        this.enabled = props.rateLimitEnabled();
    }

    /** limit 을 넘으면 429 RATE_LIMITED */
    public void check(String bucket, String key, int limit, Duration window) {
        if (!enabled) return;
        long now = System.currentTimeMillis();
        long size = window.toMillis();
        Window w = windows.compute(bucket + ":" + key, (k, cur) -> {
            if (cur == null || now - cur.startMillis() >= cur.windowMillis()) {
                return new Window(now, size, 1);
            }
            return new Window(cur.startMillis(), cur.windowMillis(), cur.count() + 1);
        });
        if (w.count() > limit) throw ApiException.tooMany();
    }

    @Scheduled(fixedDelay = 300_000)
    void evictExpired() {
        long now = System.currentTimeMillis();
        windows.entrySet().removeIf(e -> now - e.getValue().startMillis() >= e.getValue().windowMillis());
    }
}
