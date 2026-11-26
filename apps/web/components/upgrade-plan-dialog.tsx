'use client';

import { billingPath } from '@/lib/billing/path';
import { type PaidPlan, type Plan, subscriptionCatalog } from '@teya/contracts';
import { Award, Check, Crown, Zap } from 'lucide-react';
import { useSession } from 'next-auth/react';
import { useEffect, useState } from 'react';

import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from '@/components/ui/card';
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog';
import { SubscriptionUsage } from './subscription-usage';
import { cn } from '@/lib/utils';

interface PricingTier {
  features: string[];
  name: string;
  period: string;
  plan: Plan;
  popular: boolean;
  price: string;
}

const pricingTiers: PricingTier[] = subscriptionCatalog.map((tier) => ({
  name: tier.name,
  plan: tier.plan,
  price: `${new Intl.NumberFormat('ru-RU').format(tier.amountMinor / 100)} ₽`,
  period: 'в месяц',
  popular: tier.plan === 'super',
  features: ['Подписка Ori на один месяц', 'Без автоматического продления'],
}));

function PlanIcon({ plan }: { plan: Plan }) {
  if (plan === 'premium') {
    return <Award className="size-5" />;
  }
  if (plan === 'team') {
    return <Crown className="size-5" />;
  }
  return <Zap className="size-5" />;
}

export function UpgradePlanDialog({
  open,
  onOpenChange,
}: {
  open: boolean;
  onOpenChange: (open: boolean) => void;
}) {
  const { data: session, update } = useSession();
  const [loadingPlan, setLoadingPlan] = useState<Plan | null>(null);
  const [error, setError] = useState<string | null>(null);
  const currentPlan = session?.user?.subscription ?? 'free';

  useEffect(() => {
    if (open) {
      void update();
    }
  }, [open, update]);

  async function cancelSubscription() {
    const response = await fetch(billingPath('/api/billing/subscription'), {
      method: 'DELETE',
    });
    if (!response.ok) {
      throw new Error('Не удалось изменить тариф');
    }
    await update();
    onOpenChange(false);
  }

  async function createCheckout(plan: PaidPlan) {
    const cardId = new URLSearchParams(window.location.search).get('cardId');
    const attemptId = new URLSearchParams(window.location.search).get(
      'attemptId',
    );
    const key = `blot-test-checkout:${attemptId ?? cardId ?? 'web'}:${plan}`;
    const idempotencyKey = sessionStorage.getItem(key) ?? crypto.randomUUID();
    sessionStorage.setItem(key, idempotencyKey);
    const response = await fetch(billingPath('/api/billing/checkout'), {
      body: JSON.stringify({
        cardId: cardId ?? undefined,
        attemptId: attemptId ?? undefined,
        idempotencyKey,
        plan,
      }),
      headers: { 'content-type': 'application/json' },
      method: 'POST',
    });
    const result = await response.json();
    if (!response.ok || typeof result.confirmationUrl !== 'string') {
      throw new Error(result.error || 'Не удалось создать платёж');
    }
    if (result.status === 'canceled' || result.status === 'succeeded') {
      sessionStorage.removeItem(key);
      throw new Error(
        result.status === 'canceled'
          ? 'Платёж отменён. Выберите тариф ещё раз.'
          : 'Этот платёж уже завершён.',
      );
    }
    window.location.assign(result.confirmationUrl);
  }

  async function selectPlan(plan: Plan) {
    if (plan === currentPlan) {
      return;
    }
    setLoadingPlan(plan);
    setError(null);
    try {
      if (plan === 'free') {
        await cancelSubscription();
      } else {
        await createCheckout(plan);
      }
    } catch (caughtError) {
      setError(
        caughtError instanceof Error
          ? caughtError.message
          : 'Не удалось изменить тариф',
      );
      setLoadingPlan(null);
    }
  }

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-h-[90vh] overflow-y-auto rounded-[10px] border-border bg-background text-foreground shadow-none sm:max-w-[900px]">
        <DialogHeader>
          <DialogTitle className="text-2xl font-medium">
            Выберите тариф
          </DialogTitle>
          <DialogDescription className="text-muted-foreground">
            Тестовая оплата через ЮKassa. Деньги не списываются, действующая
            подписка не меняется.
          </DialogDescription>
        </DialogHeader>
        {open && <SubscriptionUsage />}
        <div className="mt-4 grid grid-cols-1 gap-3 md:grid-cols-3">
          {pricingTiers.map((tier) => (
            <Card
              className="relative rounded-[10px] border-border bg-card text-card-foreground shadow-none"
              key={tier.plan}
            >
              {tier.popular && (
                <span className="absolute right-3 top-3 rounded-md border border-border bg-muted px-2 py-1 text-[11px] text-muted-foreground">
                  Популярный
                </span>
              )}
              <CardHeader className="pb-4">
                <div className="mb-2 flex items-center gap-2">
                  <PlanIcon plan={tier.plan} />
                  <CardTitle className="text-base font-medium">
                    {tier.name}
                  </CardTitle>
                </div>
                <CardDescription className="text-2xl font-medium text-foreground">
                  {tier.price}{' '}
                  <span className="text-sm font-normal text-muted-foreground">
                    {tier.period}
                  </span>
                </CardDescription>
              </CardHeader>
              <CardContent>
                <ul className="mb-6 space-y-2">
                  {tier.features.map((feature) => (
                    <li
                      className="flex items-center gap-2 text-sm"
                      key={feature}
                    >
                      <Check className="size-4 text-muted-foreground" />
                      <span className="text-muted-foreground">{feature}</span>
                    </li>
                  ))}
                </ul>
                <button
                  className={cn(
                    'w-full rounded-[10px] border px-4 py-2 text-sm font-medium transition-colors disabled:cursor-not-allowed disabled:opacity-50',
                    currentPlan === tier.plan
                      ? 'border-border bg-muted text-muted-foreground'
                      : 'border-primary bg-primary text-primary-foreground hover:bg-primary/90',
                  )}
                  disabled={loadingPlan !== null || currentPlan === tier.plan}
                  onClick={() => void selectPlan(tier.plan)}
                  type="button"
                >
                  {loadingPlan === tier.plan
                    ? 'Подождите...'
                    : currentPlan === tier.plan
                      ? 'Текущий тариф'
                      : 'Выбрать'}
                </button>
              </CardContent>
            </Card>
          ))}
        </div>
        {currentPlan !== 'free' && (
          <button
            type="button"
            className="justify-self-start text-sm underline"
            disabled={loadingPlan !== null}
            onClick={() => {
              if (window.confirm('Завершить действующую платную подписку и перейти на Free сейчас?')) {
                void selectPlan('free');
              }
            }}
          >
            Перейти на Free
          </button>
        )}
        {error && (
          <p className="text-sm text-muted-foreground" role="alert">
            {error}
          </p>
        )}
      </DialogContent>
    </Dialog>
  );
}
