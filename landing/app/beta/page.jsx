import { PageFrame } from "@/components/site/PageFrame";
import { PlatformAvailability } from "@/components/site/PlatformAvailability";

export const metadata = { title: "Early access — Blot" };
const platforms = new Set(["macos", "ios", "android", "windows"]);
const plans = new Set(["premium", "super", "ultra", "teams"]);

export default async function BetaPage({ searchParams }) {
  const query = await searchParams;
  const platform = platforms.has(query.platform) ? query.platform : "macos";
  const plan = plans.has(query.plan) ? query.plan : "";
  return <PageFrame eyebrow="Download" title="Your team, wherever you are." intro="Blot is being developed for macOS, iOS, Android, and Windows."><PlatformAvailability key={`${platform}-${plan}`} platform={platform} plan={plan} /></PageFrame>;
}
