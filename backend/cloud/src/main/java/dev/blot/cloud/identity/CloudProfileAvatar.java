package dev.blot.cloud.identity;

import java.net.URI;
import java.util.Locale;

/** Only provider image hosts are retained; a missing or invalid photo never rejects sign-in. */
public final class CloudProfileAvatar {
  private CloudProfileAvatar() {}

  public static String google(Object value) {
    if (!(value instanceof String text) || text.length() > 2048) return null;
    try {
      var url = URI.create(text);
      var host = url.getHost() == null ? "" : url.getHost().toLowerCase(Locale.ROOT);
      if (!"https".equals(url.getScheme())
          || url.getUserInfo() != null
          || url.getFragment() != null
          || url.getPort() != -1 && url.getPort() != 443) return null;
      return host.equals("googleusercontent.com")
              || host.endsWith(".googleusercontent.com")
              || host.equals("ggpht.com")
              || host.endsWith(".ggpht.com")
          ? text
          : null;
    } catch (IllegalArgumentException failure) {
      return null;
    }
  }
}
