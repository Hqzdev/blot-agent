import { SiteText } from "@/components/site/LocaleProvider";
import { PageFrame, PageLink } from "@/components/site/PageFrame";
import { betaRelease } from "@/lib/releases.mjs";

export const metadata = { title: "1.0 Beta · Changelog — Blot" };

export default function ChangelogPage() {
  return <PageFrame eyebrow="Changelog" title="Blot 1.0 Beta." intro="Our first downloadable beta for Mac and iPhone. Android and Windows are coming soon.">
    <article className="site-release"><time dateTime={betaRelease.date}><SiteText>November 4, 2026</SiteText></time><div className="site-prose">
      <span className="site-tag"><SiteText>First beta</SiteText></span><h2><SiteText>Your first workspace for a team of agents.</SiteText></h2>
      <p><SiteText>This release brings together the native apps, local workspace, model runtime, account sign-in, and the interface improvements built during the first stage of development.</SiteText></p>
      <ul>
        <li><SiteText>Native Mac and iPhone apps with light and dark appearance, agent profiles, chat navigation, and settings.</SiteText></li>
        <li><SiteText>Persistent chats, projects, messages, files, and memory in a local SQLite workspace.</SiteText></li>
        <li><SiteText>Browser sign-in with a secure return to the app, saved sessions, and separate workspaces for each account.</SiteText></li>
        <li><SiteText>Model streaming, saved replies, tool results, cancellation, explicit retry, context compaction, and token usage tracking.</SiteText></li>
        <li><SiteText>Agent groups with participant editing, role instructions, and shared budget controls.</SiteText></li>
        <li><SiteText>Permission controls and native Apple integration interfaces, with capabilities depending on the device and granted access.</SiteText></li>
        <li><SiteText>Account workspace backups, plus the protocol foundation for direct device synchronization.</SiteText></li>
        <li><SiteText>Improved chat responsiveness, typing indicators, whole replies, animated avatars, personalized greetings, and a cleaner Mac settings layout.</SiteText></li>
      </ul>
      <h3><SiteText>Before you install</SiteText></h3>
      <p><SiteText>Mac: Apple Silicon and macOS 26+. The DMG contains an ad hoc signed app that is not notarized. iPhone: iOS 26+; the IPA requires signing with your own Apple developer identity.</SiteText></p>
      <p><SiteText>The public beta includes no shared model credentials. Add your own compatible API key and choose Compatible API in your agent settings.</SiteText></p>
      <h3><SiteText>Still in development</SiteText></h3>
      <p><SiteText>Android and Windows installers, complete Wi-Fi/Bluetooth discovery and attachment synchronization, background schedule execution, and full end-to-end validation of external integrations are still in development. Some polished preview screens are ahead of the live workspace. This is an early beta, not the completed product.</SiteText></p>
      <PageLink href="/beta"><SiteText>Download and installation</SiteText></PageLink><PageLink href={betaRelease.url}><SiteText>GitHub release and checksums</SiteText></PageLink>
    </div></article>
    <article className="site-release"><time dateTime="2026-11-01"><SiteText>November 1, 2026</SiteText></time><div className="site-prose"><span className="site-tag"><SiteText>Website</SiteText></span><h2><SiteText>A new home for Blot.</SiteText></h2><p><SiteText>A refreshed landing page, interactive chat demo, animated characters, documentation, and a project workspace with the roadmap and specifications.</SiteText></p><PageLink href="/workspace"><SiteText>Explore the project roadmap</SiteText></PageLink></div></article>
  </PageFrame>;
}
