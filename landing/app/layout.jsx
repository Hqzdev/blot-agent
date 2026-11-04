import "@fontsource-variable/inter";
import "@fontsource/jetbrains-mono/400.css";
import "@fontsource/jetbrains-mono/500.css";
import "@fontsource/jetbrains-mono/600.css";
import "./globals.css";
import "./landing.css";
import "./site.css";
import { SiteShell } from "@/components/site/SiteShell";
import { themeInitializationScript } from "@/lib/landing/theme";

export const metadata = {
  title: "Blot — AI teammates that finish the work",
  description: "A team of AI agents for your apps, files, and projects. Blot for macOS, iOS, Android, and Windows.",
};

export default function RootLayout({ children }) {
  return (
    <html lang="en" data-theme="light" suppressHydrationWarning>
      <head>
        <script dangerouslySetInnerHTML={{ __html: themeInitializationScript }} />
      </head>
      <body>
        <a className="skip-link" href="#main-content">Skip to content</a>
        <SiteShell>{children}</SiteShell>
      </body>
    </html>
  );
}
