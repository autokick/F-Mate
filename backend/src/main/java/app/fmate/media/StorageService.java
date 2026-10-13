package app.fmate.media;

import app.fmate.common.ApiException;
import app.fmate.config.FmateProperties;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;
import software.amazon.awssdk.auth.credentials.AwsBasicCredentials;
import software.amazon.awssdk.auth.credentials.StaticCredentialsProvider;
import software.amazon.awssdk.core.sync.RequestBody;
import software.amazon.awssdk.core.sync.ResponseTransformer;
import software.amazon.awssdk.regions.Region;
import software.amazon.awssdk.services.s3.S3Client;
import software.amazon.awssdk.services.s3.S3Configuration;
import software.amazon.awssdk.services.s3.model.DeleteObjectRequest;
import software.amazon.awssdk.services.s3.model.GetObjectRequest;
import software.amazon.awssdk.services.s3.model.HeadObjectRequest;
import software.amazon.awssdk.services.s3.model.HeadObjectResponse;
import software.amazon.awssdk.services.s3.model.ListObjectsV2Request;
import software.amazon.awssdk.services.s3.model.ListObjectsV2Response;
import software.amazon.awssdk.services.s3.model.PutObjectRequest;
import software.amazon.awssdk.services.s3.model.S3Exception;
import software.amazon.awssdk.services.s3.model.S3Object;
import software.amazon.awssdk.services.s3.presigner.S3Presigner;
import software.amazon.awssdk.services.s3.presigner.model.GetObjectPresignRequest;
import software.amazon.awssdk.services.s3.presigner.model.PutObjectPresignRequest;

import java.net.URI;
import java.nio.file.Path;
import java.time.Duration;
import java.util.Collection;
import java.util.Optional;

/**
 * S3 호환 오브젝트 스토리지.
 *  - raw 버킷(비공개): 영상 원본, 구장 서류
 *  - public 버킷(CDN 공개): 이미지, 프로필 사진, HLS 결과물, 썸네일
 * 파일은 앱이 presigned URL 로 스토리지에 직접 올린다. API 서버는 대용량 파일을 중계하지 않는다.
 */
@Service
public class StorageService {

    private static final Logger log = LoggerFactory.getLogger(StorageService.class);

    private final FmateProperties.Storage cfg;
    private volatile S3Client client;
    private volatile S3Presigner presigner;

    public StorageService(FmateProperties props) {
        this.cfg = props.storage();
    }

    public boolean isConfigured() {
        return cfg.isConfigured();
    }

    public void ensureConfigured() {
        if (!isConfigured()) throw ApiException.unavailable("MEDIA_NOT_CONFIGURED");
    }

    public String rawBucket() {
        return cfg.bucketRaw();
    }

    public String publicBucket() {
        return cfg.bucketPublic();
    }

    /** CDN 공개 URL. 키가 없으면 null */
    public String publicUrl(String key) {
        if (key == null || !isConfigured()) return null;
        String base = cfg.publicBaseUrl().endsWith("/") ? cfg.publicBaseUrl() : cfg.publicBaseUrl() + "/";
        return base + key;
    }

    public String presignPut(String bucket, String key, String contentType, Duration ttl) {
        ensureConfigured();
        PutObjectRequest put = PutObjectRequest.builder().bucket(bucket).key(key).contentType(contentType).build();
        return presigner().presignPutObject(PutObjectPresignRequest.builder()
                .signatureDuration(ttl).putObjectRequest(put).build()).url().toString();
    }

    public String presignGet(String bucket, String key, Duration ttl) {
        ensureConfigured();
        GetObjectRequest get = GetObjectRequest.builder().bucket(bucket).key(key).build();
        return presigner().presignGetObject(GetObjectPresignRequest.builder()
                .signatureDuration(ttl).getObjectRequest(get).build()).url().toString();
    }

    /** 객체 크기(바이트). 없으면 empty */
    public Optional<Long> size(String bucket, String key) {
        ensureConfigured();
        try {
            HeadObjectResponse head = client().headObject(HeadObjectRequest.builder().bucket(bucket).key(key).build());
            return Optional.ofNullable(head.contentLength());
        } catch (S3Exception e) {
            if (e.statusCode() == 404) return Optional.empty();
            throw e;
        }
    }

    public void download(String bucket, String key, Path target) {
        client().getObject(GetObjectRequest.builder().bucket(bucket).key(key).build(), ResponseTransformer.toFile(target));
    }

    public void upload(String bucket, String key, Path file, String contentType, String cacheControl) {
        client().putObject(PutObjectRequest.builder().bucket(bucket).key(key)
                .contentType(contentType).cacheControl(cacheControl).build(), RequestBody.fromFile(file));
    }

    public void delete(String bucket, String key) {
        if (key == null || !isConfigured()) return;
        client().deleteObject(DeleteObjectRequest.builder().bucket(bucket).key(key).build());
    }

    /** prefix 아래 모든 객체 삭제 (HLS 폴더 등) */
    public void deletePrefix(String bucket, String prefix) {
        if (prefix == null || prefix.isBlank() || !isConfigured()) return;
        String token = null;
        do {
            ListObjectsV2Response page = client().listObjectsV2(ListObjectsV2Request.builder()
                    .bucket(bucket).prefix(prefix).continuationToken(token).build());
            for (S3Object o : page.contents()) delete(bucket, o.key());
            token = Boolean.TRUE.equals(page.isTruncated()) ? page.nextContinuationToken() : null;
        } while (token != null);
    }

    public void deletePublicQuietly(Collection<String> keys) {
        if (keys == null || keys.isEmpty() || !isConfigured()) return;
        for (String k : keys) {
            try {
                delete(cfg.bucketPublic(), k);
            } catch (Exception e) {
                log.warn("storage delete failed (will remain orphaned): {}", e.getClass().getSimpleName());
            }
        }
    }

    private S3Client client() {
        ensureConfigured();
        if (client == null) {
            synchronized (this) {
                if (client == null) {
                    var b = S3Client.builder()
                            .region(Region.of(cfg.region()))
                            .credentialsProvider(credentials())
                            .serviceConfiguration(S3Configuration.builder().pathStyleAccessEnabled(cfg.pathStyle()).build());
                    if (cfg.endpoint() != null && !cfg.endpoint().isBlank()) b.endpointOverride(URI.create(cfg.endpoint()));
                    client = b.build();
                }
            }
        }
        return client;
    }

    private S3Presigner presigner() {
        if (presigner == null) {
            synchronized (this) {
                if (presigner == null) {
                    var b = S3Presigner.builder()
                            .region(Region.of(cfg.region()))
                            .credentialsProvider(credentials())
                            .serviceConfiguration(S3Configuration.builder().pathStyleAccessEnabled(cfg.pathStyle()).build());
                    String ep = cfg.presignEndpoint() != null && !cfg.presignEndpoint().isBlank() ? cfg.presignEndpoint() : cfg.endpoint();
                    if (ep != null && !ep.isBlank()) b.endpointOverride(URI.create(ep));
                    presigner = b.build();
                }
            }
        }
        return presigner;
    }

    private StaticCredentialsProvider credentials() {
        return StaticCredentialsProvider.create(AwsBasicCredentials.create(cfg.accessKey(), cfg.secretKey()));
    }
}
