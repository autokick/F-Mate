package app.fmate.social;

import app.fmate.auth.AuthUser;
import app.fmate.common.IdempotencyService;
import app.fmate.common.RateLimiter;
import app.fmate.user.UserSummary;
import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PatchMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.time.Duration;
import java.util.List;
import java.util.Map;

@RestController
@RequestMapping("/api/v1")
public class SocialController {

    private final PostService posts;
    private final CommentService comments;
    private final FollowService follows;
    private final ReportService reports;
    private final IdempotencyService idempotency;
    private final RateLimiter limiter;

    public SocialController(PostService posts, CommentService comments, FollowService follows, ReportService reports,
                            IdempotencyService idempotency, RateLimiter limiter) {
        this.posts = posts;
        this.comments = comments;
        this.follows = follows;
        this.reports = reports;
        this.idempotency = idempotency;
        this.limiter = limiter;
    }

    // ------------------------------------------------------------- 피드

    @GetMapping("/feed")
    public PostService.FeedPage feed(@AuthenticationPrincipal AuthUser me,
                                     @RequestParam(defaultValue = "latest") String type,
                                     @RequestParam(required = false) Long cursor,
                                     @RequestParam(defaultValue = "20") int limit) {
        return posts.feed(me.id(), type, cursor, limit);
    }

    @GetMapping("/shorts")
    public PostService.FeedPage shorts(@AuthenticationPrincipal AuthUser me, @RequestParam(required = false) Long cursor,
                                       @RequestParam(defaultValue = "10") int limit) {
        return posts.shorts(me.id(), cursor, limit);
    }

    @GetMapping("/users/{id}/posts")
    public PostService.FeedPage userPosts(@AuthenticationPrincipal AuthUser me, @PathVariable long id,
                                          @RequestParam(defaultValue = "posts") String tab,
                                          @RequestParam(required = false) Long cursor,
                                          @RequestParam(defaultValue = "24") int limit) {
        return posts.userPosts(me.id(), id, "highlights".equals(tab), cursor, limit);
    }

    @GetMapping("/me/saved")
    public PostService.FeedPage saved(@AuthenticationPrincipal AuthUser me, @RequestParam(required = false) Long cursor,
                                      @RequestParam(defaultValue = "24") int limit) {
        return posts.saved(me.id(), cursor, limit);
    }

    @GetMapping("/hashtags/{tag}/posts")
    public PostService.FeedPage hashtag(@AuthenticationPrincipal AuthUser me, @PathVariable String tag,
                                        @RequestParam(required = false) Long cursor,
                                        @RequestParam(defaultValue = "24") int limit) {
        return posts.hashtag(me.id(), tag, cursor, limit);
    }

    // ------------------------------------------------------------- 게시물

    @PostMapping("/posts")
    public ResponseEntity<?> create(@AuthenticationPrincipal AuthUser me, @RequestHeader("Idempotency-Key") String key,
                                    @RequestBody PostService.PostInput in) {
        limiter.check("post-create", Long.toString(me.id()), 30, Duration.ofHours(1));
        return idempotency.execute(me.id(), "post-create", key, in,
                () -> ResponseEntity.status(HttpStatus.CREATED).body(posts.create(me.id(), me.emailVerified(), in)));
    }

    @GetMapping("/posts/{id}")
    public PostService.PostView get(@AuthenticationPrincipal AuthUser me, @PathVariable long id) {
        return posts.get(me.id(), id);
    }

    @PatchMapping("/posts/{id}")
    public PostService.PostView update(@AuthenticationPrincipal AuthUser me, @PathVariable long id,
                                       @RequestBody PostService.PostInput in) {
        return posts.update(me.id(), id, in);
    }

    @DeleteMapping("/posts/{id}")
    public ResponseEntity<Void> delete(@AuthenticationPrincipal AuthUser me, @PathVariable long id) {
        posts.delete(me.id(), me.isModerator(), id);
        return ResponseEntity.noContent().build();
    }

    @PutMapping("/posts/{id}/like")
    public ResponseEntity<Void> like(@AuthenticationPrincipal AuthUser me, @PathVariable long id) {
        limiter.check("like", Long.toString(me.id()), 300, Duration.ofHours(1));
        posts.like(me.id(), id, true);
        return ResponseEntity.noContent().build();
    }

    @DeleteMapping("/posts/{id}/like")
    public ResponseEntity<Void> unlike(@AuthenticationPrincipal AuthUser me, @PathVariable long id) {
        posts.like(me.id(), id, false);
        return ResponseEntity.noContent().build();
    }

    @PutMapping("/posts/{id}/save")
    public ResponseEntity<Void> save(@AuthenticationPrincipal AuthUser me, @PathVariable long id) {
        posts.save(me.id(), id, true);
        return ResponseEntity.noContent().build();
    }

    @DeleteMapping("/posts/{id}/save")
    public ResponseEntity<Void> unsave(@AuthenticationPrincipal AuthUser me, @PathVariable long id) {
        posts.save(me.id(), id, false);
        return ResponseEntity.noContent().build();
    }

    // ------------------------------------------------------------- 댓글

    @GetMapping("/posts/{id}/comments")
    public List<CommentService.CommentView> comments(@AuthenticationPrincipal AuthUser me, @PathVariable long id,
                                                     @RequestParam(required = false) Long after,
                                                     @RequestParam(defaultValue = "50") int limit) {
        return comments.list(me.id(), id, after, limit);
    }

    public record CommentRequest(Long parentId, @NotBlank @Size(max = 1000) String body) {
    }

    @PostMapping("/posts/{id}/comments")
    public ResponseEntity<CommentService.CommentView> comment(@AuthenticationPrincipal AuthUser me, @PathVariable long id,
                                                              @Valid @RequestBody CommentRequest r) {
        limiter.check("comment", Long.toString(me.id()), 120, Duration.ofHours(1));
        return ResponseEntity.status(HttpStatus.CREATED)
                .body(comments.create(me.id(), me.emailVerified(), id, r.parentId(), r.body()));
    }

    @DeleteMapping("/comments/{id}")
    public ResponseEntity<Void> deleteComment(@AuthenticationPrincipal AuthUser me, @PathVariable long id) {
        comments.delete(me.id(), me.isModerator(), id);
        return ResponseEntity.noContent().build();
    }

    // ------------------------------------------------------------- 팔로우·차단

    @PutMapping("/users/{id}/follow")
    public Map<String, String> follow(@AuthenticationPrincipal AuthUser me, @PathVariable long id) {
        limiter.check("follow", Long.toString(me.id()), 200, Duration.ofHours(1));
        return Map.of("followStatus", follows.follow(me.id(), id));
    }

    @DeleteMapping("/users/{id}/follow")
    public ResponseEntity<Void> unfollow(@AuthenticationPrincipal AuthUser me, @PathVariable long id) {
        follows.unfollow(me.id(), id);
        return ResponseEntity.noContent().build();
    }

    @GetMapping("/users/{id}/followers")
    public List<UserSummary> followers(@AuthenticationPrincipal AuthUser me, @PathVariable long id,
                                       @RequestParam(defaultValue = "0") int page,
                                       @RequestParam(defaultValue = "30") int size) {
        return follows.followers(me.id(), id, page, size);
    }

    @GetMapping("/users/{id}/following")
    public List<UserSummary> following(@AuthenticationPrincipal AuthUser me, @PathVariable long id,
                                       @RequestParam(defaultValue = "0") int page,
                                       @RequestParam(defaultValue = "30") int size) {
        return follows.following(me.id(), id, page, size);
    }

    @GetMapping("/me/follow-requests")
    public List<UserSummary> requests(@AuthenticationPrincipal AuthUser me) {
        return follows.requests(me.id());
    }

    @PostMapping("/me/follow-requests/{userId}/accept")
    public ResponseEntity<Void> accept(@AuthenticationPrincipal AuthUser me, @PathVariable long userId) {
        follows.acceptRequest(me.id(), userId);
        return ResponseEntity.noContent().build();
    }

    @PostMapping("/me/follow-requests/{userId}/reject")
    public ResponseEntity<Void> reject(@AuthenticationPrincipal AuthUser me, @PathVariable long userId) {
        follows.removeFollower(me.id(), userId);
        return ResponseEntity.noContent().build();
    }

    @DeleteMapping("/me/followers/{userId}")
    public ResponseEntity<Void> removeFollower(@AuthenticationPrincipal AuthUser me, @PathVariable long userId) {
        follows.removeFollower(me.id(), userId);
        return ResponseEntity.noContent().build();
    }

    @PutMapping("/users/{id}/block")
    public ResponseEntity<Void> block(@AuthenticationPrincipal AuthUser me, @PathVariable long id) {
        follows.block(me.id(), id);
        return ResponseEntity.noContent().build();
    }

    @DeleteMapping("/users/{id}/block")
    public ResponseEntity<Void> unblock(@AuthenticationPrincipal AuthUser me, @PathVariable long id) {
        follows.unblock(me.id(), id);
        return ResponseEntity.noContent().build();
    }

    @GetMapping("/me/blocks")
    public List<UserSummary> blocks(@AuthenticationPrincipal AuthUser me) {
        return follows.blocked(me.id());
    }

    // ------------------------------------------------------------- 신고

    public record ReportRequest(@NotBlank String targetType, @NotNull Long targetId, @NotBlank String reason,
                                @Size(max = 1000) String detail) {
    }

    @PostMapping("/reports")
    public ResponseEntity<Map<String, Long>> report(@AuthenticationPrincipal AuthUser me, @Valid @RequestBody ReportRequest r) {
        limiter.check("report", Long.toString(me.id()), 30, Duration.ofHours(1));
        long id = reports.report(me.id(), r.targetType(), r.targetId(), r.reason(), r.detail());
        return ResponseEntity.status(HttpStatus.CREATED).body(Map.of("reportId", id));
    }
}
