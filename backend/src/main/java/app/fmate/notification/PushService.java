package app.fmate.notification;

import app.fmate.config.FmateProperties;
import com.google.auth.oauth2.GoogleCredentials;
import com.google.firebase.FirebaseApp;
import com.google.firebase.FirebaseOptions;
import com.google.firebase.messaging.AndroidConfig;
import com.google.firebase.messaging.FirebaseMessaging;
import com.google.firebase.messaging.FirebaseMessagingException;
import com.google.firebase.messaging.Message;
import com.google.firebase.messaging.MessagingErrorCode;
import com.google.firebase.messaging.Notification;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;

import java.io.FileInputStream;
import java.io.IOException;
import java.io.InputStream;
import java.util.Map;

/** FCM 발송. FCM_CREDENTIALS_PATH 가 없으면 발송하지 않는다(알림 목록은 앱에서 계속 조회 가능). */
@Service
public class PushService {

    private static final Logger log = LoggerFactory.getLogger(PushService.class);

    public enum Result { SENT, INVALID_TOKEN, FAILED }

    private final FmateProperties.Push cfg;
    private volatile FirebaseMessaging messaging;
    private volatile boolean initFailed;

    public PushService(FmateProperties props) {
        this.cfg = props.push();
    }

    public boolean isAvailable() {
        return cfg.isConfigured() && !initFailed && messaging() != null;
    }

    public Result send(String token, String title, String body, Map<String, String> data) {
        FirebaseMessaging m = messaging();
        if (m == null) return Result.FAILED;
        Message msg = Message.builder()
                .setToken(token)
                .setNotification(Notification.builder().setTitle(title).setBody(body).build())
                .putAllData(data)
                .setAndroidConfig(AndroidConfig.builder().setPriority(AndroidConfig.Priority.HIGH).build())
                .build();
        try {
            m.send(msg);
            return Result.SENT;
        } catch (FirebaseMessagingException e) {
            MessagingErrorCode code = e.getMessagingErrorCode();
            if (code == MessagingErrorCode.UNREGISTERED || code == MessagingErrorCode.INVALID_ARGUMENT) {
                return Result.INVALID_TOKEN;
            }
            log.warn("fcm send failed: {}", code);
            return Result.FAILED;
        }
    }

    private FirebaseMessaging messaging() {
        if (!cfg.isConfigured() || initFailed) return null;
        if (messaging == null) {
            synchronized (this) {
                if (messaging == null && !initFailed) {
                    try (InputStream in = new FileInputStream(cfg.fcmCredentialsPath())) {
                        FirebaseOptions options = FirebaseOptions.builder()
                                .setCredentials(GoogleCredentials.fromStream(in)).build();
                        FirebaseApp app = FirebaseApp.getApps().stream()
                                .filter(a -> a.getName().equals("fmate")).findFirst()
                                .orElseGet(() -> FirebaseApp.initializeApp(options, "fmate"));
                        messaging = FirebaseMessaging.getInstance(app);
                    } catch (IOException | RuntimeException e) {
                        initFailed = true;
                        log.error("FCM 초기화 실패 — 푸시 발송을 끕니다: {}", e.getClass().getSimpleName());
                    }
                }
            }
        }
        return messaging;
    }
}
