package dev.blot.infrastructure.workspace.provider;

import dev.blot.application.ports.*;
import dev.blot.application.ports.EmailSender;
import dev.blot.application.ports.SecretStore;
import dev.blot.application.workspace.WorkspaceFailure;
import jakarta.mail.*;
import jakarta.mail.internet.*;
import java.util.Properties;

public final class SmtpEmailSender implements EmailSender {
  private final SecretStore secrets;

  public SmtpEmailSender(SecretStore secrets) {
    this.secrets = secrets;
  }

  public void sendCode(String email, String code, String purpose) {
    String host = required("smtp.host"),
        user = required("smtp.username"),
        password = required("smtp.password"),
        from = required("smtp.from");
    var props = new Properties();
    props.setProperty("mail.smtp.host", host);
    props.setProperty("mail.smtp.port", secrets.get("smtp.port").orElse("587"));
    props.setProperty("mail.smtp.auth", "true");
    boolean implicitTls = props.getProperty("mail.smtp.port").equals("465");
    props.setProperty("mail.smtp.ssl.enable", Boolean.toString(implicitTls));
    props.setProperty("mail.smtp.starttls.enable", Boolean.toString(!implicitTls));
    props.setProperty("mail.smtp.starttls.required", Boolean.toString(!implicitTls));
    props.setProperty("mail.smtp.ssl.checkserveridentity", "true");
    props.setProperty("mail.smtp.connectiontimeout", "10000");
    props.setProperty("mail.smtp.timeout", "10000");
    props.setProperty("mail.smtp.writetimeout", "10000");
    var session =
        Session.getInstance(
            props,
            new Authenticator() {
              protected PasswordAuthentication getPasswordAuthentication() {
                return new PasswordAuthentication(user, password);
              }
            });
    try {
      var message = new MimeMessage(session);
      message.setFrom(new InternetAddress(from));
      message.setRecipient(Message.RecipientType.TO, new InternetAddress(email));
      message.setSubject(
          "Blot: "
              + (purpose.equals("delete")
                  ? "удаление аккаунта"
                  : purpose.equals("verify") ? "подтверждение почты" : "восстановление пароля"),
          "UTF-8");
      message.setText(
          "Ваш код: "
              + code
              + "\nКод действует 10 минут. Если вы не запрашивали код, проигнорируйте письмо.",
          "UTF-8");
      Transport.send(message);
    } catch (MessagingException e) {
      throw new WorkspaceFailure(
          503,
          "email_unavailable",
          "Не удалось отправить письмо. Проверьте настройки SMTP и повторите отправку");
    }
  }

  private String required(String key) {
    return secrets
        .get(key)
        .filter(s -> !s.isBlank())
        .orElseThrow(() -> new WorkspaceFailure(503, "smtp_unconfigured", "Настройте SMTP на Mac"));
  }
}
