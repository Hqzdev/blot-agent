import { PageFrame, PageLink } from "@/components/site/PageFrame";

export const metadata = { title: "GitHub — Blot" };

export default function GitHubPage() {
  return <PageFrame eyebrow="Resources" title="Follow the build." intro="Explore Blot’s repository, project plan, and technical documentation."><div className="site-split"><section className="site-prose"><h2>Hqzdev / blot-releases</h2><p>The public release repository contains Blot installers, release notes, and installation instructions. Application source code is maintained separately.</p><PageLink href="https://github.com/Hqzdev/blot-releases">Open the repository</PageLink><PageLink href="https://github.com/Hqzdev/blot-releases/issues">Issues on GitHub</PageLink></section><section className="site-prose"><h2>Plan and implementation</h2><p>The workspace tracks the actual project tasks and documentation. Repository statistics and published releases are available on GitHub.</p><PageLink href="/workspace">Open the project workspace</PageLink><PageLink href="/docs">Explore the documentation</PageLink></section></div></PageFrame>;
}
