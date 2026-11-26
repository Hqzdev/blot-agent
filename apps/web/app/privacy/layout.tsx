import type { Metadata } from 'next';

export const metadata: Metadata = {
  title: 'Terms of Service | Teya',
  description:
    'Teya Terms of Service - Read our terms and conditions for using our AI assistant service.',
  openGraph: {
    title: 'Terms of Service | Teya',
    description:
      'Teya Terms of Service - Read our terms and conditions for using our AI assistant service.',
    type: 'website',
  },
  twitter: {
    card: 'summary',
    title: 'Terms of Service | Teya',
    description: 'Teya Terms of Service - Read our terms and conditions.',
  },
  robots: {
    index: true,
    follow: true,
  },
};

export default function PrivacyLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return <>{children}</>;
}
