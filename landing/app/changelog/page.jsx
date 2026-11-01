import { PageFrame, PageLink } from "@/components/site/PageFrame";

export const metadata = { title: "Changelog — Blot" };

export default function ChangelogPage() {
  return <PageFrame eyebrow="Company" title="What’s new in Blot." intro="Updates to the website and the project. Product releases will appear here when published."><article className="site-release"><time dateTime="2026-11-01">November 1, 2026</time><div className="site-prose"><span className="site-tag">Website</span><h2>A new home for Blot.</h2><p>The new landing introduces the team of agents, with an interactive chat demonstration, animated characters, role selection, and responsive navigation.</p><ul><li>A shared visual style across the website.</li><li>Product specifications and the MCP guide available in the documentation.</li><li>The project workspace retains its tasks, roadmap, and source documents.</li></ul><PageLink href="/workspace">Explore the project roadmap</PageLink></div></article></PageFrame>;
}
