package dev.blot.api.workspace.auth;

import dev.blot.api.workspace.transport.RequestActor;
import dev.blot.application.workspace.*;
import dev.blot.application.workspace.conversation.SessionService;
import dev.blot.application.workspace.identity.AccountService;
import jakarta.servlet.http.HttpServletRequest;
import java.util.*;
import org.springframework.web.bind.annotation.*;

@RestController
@RequestMapping("/v2/auth")
public final class AuthController {
  public record Credentials(String email, String password, String name, boolean remember) {}

  public record Verify(String email, String code) {}

  public record Reset(String email, String code, String password) {}

  private final AccountService accounts;
  private final SessionService sessions;
  private final RequestActor actor;
  private final LoginThrottle throttle = new LoginThrottle();

  public AuthController(AccountService accounts, SessionService sessions, RequestActor actor) {
    this.accounts = accounts;
    this.sessions = sessions;
    this.actor = actor;
  }

  @PostMapping("/register")
  public Object register(@RequestBody Credentials body, HttpServletRequest req) {
    actor.requireLocal(req);
    throttle.check(req.getRemoteAddr() + ":" + body.email());
    return accounts.registerAccount(body.email(), body.password(), body.name());
  }

  @PostMapping("/verify")
  public Object verify(@RequestBody Verify body, HttpServletRequest req) {
    actor.requireLocal(req);
    return accounts.verifyEmail(body.email(), body.code());
  }

  @PostMapping("/resend")
  public Object resend(@RequestBody Verify body, HttpServletRequest req) {
    actor.requireLocal(req);
    accounts.resend(body.email());
    return Map.of("sent", true);
  }

  @PostMapping("/login")
  public Object login(@RequestBody Credentials body, HttpServletRequest req) {
    actor.requireLocal(req);
    throttle.check(req.getRemoteAddr() + ":" + body.email());
    var user = accounts.credentials(body.email(), body.password());
    return Map.of(
        "session",
        sessions.create(user.id(), null, body.remember()),
        "account",
        accounts.me(new dev.blot.core.workspace.identity.Actor(user.id(), null, null, true)));
  }

  @PostMapping("/logout")
  public Object logout(HttpServletRequest req) {
    sessions.logout(actor.require(req));
    return Map.of("signedOut", true);
  }

  @GetMapping("/me")
  public Object me(HttpServletRequest req) {
    return accounts.me(actor.require(req));
  }

  @PostMapping("/password/request")
  public Object request(@RequestBody Verify body, HttpServletRequest req) {
    actor.requireLocal(req);
    throttle.check(req.getRemoteAddr() + ":" + body.email());
    accounts.requestReset(body.email());
    return Map.of("accepted", true);
  }

  @PostMapping("/password/reset")
  public Object reset(@RequestBody Reset body, HttpServletRequest req) {
    actor.requireLocal(req);
    accounts.reset(body.email(), body.code(), body.password());
    return Map.of("changed", true);
  }
}
