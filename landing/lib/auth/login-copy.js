export const loginCopy = {
  ru: {
    login: "Войти в Blot", register: "Создать аккаунт", verify: "Проверьте почту", signedIn: "Вы вошли в аккаунт",
    choose: "Выберите способ входа", google: "Продолжить с Google", yandex: "Продолжить с Яндекс", emailButton: "Войти через почту", registerEmail: "Регистрация через почту",
    name: "Ваше имя", email: "Электронная почта", code: "Код из письма", send: "Получить код", confirm: "Войти", wait: "Подождите…", checking: "Проверяем вход…",
    codeSent: "Если аккаунт существует, код отправлен на вашу почту.", registrationSent: "Отправили код на вашу почту.", codeDescription: "Введите шестизначный код из письма для", codeHint: "Код действует 10 минут.",
    resend: "Отправить код ещё раз", resendIn: "Повторная отправка через", seconds: "с", back: "Назад", changeEmail: "Изменить почту", noAccount: "Ещё нет аккаунта?", hasAccount: "Уже есть аккаунт?", signIn: "Войти", signUp: "Зарегистрироваться",
    privacy: "Продолжая, вы принимаете", privacyLink: "политику конфиденциальности", device: "Устройство", open: "Открыть Blot", opening: "Открываем Blot…", again: "Открыть ещё раз", download: "Скачать Blot", other: "Войти в другой аккаунт",
    accountDescription: "Ваш аккаунт готов к работе.", nativeDescription: "Возвращаемся в приложение Blot…", openHelp: "Если браузер запросит разрешение открыть Blot, подтвердите его.",
    unknown: "Не удалось продолжить. Повторите попытку.",
  },
  en: {
    login: "Sign in to Blot", register: "Create an account", verify: "Check your email", signedIn: "You’re signed in",
    choose: "Choose how to continue", google: "Continue with Google", yandex: "Continue with Yandex", emailButton: "Sign in with email", registerEmail: "Register with email",
    name: "Your name", email: "Email address", code: "Email code", send: "Send code", confirm: "Sign in", wait: "Please wait…", checking: "Checking your session…",
    codeSent: "If an account exists, we’ve sent a code to your email.", registrationSent: "We’ve sent a code to your email.", codeDescription: "Enter the six-digit code sent to", codeHint: "The code expires in 10 minutes.",
    resend: "Resend code", resendIn: "Resend in", seconds: "s", back: "Back", changeEmail: "Change email", noAccount: "New to Blot?", hasAccount: "Already have an account?", signIn: "Sign in", signUp: "Create an account",
    privacy: "By continuing, you accept our", privacyLink: "privacy policy", device: "Device", open: "Open Blot", opening: "Opening Blot…", again: "Open again", download: "Download Blot", other: "Use another account",
    accountDescription: "Your account is ready.", nativeDescription: "Returning to the Blot app…", openHelp: "If your browser asks for permission to open Blot, allow it.", unknown: "Unable to continue. Please try again.",
  },
};

export const loginErrors = {
  invalid_email: ["Проверьте адрес электронной почты.", "Enter a valid email address."],
  invalid_name: ["Укажите ваше имя.", "Enter your name."],
  code_expired_or_invalid: ["Код не подошёл или истёк. Запросите новый код.", "The code is incorrect or expired. Request a new one."],
  rate_limited: ["Слишком много попыток. Повторите позже.", "Too many attempts. Please try again later."],
  challenge_cooldown: ["Письмо уже отправлено. Подождите минуту.", "A code has already been sent. Please wait a minute."],
  auth_service_unconfigured: ["Сервис входа ещё не подключён.", "The sign-in service is not configured yet."],
  auth_service_unavailable: ["Не удалось связаться с сервисом входа. Повторите попытку.", "Unable to reach the sign-in service. Please try again."],
  service_unavailable: ["Сервис временно недоступен.", "The service is temporarily unavailable."],
  web_session_unconfigured: ["Сервис входа ещё не настроен.", "The sign-in service is not configured yet."],
  web_session_expired: ["Время входа истекло. Войдите ещё раз.", "Your session expired. Please sign in again."],
  session_expired: ["Войдите ещё раз, чтобы продолжить.", "Please sign in again to continue."],
  email_unavailable: ["Не удалось отправить письмо. Попробуйте позже.", "Unable to send the email. Please try again later."],
  smtp_unconfigured: ["Отправка писем ещё не настроена.", "Email delivery is not configured yet."],
  invalid_app_request: ["Ссылка из приложения некорректна. Начните вход заново в Blot.", "Invalid app link. Start sign-in again from Blot."],
  browser_authorization_invalid: ["Ссылка для приложения истекла. Начните вход заново в Blot.", "The app link expired. Start sign-in again from Blot."],
};
for (const [provider, ru] of [["google", "Google"], ["yandex", "Яндекс"]]) {
  const en = provider === "google" ? "Google" : "Yandex";
  loginErrors[`${provider}_unconfigured`] = [`Вход через ${ru} ещё не настроен. Используйте почту.`, `${en} sign-in is not configured yet. Use email to continue.`];
  loginErrors[`${provider}_access_denied`] = [`Вы отменили вход через ${ru}.`, `You cancelled ${en} sign-in.`];
  loginErrors[`${provider}_link_required`] = ["Аккаунт с этой почтой уже есть. Войдите по коду из письма.", "An account with this email already exists. Sign in using an email code."];
  for (const reason of ["failed", "identity_invalid", "unavailable", "state_invalid"]) {
    loginErrors[`${provider}_${reason}`] = [`Не удалось войти через ${ru}. Повторите попытку или используйте почту.`, `Unable to sign in with ${en}. Try again or use email.`];
  }
}
