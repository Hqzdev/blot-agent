package dev.blot.cloud.web;

import dev.blot.cloud.identity.*;
import jakarta.servlet.http.HttpServletRequest;
import java.time.Duration;
import org.springframework.web.bind.annotation.*;

@RestController
@RequestMapping("/v1/auth/browser")
public final class CloudBrowserAuthController {
  public record Issue(String clientID, String redirectURI, String codeChallenge) {}

  public record Exchange(String code, String codeVerifier, String clientID, String redirectURI) {}

  private final CloudBrowserAuthorization browser;
  private final CloudSessions sessions;
  private final CloudRateLimiter rates;

  public CloudBrowserAuthController(
      CloudBrowserAuthorization browser, CloudSessions sessions, CloudRateLimiter rates) {
    this.browser = browser;
    this.sessions = sessions;
    this.rates = rates;
  }

  @PostMapping("/code")
  public CloudBrowserAuthorization.Code code(
      @RequestHeader(value = "Authorization", required = false) String authorization,
      @RequestBody Issue input,
      HttpServletRequest request) {
    rates.check("browser-code:" + request.getRemoteAddr(), 30, Duration.ofMinutes(15));
    return browser.issue(
        sessions.require(authorization, false),
        input.clientID(),
        input.redirectURI(),
        input.codeChallenge());
  }

  @PostMapping("/token")
  public CloudSessions.Tokens token(@RequestBody Exchange input, HttpServletRequest request) {
    rates.check("browser-token:" + request.getRemoteAddr(), 60, Duration.ofMinutes(15));
    return browser.exchange(
        input.code(), input.codeVerifier(), input.clientID(), input.redirectURI());
  }
}
