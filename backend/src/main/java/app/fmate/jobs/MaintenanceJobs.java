package app.fmate.jobs;

import app.fmate.venue.OperatorService;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.context.event.ApplicationReadyEvent;
import org.springframework.context.event.EventListener;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;
import org.springframework.transaction.support.TransactionTemplate;

import java.time.LocalDate;
import java.util.List;
import java.util.function.Supplier;

/**
 * 주기 작업. 서버가 여러 대여도 같은 작업이 동시에 돌지 않도록 트랜잭션 advisory lock 으로 감싼다.
 */
@Component
public class MaintenanceJobs {

    private static final Logger log = LoggerFactory.getLogger(MaintenanceJobs.class);

    private final JdbcTemplate jdbc;
    private final TransactionTemplate tx;

    public MaintenanceJobs(JdbcTemplate jdbc, TransactionTemplate tx) {
        this.jdbc = jdbc;
        this.tx = tx;
    }

    /** 결제 대기 선점 만료 (결제 승인 진행 중인 건은 DB 함수가 제외) */
    @Scheduled(fixedDelay = 30_000, initialDelay = 10_000)
    public void expireHolds() {
        locked(9101, () -> jdbc.queryForObject("SELECT fn_expire_holds()", Integer.class));
    }

    /** 이용 종료된 확정 예약 → COMPLETED */
    @Scheduled(fixedDelay = 600_000, initialDelay = 60_000)
    public void completePast() {
        locked(9102, () -> jdbc.queryForObject("SELECT fn_complete_past_reservations()", Integer.class));
    }

    /** 운영시간 템플릿으로 앞으로 30일치 슬롯을 채운다 (매일 새벽 + 서버 시작 시) */
    @Scheduled(cron = "0 5 3 * * *", zone = "Asia/Seoul")
    @EventListener(ApplicationReadyEvent.class)
    public void generateSlots() {
        locked(9103, () -> {
            List<Long> courts = jdbc.queryForList("""
                    SELECT DISTINCT c.id FROM courts c JOIN operating_hours oh ON oh.court_id = c.id
                      JOIN futsal_venues v ON v.id = c.venue_id
                     WHERE c.is_active AND v.verification_status IN ('VERIFIED','PENDING_REVIEW')""", Long.class);
            int total = 0;
            for (Long id : courts) {
                Integer n = jdbc.queryForObject("SELECT generate_time_slots(?, ?, ?)", Integer.class,
                        id, LocalDate.now(), OperatorService.SLOT_HORIZON_DAYS);
                total += n == null ? 0 : n;
            }
            return total;
        });
    }

    @Scheduled(fixedDelay = 600_000, initialDelay = 90_000)
    public void failStaleUploads() {
        locked(9104, () -> jdbc.queryForObject("SELECT fn_fail_stale_uploads()", Integer.class));
    }

    @Scheduled(fixedDelay = 300_000, initialDelay = 45_000)
    public void liftSuspensions() {
        locked(9105, () -> jdbc.queryForObject("SELECT fn_lift_expired_suspensions()", Integer.class));
    }

    @Scheduled(cron = "0 30 4 * * *", zone = "Asia/Seoul")
    public void purgeOldTokens() {
        locked(9106, () -> {
            jdbc.update("DELETE FROM refresh_tokens WHERE expires_at < now() - interval '7 days'");
            jdbc.update("DELETE FROM one_time_tokens WHERE expires_at < now() - interval '1 day'");
            return jdbc.update("DELETE FROM app_error_logs WHERE created_at < now() - interval '90 days'");
        });
    }

    private void locked(int key, Supplier<Integer> work) {
        try {
            Integer n = tx.execute(status -> {
                Boolean got = jdbc.queryForObject("SELECT pg_try_advisory_xact_lock(?)", Boolean.class, (long) key);
                if (!Boolean.TRUE.equals(got)) return null;
                return work.get();
            });
            if (n != null && n > 0) log.info("job {} affected {}", key, n);
        } catch (Exception e) {
            log.warn("job {} failed: {}", key, e.toString());
        }
    }
}
