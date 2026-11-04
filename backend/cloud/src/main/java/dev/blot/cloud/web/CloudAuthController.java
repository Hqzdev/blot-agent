package dev.blot.cloud.web;

import dev.blot.cloud.identity.*;
import jakarta.servlet.http.HttpServletRequest;
import java.time.Duration;
import java.util.UUID;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.*;

@RestController
@RequestMapping("/v1/auth")
public final class CloudAuthController {
  public record Register(String email, String password, String name) {}

  public record Login(String email, String password) {}

  public record Code(String email, String code) {}

  public record Address(String email) {}

  public record Reset(String email, String code, String password) {}

  public record Refresh(String refreshToken) {}

  public record Binding(UUID deviceID, String nonce, byte[] signature) {}

  private final CloudAccounts accounts;
  private final CloudSessions sessions;
  private final CloudRateLimiter rates;

  public CloudAuthController(
      CloudAccounts accounts, CloudSessions sessions, CloudRateLimiter rates) {
    this.accounts = accounts;
    this.sessions = sessions;
    this.rates = rates;
  }

  @PostMapping("/register")
  @ResponseStatus(HttpStatus.ACCEPTED)
  public void register(@RequestBody Register request, HttpServletRequest http) {
    rate(http, "register", request.email(), 10);
    accounts.register(request.email(), request.password(), request.name());
  }

  @PostMapping("/verify")
  public CloudSessions.Tokens verify(@RequestBody Code request, HttpServletRequest http) {
    rate(http, "code", request.email(), 30);
    return accounts.verify(request.email(), request.code());
  }

  @PostMapping("/login")
  public CloudSessions.Tokens login(@RequestBody Login request, HttpServletRequest http) {
    rate(http, "login", request.email(), 30);
    return accounts.login(request.email(), request.password());
  }

  @PostMapping("/password/request")
  @ResponseStatus(HttpStatus.ACCEPTED)
  public void requestReset(@RequestBody Address request, HttpServletRequest http) {
    rate(http, "reset", request.email(), 10);
    accounts.requestReset(request.email());
  }

  @PostMapping("/password/reset")
  @ResponseStatus(HttpStatus.NO_CONTENT)
  public void reset(@RequestBody Reset request, HttpServletRequest http) {
    rate(http, "code", request.email(), 30);
    accounts.reset(request.email(), request.code(), request.password());
  }

  @PostMapping("/refresh")
  public CloudSessions.Tokens refresh(@RequestBody Refresh request, HttpServletRequest http) {
    rates.check("refresh:" + http.getRemoteAddr(), 120, Duration.ofMinutes(15));
    return sessions.refresh(request.refreshToken());
  }

  @GetMapping("/me")
  public CloudAccounts.Account me(
      @RequestHeader(value = "Authorization", required = false) String auth) {
    return accounts.me(sessions.require(auth, false));
  }

  @PostMapping("/device-challenge")
  public CloudSessions.BindingChallenge challenge(
      @RequestHeader(value = "Authorization", required = false) String auth) {
    return sessions.challenge(sessions.require(auth, false));
  }

  @PostMapping("/device-bind")
  @ResponseStatus(HttpStatus.NO_CONTENT)
  public void bind(
      @RequestHeader(value = "Authorization", required = false) String auth,
      @RequestBody Binding request) {
    sessions.bind(
        sessions.require(auth, false), request.deviceID(), request.nonce(), request.signature());
  }

  @PostMapping("/logout")
  @ResponseStatus(HttpStatus.NO_CONTENT)
  public void logout(@RequestHeader(value = "Authorization", required = false) String auth) {
    sessions.logout(sessions.require(auth, false));
  }

  @PostMapping("/revoke-sessions")
  @ResponseStatus(HttpStatus.NO_CONTENT)
  public void revoke(@RequestHeader(value = "Authorization", required = false) String auth) {
    sessions.revokeAll(sessions.require(auth, false));
  }

  private void rate(HttpServletRequest http, String operation, String email, int limit) {
    rates.check("auth:" + operation + ":" + http.getRemoteAddr(), limit, Duration.ofMinutes(15));
    rates.check(
        "account:" + operation + ":" + CloudTokens.email(email), limit, Duration.ofMinutes(15));
  }
}
