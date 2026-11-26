import type { Metadata } from 'next';

export const metadata: Metadata = {
  title: 'Войти в Ori',
  description: 'Вход в веб-приложение через единый аккаунт Ori.',
  robots: {
    index: false,
    follow: false,
  },
};

export default function LoginLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return <>{children}</>;
}
