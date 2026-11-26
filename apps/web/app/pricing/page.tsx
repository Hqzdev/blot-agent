'use client';

import { UpgradePlanDialog } from '@/components/upgrade-plan-dialog';
import { useRouter } from 'next/navigation';

export default function PricingPage() {
  const router = useRouter();
  return (
    <main className="min-h-dvh bg-background">
      <UpgradePlanDialog
        open
        onOpenChange={(open) => {
          if (!open) router.push('/');
        }}
      />
    </main>
  );
}
