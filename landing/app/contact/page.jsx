import { SiteText } from "@/components/site/LocaleProvider";
import { PageFrame, PageLink } from "@/components/site/PageFrame";

export const metadata = { title: "Contact — Blot" };

export default function ContactPage() {
  return <PageFrame eyebrow="Company" title="Connect with Blot." intro="Follow the project, report an issue, or explore how the agents work."><div className="site-split"><section className="site-prose"><h2><SiteText>On GitHub.</SiteText></h2><p><SiteText>The repository is the place for project updates, questions, and issue reports.</SiteText></p><PageLink href="https://github.com/Hqzdev/blot-releases"><SiteText>Open the project</SiteText></PageLink><PageLink href="https://github.com/Hqzdev/blot-releases/issues"><SiteText>Questions and issues</SiteText></PageLink></section><section className="site-prose"><h2><SiteText>Explore the project.</SiteText></h2><p><SiteText>The documentation explains the product and its integration contracts. The workspace shows the implementation plan.</SiteText></p><PageLink href="/docs"><SiteText>Read the documentation</SiteText></PageLink><PageLink href="/workspace"><SiteText>Open the workspace</SiteText></PageLink></section></div></PageFrame>;
}
