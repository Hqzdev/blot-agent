# Blot website

Next.js App Router website. The `/` route implements the approved Blot landing in `../agent.pen`, with interaction and motion references from `https://x.ai/bot`. Existing documentation, workspace, contact, privacy, beta, and changelog routes remain available.

```sh
npm install
npm run dev
```

Production:

```sh
npm run build
npm run start
```

Open `http://localhost:3000`.

## Landing structure

- `app/page.jsx` owns the page metadata and route.
- `components/site/SiteShell.jsx` gives every route the same navigation, footer, theme, and reduced-motion settings.
- `app/landing.css` and `app/site.css` implement the shared visual style. Workspace-specific styles remain scoped to the workspace.
- `components/landing/Navigation.jsx` owns desktop menus and the mobile dialog, keyboard closing, focus trapping, and scroll locking.
- `components/landing/Pet.jsx` renders the observed mascot vector frames and independently colored role avatars. Animation pauses outside the viewport and respects reduced motion.
- `components/landing/ChatDemo.jsx` owns the local interactive chat demonstration: agent search, selection, message timeline, composer, pause, and computer panel. It does not call an AI provider or execute tasks.
- `components/landing/Sections.jsx` composes the page sections and their local controls.
- `lib/landing/content.js` contains the landing copy, roles, pricing, FAQ, and navigation destinations.
- `lib/landing/pet-motion.json` contains 120 recorded SVG poses and observed timestamps, derived from the existing design catalog. This is a recording of the observed animation, not the reference site's complete animation engine.
- `public/blot/visuals` isolates the source feature illustrations in decorative frames so their imported styles do not affect existing product pages. All assets and fonts are local. Parent viewport visibility pauses the illustration timelines.

The video and its player are intentionally excluded. The header and footer use the existing Blot logo. The favicon uses the selected mascot vector.

## Navigation and release wiring

Download and plan buttons currently lead to the existing `/beta` flow, with the chosen platform or plan in the query string. They do not download invented release binaries or process a payment. Contact opens the existing `/contact` page; guides and MCP documentation open existing documentation routes. Pricing and availability copy follows the approved demonstration design and is not backed by a billing service.

The `/beta` route is a platform-availability page. It displays the selected platform and plan and links to development progress. It does not collect personal data. Contact uses GitHub links only. Email forms, mailing-list controls, and mailto links were removed at the user's request.

Old bento components, their styles, the former pet renderer, sound effects, fictional releases, and fabricated GitHub metrics have been removed. [page-status.md](page-status.md) lists implemented routes and features that have not been implemented.

## Verification

`design-qa.md` records the comparison against the approved Pencil exports, source captures, browser checks, screenshot paths, and known limitations. Use `design-evidence/` for the actual browser screenshots and comparison sheets.

Next.js was upgraded from 16.4.0 to the exact patched release 16.4.3. `npm audit` reported zero known vulnerabilities after installation. The lock file is updated. This is a dependency-advisory check, not a claim that all possible application vulnerabilities have been ruled out. The website remains local.
