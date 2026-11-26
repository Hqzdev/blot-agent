'use client';
import { billingPath } from '@/lib/billing/path';
import { useEffect, useState } from 'react';
type Overview = {
  usage: {
    plan: string;
    test: boolean;
    windows: { hours: number; percent: number; resetsAt: string | null }[];
  };
  payments: {
    paymentId: string;
    plan: string;
    status: string;
    test: boolean;
    createdAt: string;
  }[];
};
export function SubscriptionUsage() {
  const [data, setData] = useState<Overview | null>(null),
    [failed, setFailed] = useState(false);
  useEffect(() => {
    const controller = new AbortController();
    async function refresh() {
      try {
        const response = await fetch(billingPath('/api/billing/overview'), {
          cache: 'no-store',
          signal: controller.signal,
        });
        if (!response.ok) throw Error();
        setData(await response.json());
        setFailed(false);
      } catch {
        if (!controller.signal.aborted) setFailed(true);
      }
    }
    void refresh();
    const timer = setInterval(refresh, 60000);
    return () => {
      controller.abort();
      clearInterval(timer);
    };
  }, []);
  if (failed) return <p role="status">Не удалось обновить лимиты.</p>;
  if (!data) return <p role="status">Загружаем лимиты…</p>;
  return (
    <section
      aria-label="Лимиты использования"
      className="grid gap-3 rounded-xl border p-4"
    >
      <strong>
        {data.usage.test ? 'Тестовый тариф' : 'Тариф'} · {data.usage.plan}
      </strong>
      {data.usage.windows.map((w) => (
        <div key={w.hours}>
          <div className="flex justify-between">
            <span>{w.hours === 5 ? 'За 5 часов' : 'За 7 дней'}</span>
            <span>{w.percent}%</span>
          </div>
          <progress
            aria-label={
              w.hours === 5 ? 'Расход за 5 часов' : 'Расход за неделю'
            }
            className="w-full"
            max={100}
            value={w.percent}
          />
          <small>
            {w.resetsAt
              ? 'Сброс ' + new Date(w.resetsAt).toLocaleString()
              : 'Начнётся при первом использовании'}
          </small>
        </div>
      ))}
      <details>
        <summary>История платежей</summary>
        {data.payments.length ? (
          data.payments.map((p) => (
            <p key={p.paymentId}>
              {p.plan} · {p.status}
              {p.test ? ' · Тест' : ''} ·{' '}
              {new Date(p.createdAt).toLocaleDateString()}
            </p>
          ))
        ) : (
          <p>Платежей пока нет.</p>
        )}
      </details>
    </section>
  );
}
