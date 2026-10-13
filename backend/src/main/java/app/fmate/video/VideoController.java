package app.fmate.video;

import app.fmate.auth.AuthUser;
import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Positive;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/v1/videos")
public class VideoController {

    private final VideoService videos;

    public VideoController(VideoService videos) {
        this.videos = videos;
    }

    public record UploadRequest(@NotBlank String contentType, @Positive long sizeBytes) {
    }

    @PostMapping("/uploads")
    public ResponseEntity<VideoService.UploadTicket> upload(@AuthenticationPrincipal AuthUser me,
                                                            @Valid @RequestBody UploadRequest r) {
        return ResponseEntity.status(HttpStatus.CREATED)
                .body(videos.createUpload(me.id(), me.emailVerified(), r.contentType(), r.sizeBytes()));
    }

    @PostMapping("/{id}/complete")
    public VideoService.VideoStatus complete(@AuthenticationPrincipal AuthUser me, @PathVariable long id) {
        return videos.complete(me.id(), id);
    }

    @PostMapping("/{id}/abort")
    public ResponseEntity<Void> abort(@AuthenticationPrincipal AuthUser me, @PathVariable long id) {
        videos.abort(me.id(), id);
        return ResponseEntity.noContent().build();
    }

    @GetMapping("/{id}")
    public VideoService.VideoStatus status(@AuthenticationPrincipal AuthUser me, @PathVariable long id) {
        return videos.status(me.id(), id);
    }
}
