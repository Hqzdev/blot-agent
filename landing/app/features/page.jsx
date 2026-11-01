import { PageFrame } from "@/components/site/PageFrame";
import { Features, RolePicker } from "@/components/landing/Sections";

export const metadata = { title: "Features — Blot" };

export default function FeaturesPage() {
  return <PageFrame eyebrow="Product" title="A Bot for every kind of work." intro="Research, files, email, code, and the work between them. Give each agent a role and follow the team from one place." className="site-feature-page"><Features /><RolePicker /></PageFrame>;
}
