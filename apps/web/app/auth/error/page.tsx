import { TeyaLogo } from '@/components/teya-logo';
import Link from 'next/link';

const errorMessages: Record<string, string> = {
  Configuration:
    'Произошла ошибка конфигурации. Пожалуйста, свяжитесь с поддержкой.',
  AccessDenied:
    'Доступ запрещен. Убедитесь, что вы используете правильный аккаунт.',
  Verification: 'Проблема с верификацией. Попробуйте еще раз.',
  Default: 'Произошла ошибка при авторизации. Пожалуйста, попробуйте еще раз.',
};

interface AuthErrorPageProps {
  searchParams: Promise<{ error?: string | string[] }>;
}

export default async function AuthErrorPage({
  searchParams,
}: AuthErrorPageProps) {
  const params = await searchParams;
  const error = Array.isArray(params.error) ? params.error[0] : params.error;
  const errorMessage = error
    ? errorMessages[error] || errorMessages.Default
    : errorMessages.Default;

  return (
    <div className="auth-theme flex min-h-screen flex-col items-center justify-center bg-white px-4">
      <div className="w-full max-w-md">
        <div className="mb-8 flex items-center justify-center gap-2">
          <TeyaLogo size={32} priority />
          <span className="text-2xl font-bold">Teya</span>
        </div>

        <div className="rounded-lg border border-red-200 bg-red-50 p-6 dark:border-red-900/60 dark:bg-red-950/25">
          <h1 className="mb-4 text-xl font-semibold text-red-900 dark:text-red-200">
            Ошибка авторизации
          </h1>
          <p className="mb-4 text-sm text-red-800 dark:text-red-300">
            {errorMessage}
          </p>

          {error && (
            <div className="mb-4 rounded bg-red-100 p-3 dark:bg-red-950/50">
              <p className="text-xs font-mono text-red-900 dark:text-red-200">
                Код ошибки: <strong>{error}</strong>
              </p>
            </div>
          )}

          <div className="space-y-2">
            <Link
              href="/login"
              className="block w-full rounded-lg bg-red-600 px-4 py-2 text-center text-sm font-medium text-white transition hover:bg-red-700"
            >
              Вернуться к входу
            </Link>
            <Link
              href="/register"
              className="block w-full rounded-lg border border-red-300 bg-white px-4 py-2 text-center text-sm font-medium text-red-700 transition hover:bg-red-50 dark:border-red-800 dark:bg-transparent dark:text-red-300 dark:hover:bg-red-950/40"
            >
              Зарегистрироваться
            </Link>
          </div>

          <div className="mt-6 border-t border-red-200 pt-4 dark:border-red-900/60">
            <p className="text-xs text-red-700 dark:text-red-300">
              Если проблема сохраняется, проверьте:
            </p>
            <ul className="mt-2 list-inside list-disc space-y-1 text-xs text-red-600 dark:text-red-400">
              <li>Подключение к интернету</li>
              <li>Настройки браузера (разрешения для cookies)</li>
              <li>Правильность email адреса</li>
            </ul>
          </div>
        </div>
      </div>
    </div>
  );
}
