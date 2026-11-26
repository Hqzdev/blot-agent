import { returnPath } from '@/lib/auth/blot-configuration';
import { redirect } from 'next/navigation';

export const dynamic = 'force-dynamic';
export default async function Login({
  searchParams,
}: {
  searchParams: Promise<{
    callbackUrl?: string;
    error?: string;
    loggedOut?: string;
  }>;
}) {
  const query = await searchParams;
  const start = `/app/api/auth/blot/start?${new URLSearchParams({ callbackUrl: returnPath(query.callbackUrl) })}`;
  if (query.loggedOut === '1')
    return (
      <main className="flex min-h-dvh flex-col items-center justify-center gap-4 p-6">
        <h1 className="text-2xl font-semibold">Вы вышли из Ori</h1>
        <a className="rounded-lg bg-black px-5 py-3 text-white" href={start}>
          Войти в Ori
        </a>
      </main>
    );
  if (!query.error) redirect(start.replace(/^\/app/, ''));
  return (
    <main className="flex min-h-dvh flex-col items-center justify-center gap-4 p-6">
      <h1 className="text-2xl font-semibold">
        Не удалось завершить вход в Ori
      </h1>
      <p>Попытка истекла или сервис входа недоступен. Начните вход заново.</p>
      <a className="rounded-lg bg-black px-5 py-3 text-white" href={start}>
        Повторить вход
      </a>
    </main>
  );
}
