package dev.blot.api;

import dev.blot.application.ApplicationError;
import dev.blot.application.workspace.WorkspaceFailure;
import dev.blot.core.workspace.Entity;
import dev.blot.infrastructure.database.StorageException;
import java.util.Map;
import org.springframework.http.ResponseEntity;
import org.springframework.http.converter.HttpMessageNotReadableException;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.method.annotation.MethodArgumentTypeMismatchException;

@RestControllerAdvice
public final class ApiErrorHandler {
  public record ErrorResponse(String code, String message, Map<String, String> details) {}

  @ExceptionHandler(WorkspaceFailure.class)
  public ResponseEntity<ErrorResponse> workspace(WorkspaceFailure failure) {
    return response(failure.status(), failure.code(), failure.getMessage(), Map.of());
  }

  @ExceptionHandler(IllegalArgumentException.class)
  public ResponseEntity<ErrorResponse> invalidArgument(IllegalArgumentException failure) {
    return response(400, "validation", "Неверные данные запроса", Map.of());
  }

  @ExceptionHandler(ApplicationFailure.class)
  public ResponseEntity<ErrorResponse> application(ApplicationFailure failure) {
    ApplicationError error = failure.error();
    if (error instanceof ApplicationError.Validation e)
      return response(400, "validation", e.reason(), Map.of("field", e.field()));
    if (error instanceof ApplicationError.NotFound e)
      return response(
          404,
          "not_found",
          "Entity not found",
          Map.of("resource", e.resource(), "id", e.id().toString()));
    if (error instanceof ApplicationError.VersionConflict e)
      return response(
          409,
          "version_conflict",
          "Version conflict",
          Map.of("expected", Long.toString(e.expected()), "actual", Long.toString(e.actual())));
    if (error instanceof ApplicationError.InvalidTransition e)
      return response(
          409,
          "invalid_transition",
          "Status transition forbidden",
          Map.of("from", e.from().name(), "to", e.to().name()));
    return response(409, "conflict", "Entity conflict", Map.of());
  }

  @ExceptionHandler({
    HttpMessageNotReadableException.class,
    MethodArgumentTypeMismatchException.class,
    java.nio.file.InvalidPathException.class
  })
  public ResponseEntity<ErrorResponse> invalid(Exception e) {
    return response(400, "validation", "Invalid request", Map.of());
  }

  @ExceptionHandler(StorageException.class)
  public ResponseEntity<ErrorResponse> storage(StorageException e) {
    return response(
        e.kind() == StorageException.Kind.CONSTRAINT ? 409 : 503,
        e.kind() == StorageException.Kind.CONSTRAINT ? "conflict" : "storage_unavailable",
        "Storage operation failed",
        Map.of());
  }

  @ExceptionHandler(org.springframework.web.servlet.resource.NoResourceFoundException.class)
  public ResponseEntity<ErrorResponse> missingRoute(Exception failure) {
    return response(404, "not_found", "Маршрут отсутствует в контракте v2", Map.of());
  }

  @ExceptionHandler(Exception.class)
  public ResponseEntity<ErrorResponse> unexpected(Exception e) {
    return response(500, "internal", "Unexpected server error", Map.of());
  }

  private ResponseEntity<ErrorResponse> response(
      int status, String code, String message, Map<String, String> details) {
    return ResponseEntity.status(status).body(new ErrorResponse(code, message, details));
  }
}
