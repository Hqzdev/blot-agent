import { returnPath } from '@/lib/auth/blot-configuration';
import { redirect } from 'next/navigation';

export const dynamic = 'force-dynamic';
export default async function Register({
  searchParams,
}: { searchParams: Promise<{ callbackUrl?: string }> }) {
  const query = await searchParams;
  redirect(
    `/api/auth/blot/start?${new URLSearchParams({ callbackUrl: returnPath(query.callbackUrl), intent: 'register' })}`,
  );
}
