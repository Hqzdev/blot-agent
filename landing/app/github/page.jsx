import { PageFrame, PageLink } from "@/components/site/PageFrame";

export const metadata = { title: "GitHub — Blot" };

export default function GitHubPage() {
  return <PageFrame eyebrow="Resources" title="Follow the build." intro="Explore Blot’s repository, project plan, and technical documentation."><div className="site-split"><section className="site-prose"><h2>Hqzdev / blot-agent</h2><p>The project brings together the native applications, backend, shared contracts, and this Next.js website.</p><PageLink href="https://github.com/Hqzdev/blot-agent">Open the repository</PageLink><PageLink href="https://github.com/Hqzdev/blot-agent/issues">Issues on GitHub</PageLink></section><section className="site-prose"><h2>Plan and implementation</h2><p>The workspace tracks the actual project tasks and documentation. Repository statistics and published releases are available on GitHub.</p><PageLink href="/workspace">Open the project workspace</PageLink><PageLink href="/docs">Explore the documentation</PageLink></section></div></PageFrame>;
}
