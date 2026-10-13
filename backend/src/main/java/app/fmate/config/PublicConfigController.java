package app.fmate.config;

import app.fmate.auth.MailService;
import app.fmate.auth.SocialVerifier;
import app.fmate.media.StorageService;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;

/**
 * 앱이 시작할 때 조회하는 기능 상태. 외부 서비스 키가 없는 기능은 앱이 "준비 중"으로 표시한다.
 * 비밀값은 포함하지 않는다 (토스 클라이언트 키는 공개용 키).
 */
@RestController
public class PublicConfigController {

    private final FmateProperties props;
    private final StorageService storage;
    private final MailService mail;
    private final SocialVerifier social;

    public PublicConfigController(FmateProperties props, StorageService storage, MailService mail, SocialVerifier social) {
        this.props = props;
        this.storage = storage;
        this.mail = mail;
        this.social = social;
    }

    public record PaymentFeature(boolean enabled, String mode) {
    }

    public record Features(PaymentFeature payment, boolean media, boolean video, boolean push, boolean maps,
                           boolean email, List<String> socialProviders, boolean places) {
    }

    public record ConfigResponse(String serverVersion, boolean devMode, Features features,
                                 String termsVersion, List<String> regions) {
    }

    @GetMapping("/api/v1/config")
    public ConfigResponse config() {
        List<String> providers = List.of("KAKAO", "GOOGLE", "APPLE").stream().filter(social::isEnabled).toList();
        boolean media = storage.isConfigured();
        return new ConfigResponse(
                "1.0.0",
                props.devMode(),
                new Features(
                        new PaymentFeature(props.payment().isConfigured(), props.payment().isLive() ? "LIVE" : "TEST"),
                        media,
                        media && props.encoder().enabled(),
                        props.push().isConfigured(),
                        props.maps().enabled(),
                        mail.isConfigured(),
                        providers,
                        props.places() != null && props.places().isConfigured()),
                "2026-10",
                List.of());
    }
}
