import { PageFrame } from "@/components/site/PageFrame";
import { PlatformAvailability } from "@/components/site/PlatformAvailability";
import { betaRelease } from "@/lib/releases.mjs";

export const metadata = { title: `Download ${betaRelease.version} — Ori` };
const platforms = new Set(["macos", "ios", "android", "windows"]);
const plans = new Set(["premium", "super", "ultra", "teams"]);

export default async function BetaPage({ searchParams }) {
  const query = await searchParams;
  const platform = platforms.has(query.platform) ? query.platform : "macos";
  const plan = plans.has(query.plan) ? query.plan : "";
  return <PageFrame eyebrow={betaRelease.version} title="Download Ori" intro="Download macOS and iPhone builds from GitHub. Android and Windows are coming soon."><PlatformAvailability key={`${platform}-${plan}`} platform={platform} plan={plan} /></PageFrame>;
}
