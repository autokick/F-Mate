package app.fmate.common;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Component;

/** 처리되지 않은 서버 오류를 관리자 조회용 테이블에 기록한다 (예외 클래스와 잘린 메시지만). */
@Component
public class ErrorLogWriter {

    private static final Logger log = LoggerFactory.getLogger(ErrorLogWriter.class);
    private final JdbcTemplate jdbc;

    public ErrorLogWriter(JdbcTemplate jdbc) {
        this.jdbc = jdbc;
    }

    public void record(String method, String path, Long userId, Throwable e) {
        try {
            String msg = e.getMessage() == null ? null : e.getMessage();
            if (msg != null && msg.length() > 1000) msg = msg.substring(0, 1000);
            jdbc.update("""
                    INSERT INTO app_error_logs (request_id, method, path, user_id, error_class, message)
                    VALUES (?, ?, ?, ?, ?, ?)""",
                    RequestContextFilter.currentRequestId(), method,
                    path == null ? null : path.substring(0, Math.min(path.length(), 300)),
                    userId, e.getClass().getName(), msg);
        } catch (Exception writeFailure) {
            log.warn("error log write failed: {}", writeFailure.getClass().getSimpleName());
        }
    }
}
