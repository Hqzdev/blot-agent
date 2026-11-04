package dev.blot.cloud.web;

import dev.blot.application.workspace.WorkspaceFailure;
import dev.blot.cloud.CloudFailure;
import org.springframework.http.ResponseEntity;
import org.springframework.http.converter.HttpMessageNotReadableException;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.method.annotation.MethodArgumentTypeMismatchException;

@RestControllerAdvice
public final class CloudErrors {
  public record Error(String code) {}

  @ExceptionHandler(CloudFailure.class)
  public ResponseEntity<Error> cloud(CloudFailure failure) {
    return ResponseEntity.status(failure.status()).body(new Error(failure.code()));
  }

  @ExceptionHandler(WorkspaceFailure.class)
  public ResponseEntity<Error> provider(WorkspaceFailure failure) {
    return ResponseEntity.status(failure.status()).body(new Error(failure.code()));
  }

  @ExceptionHandler({
    HttpMessageNotReadableException.class,
    MethodArgumentTypeMismatchException.class,
    IllegalArgumentException.class
  })
  public ResponseEntity<Error> input(Exception failure) {
    return ResponseEntity.badRequest().body(new Error("invalid_request"));
  }

  @ExceptionHandler(Exception.class)
  public ResponseEntity<Error> unexpected(Exception failure) {
    return ResponseEntity.internalServerError().body(new Error("service_unavailable"));
  }
}
