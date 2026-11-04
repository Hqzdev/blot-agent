import { PageFrame, PageLink } from "@/components/site/PageFrame";

export const metadata = { title: "Contact — Blot" };

export default function ContactPage() {
  return <PageFrame eyebrow="Company" title="Connect with Blot." intro="Follow the project, report an issue, or explore how the agents work."><div className="site-split"><section className="site-prose"><h2>On GitHub.</h2><p>The repository is the place for project updates, questions, and issue reports.</p><PageLink href="https://github.com/Hqzdev/blot-releases">Open the project</PageLink><PageLink href="https://github.com/Hqzdev/blot-releases/issues">Questions and issues</PageLink></section><section className="site-prose"><h2>Explore the project.</h2><p>The documentation explains the product and its integration contracts. The workspace shows the implementation plan.</p><PageLink href="/docs">Read the documentation</PageLink><PageLink href="/workspace">Open the workspace</PageLink></section></div></PageFrame>;
}
