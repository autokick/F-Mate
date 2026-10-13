package app.fmate.config;

import app.fmate.auth.MailService;
import app.fmate.media.StorageService;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.context.event.ApplicationReadyEvent;
import org.springframework.context.event.EventListener;
import org.springframework.stereotype.Component;

/**
 * 서버 시작 시 외부 서비스 설정 상태를 한눈에 출력하고, 운영 모드에서 위험한 설정이면 시작을 막는다.
 */
@Component
public class StartupReport {

    private static final Logger log = LoggerFactory.getLogger(StartupReport.class);

    private final FmateProperties props;
    private final StorageService storage;
    private final MailService mail;

    public StartupReport(FmateProperties props, StorageService storage, MailService mail) {
        this.props = props;
        this.storage = storage;
        this.mail = mail;
    }

    @EventListener(ApplicationReadyEvent.class)
    public void report() {
        if (!props.devMode()) {
            if (!props.publicBaseUrl().startsWith("https://")) {
                throw new IllegalStateException("운영 모드에서는 PUBLIC_BASE_URL 이 https:// 로 시작해야 합니다");
            }
            if (props.payment().isLive() && !props.payment().tossSecretKey().startsWith("live_")) {
                throw new IllegalStateException("PAYMENT_MODE=LIVE 인데 라이브 시크릿 키(live_)가 아닙니다");
            }
        }
        if (!props.payment().isLive() && props.payment().tossSecretKey() != null
                && props.payment().tossSecretKey().startsWith("live_")) {
            throw new IllegalStateException("PAYMENT_MODE=TEST 인데 라이브 키가 설정되어 있습니다. 테스트/실결제를 섞지 마세요");
        }
        log.info("""

                ===== F-Mate 외부 서비스 설정 상태 =====
                  모드            : {}
                  결제(토스)      : {}
                  메일 발송       : {}
                  스토리지(S3)    : {}
                  영상 인코더     : {}
                  푸시(FCM)       : {}
                  카카오/구글/애플: {}/{}/{}
                  지도(앱 표시)   : {}
                ========================================""",
                props.devMode() ? "개발" : "운영",
                props.payment().isConfigured() ? (props.payment().isLive() ? "실결제(LIVE)" : "테스트(TEST)") : "미설정 → 결제 준비 중",
                mail.isConfigured() ? "설정됨" : (props.devMode() ? "미설정 → 인증코드를 서버 로그에 출력(개발용)" : "미설정 → 가입 불가"),
                storage.isConfigured() ? "설정됨" : "미설정 → 사진·영상 업로드 불가",
                props.encoder().enabled() ? "켜짐(ffmpeg)" : "꺼짐 → 숏폼 업로드 불가",
                props.push().isConfigured() ? "설정됨" : "미설정 → 앱 내 알림만",
                on(props.social().kakaoEnabled()), on(!props.social().googleClientIdList().isEmpty()),
                on(!props.social().appleAudienceList().isEmpty()),
                on(props.maps().enabled()));
    }

    private static String on(boolean b) {
        return b ? "켜짐" : "꺼짐";
    }
}
