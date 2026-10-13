package app.fmate.common;

import app.fmate.auth.AuthUser;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.validation.ConstraintViolationException;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.dao.DataAccessException;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.http.converter.HttpMessageNotReadableException;
import org.springframework.security.access.AccessDeniedException;
import org.springframework.security.authorization.AuthorizationDeniedException;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.validation.FieldError;
import org.springframework.web.HttpRequestMethodNotSupportedException;
import org.springframework.web.bind.MethodArgumentNotValidException;
import org.springframework.web.bind.MissingRequestHeaderException;
import org.springframework.web.bind.MissingServletRequestParameterException;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;
import org.springframework.web.method.annotation.MethodArgumentTypeMismatchException;
import org.springframework.web.servlet.resource.NoResourceFoundException;

import java.util.LinkedHashMap;
import java.util.Map;

@RestControllerAdvice
public class GlobalExceptionHandler {

    private static final Logger log = LoggerFactory.getLogger(GlobalExceptionHandler.class);
    private final ErrorLogWriter errorLog;

    public GlobalExceptionHandler(ErrorLogWriter errorLog) {
        this.errorLog = errorLog;
    }

    @ExceptionHandler(ApiException.class)
    public ResponseEntity<ErrorBody> api(ApiException e) {
        return respond(e);
    }

    @ExceptionHandler(MethodArgumentNotValidException.class)
    public ResponseEntity<ErrorBody> invalid(MethodArgumentNotValidException e) {
        Map<String, String> fields = new LinkedHashMap<>();
        for (FieldError fe : e.getBindingResult().getFieldErrors()) {
            fields.putIfAbsent(fe.getField(), fe.getDefaultMessage());
        }
        ApiException api = ApiException.badRequest("VALIDATION_FAILED");
        ErrorBody base = ErrorBody.of(api, RequestContextFilter.currentRequestId());
        return ResponseEntity.status(api.status()).body(new ErrorBody(
                base.type(), base.title(), base.status(), base.code(), base.requestId(), fields));
    }

    @ExceptionHandler({ConstraintViolationException.class, HttpMessageNotReadableException.class,
            MethodArgumentTypeMismatchException.class, MissingServletRequestParameterException.class})
    public ResponseEntity<ErrorBody> badInput(Exception e) {
        return respond(ApiException.badRequest("VALIDATION_FAILED"));
    }

    @ExceptionHandler(MissingRequestHeaderException.class)
    public ResponseEntity<ErrorBody> missingHeader(MissingRequestHeaderException e) {
        if ("Idempotency-Key".equalsIgnoreCase(e.getHeaderName())) {
            return respond(ApiException.badRequest("IDEMPOTENCY_KEY_REQUIRED"));
        }
        return respond(ApiException.badRequest("BAD_REQUEST"));
    }

    @ExceptionHandler({AccessDeniedException.class, AuthorizationDeniedException.class})
    public ResponseEntity<ErrorBody> denied(Exception e) {
        return respond(ApiException.forbidden("FORBIDDEN"));
    }

    @ExceptionHandler(NoResourceFoundException.class)
    public ResponseEntity<ErrorBody> noResource(NoResourceFoundException e) {
        return respond(ApiException.notFound());
    }

    @ExceptionHandler(HttpRequestMethodNotSupportedException.class)
    public ResponseEntity<ErrorBody> method(HttpRequestMethodNotSupportedException e) {
        return respond(new ApiException(HttpStatus.METHOD_NOT_ALLOWED, "BAD_REQUEST"));
    }

    @ExceptionHandler(DataAccessException.class)
    public ResponseEntity<ErrorBody> data(DataAccessException e, HttpServletRequest req) {
        return DbErrors.translate(e)
                .map(this::respond)
                .orElseGet(() -> internal(e, req));
    }

    @ExceptionHandler(Exception.class)
    public ResponseEntity<ErrorBody> any(Exception e, HttpServletRequest req) {
        return DbErrors.translate(e)
                .map(this::respond)
                .orElseGet(() -> internal(e, req));
    }

    private ResponseEntity<ErrorBody> internal(Exception e, HttpServletRequest req) {
        log.error("unhandled {} on {} {}", e.getClass().getName(), req.getMethod(), req.getRequestURI(), e);
        errorLog.record(req.getMethod(), req.getRequestURI(), currentUserId(), e);
        return respond(new ApiException(HttpStatus.INTERNAL_SERVER_ERROR, "INTERNAL"));
    }

    private ResponseEntity<ErrorBody> respond(ApiException e) {
        return ResponseEntity.status(e.status()).body(ErrorBody.of(e, RequestContextFilter.currentRequestId()));
    }

    private static Long currentUserId() {
        Authentication auth = SecurityContextHolder.getContext().getAuthentication();
        if (auth != null && auth.getPrincipal() instanceof AuthUser u) return u.id();
        return null;
    }
}
