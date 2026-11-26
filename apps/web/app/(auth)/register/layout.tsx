import type { Metadata } from 'next';

export const metadata: Metadata = {
  title: 'Создать аккаунт Ori',
  description: 'Регистрация единого аккаунта Ori для веба и приложений.',
  robots: {
    index: false,
    follow: false,
  },
};

export default function RegisterLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return <>{children}</>;
}
