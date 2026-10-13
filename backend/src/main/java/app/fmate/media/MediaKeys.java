package app.fmate.media;

import app.fmate.common.ApiException;
import org.springframework.stereotype.Component;

import java.util.Collection;

/** 오브젝트 키 규칙과 소유·존재 검증 */
@Component
public class MediaKeys {

    private final StorageService storage;

    public MediaKeys(StorageService storage) {
        this.storage = storage;
    }

    static String prefix(MediaController.Purpose purpose, long userId) {
        return switch (purpose) {
            case POST_IMAGE -> "images/" + userId + "/";
            case AVATAR -> "avatars/" + userId + "/";
            case VENUE_PHOTO -> "venues/photos/" + userId + "/";
            case VENUE_DOCUMENT -> "venues/docs/" + userId + "/";
        };
    }

    static String newKey(MediaController.Purpose purpose, long userId, String fileName) {
        return prefix(purpose, userId) + fileName;
    }

    /** 본인이 발급받은 키이고 실제로 업로드되어 있는지 확인 */
    public void requireOwnedUpload(MediaController.Purpose purpose, long userId, String key) {
        storage.ensureConfigured();
        if (key == null || key.contains("..") || !key.startsWith(prefix(purpose, userId))) {
            throw ApiException.badRequest("UPLOAD_NOT_FOUND");
        }
        String bucket = purpose == MediaController.Purpose.VENUE_DOCUMENT ? storage.rawBucket() : storage.publicBucket();
        long size = storage.size(bucket, key).orElseThrow(() -> ApiException.badRequest("UPLOAD_NOT_FOUND"));
        if (size > MediaController.MAX_IMAGE_BYTES) {
            storage.delete(bucket, key);
            throw ApiException.badRequest("FILE_TOO_LARGE");
        }
    }

    public void requireOwnedUploads(MediaController.Purpose purpose, long userId, Collection<String> keys) {
        if (keys == null) return;
        for (String k : keys) requireOwnedUpload(purpose, userId, k);
    }
}
