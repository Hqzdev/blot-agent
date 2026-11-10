import { SiteText } from "@/components/site/LocaleProvider";
import { PageFrame, PageLink } from "@/components/site/PageFrame";

export const metadata = { title: "GitHub — Blot" };

export default function GitHubPage() {
  return <PageFrame eyebrow="Resources" title="Follow the build." intro="Explore Blot’s repository, project plan, and technical documentation."><div className="site-split"><section className="site-prose"><h2><SiteText>Hqzdev / blot-releases</SiteText></h2><p><SiteText>The public release repository contains Blot installers, release notes, and installation instructions. Application source code is maintained separately.</SiteText></p><PageLink href="https://github.com/Hqzdev/blot-releases"><SiteText>Open the repository</SiteText></PageLink><PageLink href="https://github.com/Hqzdev/blot-releases/issues"><SiteText>Issues on GitHub</SiteText></PageLink></section><section className="site-prose"><h2><SiteText>Plan and implementation</SiteText></h2><p><SiteText>The workspace tracks the actual project tasks and documentation. Repository statistics and published releases are available on GitHub.</SiteText></p><PageLink href="/workspace"><SiteText>Open the project workspace</SiteText></PageLink><PageLink href="/docs"><SiteText>Explore the documentation</SiteText></PageLink></section></div></PageFrame>;
}
