package app.fmate.payment;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Component;

import java.util.Map;

/** 결제 작업 추적 로그 (분쟁 대응). 카드번호·토큰 등 민감정보는 넣지 않는다. */
@Component
public class PaymentAudit {

    private final JdbcTemplate jdbc;
    private final ObjectMapper mapper;

    public PaymentAudit(JdbcTemplate jdbc, ObjectMapper mapper) {
        this.jdbc = jdbc;
        this.mapper = mapper;
    }

    public void log(Long paymentId, Long refundId, String action, String outcome, Integer httpStatus,
                    String providerCode, Map<String, Object> detail) {
        String json;
        try {
            json = detail == null ? null : mapper.writeValueAsString(detail);
        } catch (JsonProcessingException e) {
            json = null;
        }
        jdbc.update("""
                INSERT INTO payment_audit_logs (payment_id, refund_id, action, outcome, http_status, provider_code, detail)
                VALUES (?, ?, ?, ?, ?, ?, ?::jsonb)""",
                paymentId, refundId, action, outcome, httpStatus,
                providerCode == null ? null : providerCode.substring(0, Math.min(80, providerCode.length())), json);
    }
}
