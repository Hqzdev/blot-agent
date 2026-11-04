package dev.blot.cloud.web;

import dev.blot.cloud.identity.*;
import jakarta.servlet.http.HttpServletRequest;
import java.time.Duration;
import org.springframework.web.bind.annotation.*;

@RestController
@RequestMapping("/v1/auth/google")
public final class CloudGoogleAuthController {
  public record Input(String idToken, String nonce) {}

  private final CloudGoogleAccounts accounts;
  private final CloudRateLimiter rates;

  public CloudGoogleAuthController(CloudGoogleAccounts accounts, CloudRateLimiter rates) {
    this.accounts = accounts;
    this.rates = rates;
  }

  @PostMapping("/login")
  public CloudSessions.Tokens login(@RequestBody Input input, HttpServletRequest request) {
    rates.check("google-login:" + request.getRemoteAddr(), 30, Duration.ofMinutes(15));
    return accounts.login(input.idToken(), input.nonce());
  }
}
