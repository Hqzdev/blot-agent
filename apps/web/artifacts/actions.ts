'use server';

import { auth } from '@/app/(auth)/auth';
import { getSuggestionsByDocumentId } from '@/lib/db/queries';

export async function getSuggestions({ documentId }: { documentId: string }) {
  const session = await auth();
  const userId = session?.user?.id;
  if (!userId) {
    throw new Error('Unauthorized');
  }
  const suggestions = await getSuggestionsByDocumentId({
    documentId,
    userId,
  });
  return suggestions ?? [];
}
