package app.fmate.media;

import app.fmate.auth.AuthUser;
import app.fmate.common.ApiException;
import app.fmate.common.RateLimiter;
import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotEmpty;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Positive;
import jakarta.validation.constraints.Size;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.time.Duration;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;

/**
 * 이미지·서류 업로드용 presigned URL 발급. 앱은 받은 URL 로 PUT 하고, 이후 objectKey 를 각 API 에 넘긴다.
 * 서버는 objectKey 를 쓸 때 소유자 접두어와 실제 존재·크기를 다시 확인한다 (MediaKeys).
 */
@RestController
@RequestMapping("/api/v1/media")
public class MediaController {

    public static final long MAX_IMAGE_BYTES = 10L * 1024 * 1024;
    private static final Set<String> IMAGE_TYPES = Set.of("image/jpeg", "image/png", "image/webp", "image/heic");
    private static final Set<String> DOC_TYPES = Set.of("application/pdf", "image/jpeg", "image/png");
    private static final Map<String, String> EXT = Map.of(
            "image/jpeg", "jpg", "image/png", "png", "image/webp", "webp", "image/heic", "heic", "application/pdf", "pdf");

    private final StorageService storage;
    private final RateLimiter limiter;

    public MediaController(StorageService storage, RateLimiter limiter) {
        this.storage = storage;
        this.limiter = limiter;
    }

    public enum Purpose { POST_IMAGE, AVATAR, VENUE_PHOTO, VENUE_DOCUMENT }

    public record FileSpec(@NotBlank String contentType, @Positive long sizeBytes) {
    }

    public record UploadUrlRequest(@NotNull Purpose purpose, @NotEmpty @Size(max = 10) List<@Valid FileSpec> files) {
    }

    public record UploadTarget(String objectKey, String uploadUrl, String method, Map<String, String> headers,
                               String publicUrl) {
    }

    @PostMapping("/upload-urls")
    public List<UploadTarget> uploadUrls(@AuthenticationPrincipal AuthUser me, @Valid @RequestBody UploadUrlRequest r) {
        storage.ensureConfigured();
        limiter.check("upload-urls", Long.toString(me.id()), 60, Duration.ofHours(1));
        if (r.purpose() == Purpose.AVATAR && r.files().size() != 1) throw ApiException.badRequest("VALIDATION_FAILED");

        List<UploadTarget> out = new ArrayList<>();
        for (FileSpec f : r.files()) {
            boolean doc = r.purpose() == Purpose.VENUE_DOCUMENT;
            Set<String> allowed = doc ? DOC_TYPES : IMAGE_TYPES;
            if (!allowed.contains(f.contentType())) throw ApiException.badRequest("UNSUPPORTED_MEDIA");
            if (f.sizeBytes() > MAX_IMAGE_BYTES) throw ApiException.badRequest("FILE_TOO_LARGE");

            String key = MediaKeys.newKey(r.purpose(), me.id(), UUID.randomUUID() + "." + EXT.get(f.contentType()));
            String bucket = doc ? storage.rawBucket() : storage.publicBucket();
            String url = storage.presignPut(bucket, key, f.contentType(), Duration.ofMinutes(15));
            out.add(new UploadTarget(key, url, "PUT", Map.of("Content-Type", f.contentType()),
                    doc ? null : storage.publicUrl(key)));
        }
        return out;
    }
}
