package app.fmate.auth;

import app.fmate.common.ApiException;
import app.fmate.config.FmateProperties;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.core.env.Environment;
import org.springframework.mail.SimpleMailMessage;
import org.springframework.mail.javamail.JavaMailSender;
import org.springframework.stereotype.Service;

/**
 * 메일 발송. MAIL_HOST 가 비어 있으면:
 *  - 개발 모드: 메일 대신 서버 로그에 내용을 출력 ([DEV-MAIL] 표시)
 *  - 운영 모드: EMAIL_NOT_CONFIGURED 오류 (메일이 나간 척하지 않는다)
 */
@Service
public class MailService {

    private static final Logger log = LoggerFactory.getLogger(MailService.class);

    private final ObjectProvider<JavaMailSender> sender;
    private final FmateProperties props;
    private final Environment env;

    public MailService(ObjectProvider<JavaMailSender> sender, FmateProperties props, Environment env) {
        this.sender = sender;
        this.props = props;
        this.env = env;
    }

    public boolean isConfigured() {
        String host = env.getProperty("spring.mail.host");
        String from = props.mail().from();
        return host != null && !host.isBlank() && from != null && !from.isBlank()
                && sender.getIfAvailable() != null;
    }

    /** 발송 가능 여부를 미리 확인 (가입 전에 호출) */
    public void ensureAvailable() {
        if (!isConfigured() && !props.devMode()) throw ApiException.unavailable("EMAIL_NOT_CONFIGURED");
    }

    public void send(String to, String subject, String body) {
        if (!isConfigured()) {
            if (props.devMode()) {
                log.warn("[DEV-MAIL] to={} subject={}\n{}", mask(to), subject, body);
                return;
            }
            throw ApiException.unavailable("EMAIL_NOT_CONFIGURED");
        }
        SimpleMailMessage m = new SimpleMailMessage();
        m.setFrom(props.mail().from());
        m.setTo(to);
        m.setSubject(subject);
        m.setText(body);
        sender.getObject().send(m);
    }

    static String mask(String email) {
        if (email == null) return "-";
        int at = email.indexOf('@');
        if (at <= 1) return "***" + (at >= 0 ? email.substring(at) : "");
        return email.charAt(0) + "***" + email.substring(at);
    }
}
