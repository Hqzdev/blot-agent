import { PageFrame } from "@/components/site/PageFrame";
import { PlatformAvailability } from "@/components/site/PlatformAvailability";

export const metadata = { title: "Download 1.0 Beta — Blot" };
const platforms = new Set(["macos", "ios", "android", "windows"]);
const plans = new Set(["premium", "super", "ultra", "teams"]);

export default async function BetaPage({ searchParams }) {
  const query = await searchParams;
  const platform = platforms.has(query.platform) ? query.platform : "macos";
  const plan = plans.has(query.plan) ? query.plan : "";
  return <PageFrame eyebrow="1.0 Beta" title="The first Blot beta." intro="Download macOS and iPhone builds from GitHub. Android and Windows are coming soon."><PlatformAvailability key={`${platform}-${plan}`} platform={platform} plan={plan} /></PageFrame>;
}
