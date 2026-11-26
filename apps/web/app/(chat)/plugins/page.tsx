import { auth } from '@/app/(auth)/auth';
import { SkillsLibraryPage } from '@/components/skills/skills-library-page';
import { redirect } from 'next/navigation';

export default async function Page() {
  const session = await auth();
  if (!session?.user?.id) {
    redirect('/login');
  }
  return <SkillsLibraryPage />;
}
