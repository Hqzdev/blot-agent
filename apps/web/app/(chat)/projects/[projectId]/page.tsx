import { auth } from '@/app/(auth)/auth';
import { ProjectPage } from '@/components/projects/project-page';
import { redirect } from 'next/navigation';

export default async function Page({
  params,
}: {
  params: Promise<{ projectId: string }>;
}) {
  const session = await auth();
  if (!session?.user?.id) {
    redirect('/login');
  }
  const { projectId } = await params;
  return <ProjectPage projectId={projectId} />;
}
