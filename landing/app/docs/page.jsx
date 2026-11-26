import { PageFrame } from "@/components/site/PageFrame";
import { DocumentationIndex } from "@/components/site/DocumentationIndex";

export const metadata = { title: "Documentation — Ori" };

export default function DocumentationPage() {
  return <PageFrame eyebrow="Resources" title="Build with Ori." intro="The product plan, technical specification, agent architecture, and MCP integration contract."><DocumentationIndex /></PageFrame>;
}
