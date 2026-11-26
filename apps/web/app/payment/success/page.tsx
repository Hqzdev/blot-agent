'use client';

import { billingPath } from '@/lib/billing/path';
import { CheckCircle, Loader2 } from 'lucide-react';
import { useSession } from 'next-auth/react';
import { useRouter } from 'next/navigation';
import { useEffect, useState } from 'react';

import { Button } from '@/components/ui/button';

const pollIntervalMs = 1500;
const maxAttempts = 20;

export default function PaymentSuccessPage() {
  const router = useRouter();
  const { update } = useSession();
  const [completedPlan, setCompletedPlan] = useState<string | null>(null);
  const [returnURL, setReturnURL] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    let canceled = false;

    async function pollPayment() {
      for (let attempt = 0; attempt < maxAttempts; attempt += 1) {
        const response = await fetch(billingPath('/api/billing/status'), {
          cache: 'no-store',
        });
        const result = await response.json();
        if (!response.ok) {
          throw new Error(result.error || 'Платёж не найден');
        }
        if (result.test !== true) throw new Error('Ожидался тестовый платёж');
        if (result.status === 'succeeded') {
          sessionStorage.removeItem(
            `blot-test-checkout:${result.cardId ?? 'web'}:${result.plan}`,
          );
          await update();
          if (!canceled) {
            if (result.handoff) {
              const { platform, id, code } = result.handoff;
              const scheme = platform === 'macos' ? 'blot-agent-macos' : 'blot-agent-ios';
              setReturnURL(`${scheme}://billing/return?${new URLSearchParams({ id, code })}`);
            }
            setCompletedPlan(result.plan);
            router.refresh();
          }
          return;
        }
        if (result.status === 'canceled') {
          sessionStorage.removeItem(
            `blot-test-checkout:${result.cardId ?? 'web'}:${result.plan}`,
          );
          throw new Error('Платёж отменён');
        }
        await new Promise((resolve) => setTimeout(resolve, pollIntervalMs));
      }
      throw new Error(
        'Платёж обрабатывается дольше обычного. Проверьте тариф позже.',
      );
    }

    void pollPayment().catch((caughtError) => {
      if (!canceled) {
        setError(
          caughtError instanceof Error
            ? caughtError.message
            : 'Не удалось проверить платёж',
        );
      }
    });

    return () => {
      canceled = true;
    };
  }, [router, update]);

  if (error) {
    return (
      <main className="flex min-h-screen items-center justify-center bg-[#fafafa]">
        <div className="max-w-md rounded-lg bg-white p-6 text-center shadow-lg">
          <p className="mb-4 text-red-600">{error}</p>
          <Button onClick={() => router.push('/chat')}>Вернуться в чат</Button>
        </div>
      </main>
    );
  }

  if (!completedPlan) {
    return (
      <main className="flex min-h-screen items-center justify-center bg-[#fafafa]">
        <div className="text-center">
          <Loader2 className="mx-auto mb-4 size-12 animate-spin text-blue-600" />
          <p className="text-lg text-gray-600">Проверяем платёж...</p>
        </div>
      </main>
    );
  }

  return (
    <main className="flex min-h-screen items-center justify-center bg-[#fafafa]">
      <div className="max-w-md rounded-lg bg-white p-8 text-center shadow-lg">
        <CheckCircle className="mx-auto mb-4 size-16 text-green-500" />
        <h1 className="mb-2 text-2xl font-bold text-gray-900">
          Тестовый платёж подтверждён
        </h1>
        <p className="mb-6 text-gray-600">
          Тестовый тариф {completedPlan} проверен. Действующая подписка не
          изменена.
        </p>
        {returnURL && (
          <Button asChild>
            <a href={returnURL}>Вернуться в Ori</a>
          </Button>
        )}
        <Button onClick={() => router.push('/chat')}>Перейти в чат</Button>
      </div>
    </main>
  );
}
