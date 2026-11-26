import 'server-only';
import { auth } from '@/app/(auth)/auth';
import {
  BlotAccountClient,
  BlotAccountError,
} from '@/lib/auth/blot-account-client';

export async function billingOwner(
  request: Request,
): Promise<string | undefined> {
  const header = request.headers.get('authorization');
  if (header) {
    if (!/^Bearer [A-Za-z0-9_-]{43}$/.test(header)) return undefined;
    try {
      return (await new BlotAccountClient().profile(header.slice(7))).id;
    } catch (error) {
      if (
        error instanceof BlotAccountError &&
        [401, 403].includes(error.status)
      )
        return undefined;
      throw error;
    }
  }
  return (await auth())?.user?.id;
}
