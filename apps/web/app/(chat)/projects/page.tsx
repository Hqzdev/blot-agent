import { auth } from '@/app/(auth)/auth';
import { ProjectsPage } from '@/components/projects/projects-page';
import { redirect } from 'next/navigation';

export default async function Page() {
  const session = await auth();
  if (!session?.user?.id) {
    redirect('/login');
  }
  return <ProjectsPage />;
}
