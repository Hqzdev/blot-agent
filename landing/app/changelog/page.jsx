import { PageFrame, PageLink } from "@/components/site/PageFrame";
import { betaRelease } from "@/lib/releases.mjs";

export const metadata = { title: "1.0 Beta · Changelog — Blot" };

export default function ChangelogPage() {
  return <PageFrame eyebrow="Changelog" title="Blot 1.0 Beta." intro="Our first downloadable beta for Mac and iPhone. Android and Windows are coming soon.">
    <article className="site-release"><time dateTime={betaRelease.date}>November 4, 2026</time><div className="site-prose">
      <span className="site-tag">First beta</span><h2>Your first workspace for a team of agents.</h2>
      <p>This release brings together the native apps, local workspace, model runtime, account sign-in, and the interface improvements built during the first stage of development.</p>
      <ul>
        <li>Native Mac and iPhone apps with light and dark appearance, agent profiles, chat navigation, and settings.</li>
        <li>Persistent chats, projects, messages, files, and memory in a local SQLite workspace.</li>
        <li>Browser sign-in with a secure return to the app, saved sessions, and separate workspaces for each account.</li>
        <li>Model streaming, saved replies, tool results, cancellation, explicit retry, context compaction, and token usage tracking.</li>
        <li>Agent groups with participant editing, role instructions, and shared budget controls.</li>
        <li>Permission controls and native Apple integration interfaces, with capabilities depending on the device and granted access.</li>
        <li>Account workspace backups, plus the protocol foundation for direct device synchronization.</li>
        <li>Improved chat responsiveness, typing indicators, whole replies, animated avatars, personalized greetings, and a cleaner Mac settings layout.</li>
      </ul>
      <h3>Before you install</h3>
      <p>Mac: Apple Silicon and macOS 26+. The DMG contains an ad hoc signed app that is not notarized. iPhone: iOS 26+; the IPA requires signing with your own Apple developer identity.</p>
      <p>The public beta includes no shared model credentials. Add your own compatible API key and choose Compatible API in your agent settings.</p>
      <h3>Still in development</h3>
      <p>Android and Windows installers, complete Wi-Fi/Bluetooth discovery and attachment synchronization, background schedule execution, and full end-to-end validation of external integrations are still in development. Some polished preview screens are ahead of the live workspace. This is an early beta, not the completed product.</p>
      <PageLink href="/beta">Download and installation</PageLink><PageLink href={betaRelease.url}>GitHub release and checksums</PageLink>
    </div></article>
    <article className="site-release"><time dateTime="2026-11-01">November 1, 2026</time><div className="site-prose"><span className="site-tag">Website</span><h2>A new home for Blot.</h2><p>A refreshed landing page, interactive chat demo, animated characters, documentation, and a project workspace with the roadmap and specifications.</p><PageLink href="/workspace">Explore the project roadmap</PageLink></div></article>
  </PageFrame>;
}
