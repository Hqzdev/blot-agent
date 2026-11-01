# Blot landing — design QA

Date: 2026-11-01

## Target and evidence

Primary visual truth: `../agent.pen`, frames `NHNW1` (desktop), `chkSM` (mobile), and `Y4O7O` (interaction states). Raster exports are in `../docs/design/landing-previews/`. Motion and interactive reference: `https://x.ai/bot`, captured in the in-app browser. The user explicitly excluded video from the implementation.

Implementation: `http://127.0.0.1:3000/`, Next.js production build.

Evidence is stored in `design-evidence/`:

- `source-desktop.png`, `source-mobile.png`, `source-mobile-menu.png`: source browser captures.
- `implementation-desktop-hero.png`, `implementation-desktop-full.png`, `implementation-desktop-features.png`: final browser captures.
- `implementation-mobile-hero.png`, `implementation-mobile-full.png`, `implementation-mobile-menu.png`: mobile browser captures.
- `implementation-desktop-menu.png`, `implementation-desktop-role.png`, `implementation-desktop-teams.png`: captured interaction states. The role capture includes an in-progress crossfade; the final full-page captures contain settled content.
- `compare-desktop-full.png`, `compare-mobile-full.png`: approved Pencil design on the left, rendered website on the right. The video section is removed from the comparison target, following the user's instruction.
- `compare-desktop-hero.png`, `compare-mobile-hero.png`: focused, equal-width comparisons.
- `preview.png`: preview thumbnail.

Desktop comparisons use 1440 CSS px width, with 1440 × 1000 viewport captures. Mobile comparisons use 390 × 844 CSS px. Desktop Pencil export is 1440 × 8130 pixels. The mobile Pencil export was capped at 294 × 8192 pixels; it was normalized to 390 px width before comparison. Website screenshots use matching CSS-pixel dimensions. Full-page captures were taken after visiting the illustrated sections, then returning to the top so the sticky header is not captured in the middle of the page.

Light theme, initial Sales Outbound role, Individual pricing, and first FAQ open are the comparison states. Recorded pet poses and demo-chat progress intentionally vary between frames.

## Comparison history

1. **P2 — Desktop menu closed on the first click.** Hover opened the menu immediately before click toggled it shut. Fixed by making the desktop click open its named menu; pointer leave, outside click, and Escape handle closing. Retested in the production browser: Products displays Chat, Blot, Agents, and Workspace.
2. **P2 — Statement and Guides drifted from Pencil.** The statement initially used one cream surface, and Guides was centered. Restored the split text/pet composition, a separate cream pet panel, left-aligned Guides content, and its dark CTA. Compared again in the final full-page sheets.
3. **P2 — Sections could remain hidden after fast navigation.** Initial opacity zero allowed skipped scroll animations to leave full-page content invisible. Changed reveals to keep the default document visible, then animate explicit entrance keyframes. Repeated fast scrolling and focused section checks. All four feature panels are visible in the final full-page evidence; computed opacity settled at one, and browser screenshots show the actual illustrations.
4. **P2 — Agent selection could retain a paused demo after a custom message.** Choosing a new agent now resets its transcript and resumes autoplay. The mobile home-logo link also closes its dialog rather than leaving navigation open.
5. Restored SVG definition IDs in copied feature illustrations, replaced non-portable icon glyphs with the local source icon font or the installed icon library, and used the actual Apple mark. Source SVG avatars, illustrations, fonts, and branding assets are local rather than hotlinked.

## Fidelity surfaces

- **Typography:** 60 px desktop and 34 px mobile hero; 36/32 px section headings; local source variable font, with Inter as fallback. The Pencil file used Inter, while the website restores the reference font. This is intentional. Checked wrapping in role labels, FAQ questions, plan features, and the mobile header. No hidden or overlapping text was observed at the tested widths.
- **Spacing/layout:** Reviewed full-page structure and focused hero, feature, role, pricing, menu, and FAQ regions. Desktop uses paired feature columns and three individual-plan columns; mobile stacks them. The mobile plan cards retain the approved 520 px minimum. Small vertical differences come from live transcripts, actual font metrics, and functional controls; no major region is missing. Video is intentionally absent.
- **Colors/tokens:** White, `#0a0a0a`, `#858585`, `#f9f8f6`, `#f2ede5`, and `#d5d9e2` follow the agreed palette. Agent colors match the saved role catalog. The dark-theme control was exercised. This is not a claim of an independent WCAG contrast audit of the source palette.
- **Images/assets:** Existing Blot wordmark in header, footer, and mobile menu; source SVG chat avatars; recorded native vector poses for the animated pet and colored role avatars; original source feature illustrations and wallpapers. No broken images were found. No video assets are shipped. The locally recorded pet timeline reproduces the observed poses, not the original site's complete internal animation engine.
- **Copy/content:** User-facing reference branding is replaced with Blot. A browser text check found no Grok Bot, xAI, or SpaceXSI in the main document. The approved demonstration pricing/availability copy is retained. Navigation destinations point to existing project pages and anchors.

## Functional browser checks

- Desktop Products dropdown opens; its real destinations are available.
- Mobile menu opens, its Products group expands, Pricing navigation closes it, and clicking the Blot logo closes it.
- Agent search filters to one Talent Scout result; selecting it updates the chat title.
- Local demo composer accepts a message and appends its demonstration reply.
- Computer panel opens and closes; Add an agent shows six choices.
- All eight role buttons select their respective role, description, avatar, and phone demonstration.
- Individual/Teams changes three cards to two; Ultra Teams seat displays `$200 / user / month`.
- More downloads exposes macOS, iOS, Android, and Windows.
- All seven FAQ questions expand with their answers.
- Theme changes to dark and back to light.
- Pet SVG eye geometry changes between browser observations, confirming actual animation.
- Main document contains zero video elements.
- Widths 320, 390, 768, 1024, and 1440 were checked: no document horizontal overflow or escaped main layout/control boxes.
- Production browser console: no error or warning entries during the final checks.
- `npm run build`: passed, including all 49 generated pages.
- `git diff --check`: passed.

Keyboard focus styles, mobile focus trapping, Escape closing, reduced-motion handling, local-only demo state, and effect/timer cleanup are implemented. OS reduced-motion preference was not changed during this run.

## Integration limits and follow-up polish

- This is a frontend landing and demonstration, not a connection to the agent runtime or billing backend.
- Download/plan CTAs lead to the platform-availability page with platform/plan query parameters; email forms are disabled at the user’s request. No release binaries or payment service were invented.
- The initial framework advisory was resolved on 2026-11-01 by upgrading Next.js from 16.4.0 to 16.4.3. The updated lock file and npm audit report show zero known dependency vulnerabilities. This does not certify the absence of all application vulnerabilities.
- P3: the source font and real-time conversation produce small spacing/pose differences from the static Pencil fallback. Further pixel tuning is optional.

No actionable P0/P1/P2 visual or core interaction findings remain for the agreed local landing scope.


## Local cleanup and dependency update — 2026-11-01

Next.js is pinned to 16.4.3. `design-evidence/cleanup/npm-audit.json` records zero known vulnerabilities. Public routes now share SiteShell navigation, footer, theme, and accessibility preferences. Seventeen unused legacy modules and three style sheets were removed; the previous pet, sound system, card grid, fake releases, and fake GitHub counters are no longer part of the app. All email collection and mailto handling were removed at the user's request.

The live route inventory is in `page-status.md`. `design-evidence/cleanup/routes.json` contains 92 successful HTTP checks, including all 37 document pages and their downloadable source files. Desktop public pages and mobile docs/contact/platform/GitHub/workspace were checked in the in-app browser without horizontal overflow. MCP search returned its matching guide, document navigation worked, workspace Roadmap/Specification tabs switched correctly, cross-page pricing navigation reached `/#pricing`, and the mobile menu closed after navigation.

The browser automation session produced one isolated MutationObserver diagnostic that had also occurred with the previous framework; it did not reproduce as a visible application failure during the checked scenarios. No application code installs a MutationObserver. No diagnostic was suppressed.

Updated public-page screenshots are in `design-evidence/cleanup/`. The footer is intentionally reduced to implemented destinations, so its content now differs from the earlier reference clone. Pricing/availability copy remains demonstration content; no account, billing, installer hosting, or agent marketplace backend was added. The site remains local.

final result: passed
