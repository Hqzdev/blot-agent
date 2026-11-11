<p align="center">
  <img src="assets/readme/hero.svg" width="100%" alt="Blot — an AI assistant with a team of agents for Mac and iPhone">
</p>

<p align="center">
  <a href="#screenshots">Interface</a> ·
  <a href="#quick-start">Quick start</a> ·
  <a href="#architecture">Architecture</a> ·
  <a href="#checks">Checks</a> ·
  <a href="docs/README.md">Documentation</a>
</p>

# Blot

**One task. A team of agents. Results in your workspace.**

Blot is an AI assistant in development, with native apps for Mac and iPhone. You describe a task in chat, a coordinator brings in agents with the right roles, and plans, files, and actions come together in one place. This repository contains the apps, local services, website, and contracts.

<p align="center">
  <img src="docs/status/verification/mac-team-demo/workspace.jpg" width="100%" alt="Blot on macOS: a team discusses invoices and drafts an email, with participants, schedules, and connections open on the right">
</p>

<p align="center"><sub>Team chat on macOS. This screenshot is from the local demo, where external services and actions use test data.</sub></p>

## What's inside

| Area | Purpose |
| --- | --- |
| **Agent team** | A coordinator and specialists with their own names, roles, instructions, and appearances. |
| **Chats and groups** | Direct conversations, discussions between multiple agents, and task results. |
| **Files and context** | Attachments, documents, memory, and skills alongside your conversations. |
| **Action approval** | Review prepared actions before execution, with permission modes and rules. |
| **Schedules** | Interfaces for recurring tasks, reminders, and executor selection. |
| **Connections** | Service and MCP interfaces, model configuration, and accounts. |

This is an overview of the project's capabilities. Availability of a particular workflow depends on the connected service and launch mode.

## Screenshots

### iPhone · tasks, team, and schedules

<p align="center">
  <img src="docs/status/verification/apple-v3/ios/10-chat-with-ceo-light.png" width="30%" alt="iPhone: discussing a task and reviewing a plan with Blot CEO">
  <img src="docs/status/verification/apple-v3/ios/15-my-agents-light.png" width="30%" alt="iPhone: an agent catalog with roles and individual avatars">
  <img src="docs/status/verification/apple-v3/ios/17-schedules-light.png" width="30%" alt="iPhone: schedules for a morning digest and weekly meal plan">
</p>

<p align="center"><sub>Apple v3 screen catalog screenshots with test data. These show the interface; functional acceptance is checked separately.</sub></p>

<details>
<summary><strong>More screenshots: agent catalog, dark mode, and website</strong></summary>

### macOS · agents and connections

<img src="docs/status/verification/mac-team-demo/marketplace.jpg" width="100%" alt="macOS: agent templates and service connections in the local demo">

### macOS · settings in dark mode

<img src="docs/status/verification/mac-settings-page/general-dark.jpg" width="100%" alt="macOS: Blot's general settings page in dark mode">

### Web · Blot landing page

<img src="landing/design-evidence/implementation-desktop-hero.png" width="100%" alt="Blot's website hero: an introduction to the assistant, navigation, and product preview">

</details>

Source designs are in [`screens/`](screens/) and [`agent.pen`](agent.pen). Screenshots of running interfaces and verification reports are in [`docs/status/verification/`](docs/status/verification/).

## Development status

The project is under active development. The repository includes SwiftUI clients, a SQLite-backed Swift workspace package, a Java backend and account service, and a Next.js website with authentication code. The Mac team demo runs separately from the app's regular mode.

| Component | Repository status |
| --- | --- |
| **macOS and iOS** | Native app sources, a shared v3 interface, and a Debug preview catalog. |
| **Workspace** | Chat, agent, file, task, permission, memory, and sync services, with component tests. |
| **Backend and accounts** | Local Java server modules, a separate `cloud` module, web authentication, and session handoff to the app. |
| **Website** | Landing page, product pages, documentation, and a project `/workspace`. |
| **Android and Windows** | Target platforms in the specification and designs; native apps are not yet included in this repository. |
| **Release** | The instructions below are for development from source. Release readiness is assessed against the acceptance matrix. |

Screen reviews, successful builds, and component tests cover different parts of the product. A complete workflow with a real model, email, connections, and a physical iPhone requires separate verification. The main requirements and BLOT-01…30 are described in the [November 1, 2026 specification](docs/product/blot-technical-specification.md); verification history is in [`docs/status/`](docs/status/).

## Quick start

### Get the source

```bash
git clone https://github.com/Hqzdev/kiln-agent.git
cd kiln-agent
```

### Requirements

| Component | Requirements |
| --- | --- |
| Website | Node.js 24 and npm, matching CI. |
| Apple apps | macOS, Xcode with macOS/iOS 26 SDKs, and Swift 6.2 or later. Packaging the Java backend requires JDK 25. |
| Backend / account service | JDK 25; the Gradle Wrapper is included. |
| Schema checks | Python 3 and `jsonschema==4.26.0`. |

The first dependency installation requires network access. The apps target **macOS 26+** and **iOS 26+**.

### Website and documentation

```bash
cd landing
npm ci
npm run dev
```

Open [localhost:3000](http://localhost:3000). The home page presents the product, `/docs` contains documentation, and `/workspace` shows the development plan. The website's `/workspace` provides navigation through tasks and the specification; agent tasks run in the app.

`npm run build` refreshes the downloadable specification and documentation copies, then builds Next.js. Server-side authentication requires additional environment configuration.

### Mac

Open [`apps/Blot.xcodeproj`](apps/Blot.xcodeproj), select the **BlotMac** scheme, and run the app. Alternatively, from the repository root:

```bash
./script/build_and_run.sh
```

The script builds the app, checks for the embedded Java backend, and launches Blot. Additional modes are available:

```bash
# Build without launching
./script/build_and_run.sh --build-only

# Launch the local team demo with test data
./script/build_and_run.sh --design
```

### iPhone

In the same Xcode project, select the **BlotIOS** scheme and your connected physical iPhone. Configure the signing team in Xcode. The repository's default verification workflow uses physical devices; simulators and their runtimes are only used when explicitly requested.

The screen catalog is available in Debug. To open a specific v3 screen, add the following under **Scheme → Run → Arguments**:

```text
--workspace-preview --screen 10-chat-with-ceo
```

Screen names match the files in [`screens/ios/`](screens/ios/). For Mac, use [`screens/desktop/`](screens/desktop/), such as `05-new-task`. Previews use fixtures and do not perform external actions.

### Java backend and accounts

From the repository root:

```bash
# Local API
./backend/gradlew -p backend :api:bootRun

# Separate account service for development
./scripts/run-cloud.sh
```

SMTP, model, Google OAuth, database, and service URL settings are listed in [`.env.example`](.env.example). If needed, create a local `.env` and configure the workflow you want to run. Keep keys and local databases out of Git. Personal Debug builds may embed GigaChat configuration in the `.app`; account for this before sharing a build.

See the [backend guide](backend/README.md), [environment guide](docs/status/installation-environment.md), and [Apple build configuration](scripts/apple_build_configuration.py).

## Architecture

| Layer | Responsibility | Sources |
| --- | --- | --- |
| **Apple clients** | Navigation, screens, user input, and state presentation. | [`apps/`](apps/) |
| **Shared Swift packages** | Domain, API, design, graph, and workspace services. | [`packages/`](packages/) |
| **Local backend** | Java domain logic, use cases, system adapters, and HTTP API. | [`backend/`](backend/) |
| **Accounts** | Java `cloud` module and server-side web authentication modules. | [`backend/cloud/`](backend/cloud/), [`landing/lib/auth/`](landing/lib/auth/), [`landing/lib/accounts/`](landing/lib/accounts/) |
| **Contracts** | OpenAPI, JSON Schema, and shared verification data. | [`contracts/`](contracts/), [`fixtures/`](fixtures/) |
| **Web** | Next.js, React, product website, and documentation publishing. | [`landing/`](landing/) |

The Java backend is split into `core`, `application`, `infrastructure`, `api`, and `cloud`. Shared Swift packages include `BlotDomain`, `BlotAPI`, `BlotDesign`, `BlotGraph`, and `BlotWorkspace`.

The code follows single responsibility, encapsulation, and composition principles. Component responsibilities and the target architecture are described in the [module map](docs/architecture/module-map.md); entity and API versions are in [`contracts/v3/`](contracts/v3/).

```text
apps/           Mac/iPhone clients and shared SwiftUI interface
packages/       Reusable Swift packages and their tests
backend/        Java modules, Gradle Wrapper, and server tests
landing/        Website, web authentication, and project workspace
contracts/      API contracts and entity schemas
fixtures/       Shared test data
docs/           Specification, architecture, rules, and verification reports
screens/        Screen designs by platform
scripts/        Checks and environment preparation
script/         Mac app build and launch
```

## Checks

Run commands from the repository root unless a directory change is shown.

<details open>
<summary><strong>Website: plan, authentication, and build</strong></summary>

```bash
cd landing
npm run test:plan
npm run test:auth
npm run build
```

</details>

<details>
<summary><strong>Swift: domain, workspace, and design</strong></summary>

```bash
swift test --package-path packages/BlotDomain
swift test --package-path packages/BlotWorkspace
swift test --package-path packages/BlotDesign
swift test --package-path packages/BlotGraph
```

`BlotAPI` uses HTTP fixtures from the Java checks:

```bash
BLOT_HTTP_FIXTURES="$PWD/.build/http-fixtures" swift test --package-path packages/BlotAPI
```

</details>

<details>
<summary><strong>Java: formatting, dependencies, tests, and JAR</strong></summary>

```bash
./backend/gradlew --no-daemon -p backend --dependency-verification=strict spotlessCheck check :api:bootJar
```

Java HTTP tests write fixtures for `BlotAPI` to `.build/http-fixtures`.

</details>

<details>
<summary><strong>Python: Apple configuration and v3 schemas</strong></summary>

```bash
python3 -m unittest discover -s scripts/tests
python3 -m venv .build/schema-venv
.build/schema-venv/bin/python -m pip install jsonschema==4.26.0
.build/schema-venv/bin/python scripts/check-v3-schemas.py
```

</details>

CI is configured in [`.github/workflows/ci.yml`](.github/workflows/ci.yml) for the website, Java, shared Swift packages, and Apple builds. The Apple job requires a configured self-hosted runner. Results for each run are available under [Actions](https://github.com/Hqzdev/kiln-agent/actions).

## Documentation

| Start here | Purpose |
| --- | --- |
| [Documentation guide](docs/README.md) | Find the current document and distinguish it from archived material. |
| [Technical specification](docs/product/blot-technical-specification.md) | Product capabilities and the BLOT-01…30 acceptance matrix. |
| [Development plan](docs/product/blot-product-plan.md) | Implementation stages and dependencies. |
| [Module map](docs/architecture/module-map.md) | Component responsibilities and task boundaries. |
| [Domain model](docs/architecture/domain-model.md) | Entities, states, and versions. |
| [v3 contracts](contracts/v3/README.md) | Schemas for commands, events, and public data. |
| [Permissions](docs/rules/permission-policy.md) | Prepared actions, approvals, and trusted scopes. |
| [MCP guide](docs/integrations/mcp-developer-guide.md) | The contract for connected tools. |
| [Verification materials](docs/status/) | Commands, results, screenshots, and limitations. |

Where October documents differ, the **November 1, 2026** specification takes precedence. Report project questions and bugs in [GitHub Issues](https://github.com/Hqzdev/kiln-agent/issues), including the component, reproduction steps, and command output without secrets.
