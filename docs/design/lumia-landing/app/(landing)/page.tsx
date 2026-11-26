import { auth } from '@/app/(auth)/auth';
import { LandingPage } from '@/components/landing/landing-page';
import type { Metadata } from 'next';

export const metadata: Metadata = {
  title: 'Teya — персональный искусственный интеллект',
  description:
    'Teya помогает отвечать, исследовать и рассуждать. Попробуйте режим Max с прозрачным ходом решения.',
  openGraph: {
    title: 'Teya — персональный искусственный интеллект',
    description: 'От быстрых ответов до глубокого reasoning в режиме Teya Max.',
    images: [
      {
        url: '/og.png',
        width: 1731,
        height: 909,
        alt: 'Teya — Чем я могу помочь?',
      },
    ],
  },
  twitter: {
    card: 'summary_large_image',
    title: 'Teya — персональный искусственный интеллект',
    description: 'От быстрых ответов до глубокого reasoning в режиме Teya Max.',
    images: ['/og.png'],
  },
};

export default async function Page() {
  const session = await auth();

  return <LandingPage isAuthenticated={Boolean(session?.user)} />;
}
