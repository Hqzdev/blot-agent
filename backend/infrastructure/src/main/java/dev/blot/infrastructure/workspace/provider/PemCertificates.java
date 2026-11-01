package dev.blot.infrastructure.workspace.provider;

import dev.blot.application.ports.CertificateInspector;
import dev.blot.application.workspace.WorkspaceFailure;
import java.io.*;
import java.nio.charset.StandardCharsets;
import java.security.*;
import java.security.cert.*;
import java.util.*;

/** Разбирает выбранные владельцем CA; никакие сертификаты здесь не загружаются из сети. */
public final class PemCertificates implements CertificateInspector {
  static List<X509Certificate> parse(String pem) {
    if (pem == null || pem.length() > 65536 || !pem.contains("-----BEGIN CERTIFICATE-----"))
      throw WorkspaceFailure.invalid("Выберите сертификат CA в формате PEM");
    try {
      var factory = CertificateFactory.getInstance("X.509");
      var source = new ByteArrayInputStream(pem.getBytes(StandardCharsets.US_ASCII));
      var result = new ArrayList<X509Certificate>();
      for (var entry : factory.generateCertificates(source)) {
        var certificate = (X509Certificate) entry;
        certificate.checkValidity();
        if (certificate.getBasicConstraints() < 0)
          throw WorkspaceFailure.invalid("Нужен сертификат CA");
        result.add(certificate);
      }
      if (result.isEmpty() || result.size() > 4)
        throw WorkspaceFailure.invalid("Нужно от 1 до 4 сертификатов CA");
      return List.copyOf(result);
    } catch (GeneralSecurityException failure) {
      throw WorkspaceFailure.invalid("Сертификат CA недействителен или повреждён");
    }
  }

  public List<CertificateInfo> inspect(String pem) {
    return parse(pem).stream()
        .map(
            certificate -> {
              try {
                String fingerprint =
                    HexFormat.ofDelimiter(":")
                        .withUpperCase()
                        .formatHex(
                            MessageDigest.getInstance("SHA-256").digest(certificate.getEncoded()));
                return new CertificateInfo(
                    certificate.getSubjectX500Principal().getName(),
                    certificate.getIssuerX500Principal().getName(),
                    fingerprint,
                    certificate.getNotAfter().toInstant().toString());
              } catch (GeneralSecurityException failure) {
                throw new IllegalStateException(failure);
              }
            })
        .toList();
  }
}
