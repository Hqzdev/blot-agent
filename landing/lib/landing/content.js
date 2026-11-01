export const roles = [
  { id: "sales-outbound", name: "Sales Outbound", color: "#54b9a6", description: "Generate pipeline overnight. Researches accounts, scores contacts with intent, drafts email and LinkedIn in your voice, and leaves a review list for you to approve.", task: "Research the accounts in my sheet and draft outreach in my voice.", result: "The 36 drafts are ready for review. Each includes the account research, recipient, and opening line. Nothing goes out until you approve." },
  { id: "talent-scout", name: "Talent Scout", color: "#885cf5", description: "Keep your talent pipeline moving. Runs screen-to-offer: sources, drafts outreach in your voice, skips profiles already in the ATS, and handles scheduling once you approve.", task: "Find candidates for our open engineering role. Skip anyone already in the ATS.", result: "I found 12 matching candidates and checked them against the ATS. The shortlist and personalized outreach are ready for your review." },
  { id: "paid-media", name: "Paid Media", color: "#eb4699", description: "Pulls live channel and campaign data, sends recommended reallocations against your monthly budget, and holds bids for your approval before making adjustments.", task: "Review this month’s campaigns and recommend where to move our budget.", result: "The campaign review is ready. I flagged three opportunities to reallocate spend. Bids and budgets are unchanged, pending your approval." },
  { id: "expense-manager", name: "Expense Manager", color: "#5bc67a", description: "Stay on top of money. Builds the weekly summary from your expense manager and sheets, logs new receipts from email, and nudges owners on missing categories before weekly review.", task: "Prepare the weekly expense report and find any missing receipts.", result: "The weekly summary is ready. Nine receipts are matched to transactions; two missing categories are highlighted for review." },
  { id: "product-performance", name: "Product Performance", color: "#ea4045", description: "Get a clear view of the metrics that matter. Logs into observability tools, walks the flamegraphs, and comes back with hotspots plus a short writeup with screenshots.", task: "Investigate why the dashboard has become slower this week.", result: "I traced the slowdown to two expensive requests. The writeup includes flamegraphs, screenshots, and recommended next steps." },
  { id: "bug-reproduction", name: "Bug Reproduction", color: "#ea4045", description: "Give engineers reports they can trust. Catches the thread, clicks the same path in staging, captures the failure, and drops a repro pack (steps, screenshots, network notes).", task: "Reproduce the checkout issue from the support thread in staging.", result: "Reproduced in staging. The report includes exact steps, screenshots, and the failing network request. Production was untouched." },
  { id: "account-health", name: "Account Health", color: "#3c82f6", description: "See risk and expansion before the QBR. Reads usage and signals across your book and turns portfolio noise into a clear watch list.", task: "Review our accounts before the QBR. Flag risks and expansion opportunities.", result: "Your watch list is ready: three accounts need attention and two show expansion signals. Each finding links back to its source." },
  { id: "chief-of-staff", name: "Chief of Staff", color: "#ed712e", description: "Your always-on assistant. Scans Slack, email, calendar, and meeting notes and surfaces what’s new and what maps to your priorities. Helps follow up on dropped threads, coordinate schedules, and update deliverables.", task: "Review my week and help follow up on anything that has slipped.", result: "I pulled together your priorities, three open follow-ups, and two scheduling conflicts. Drafts are ready when you are." },
];

export const chats = [
  { id: "chief", name: "Chief", avatar: "chat-chief-of-staff", role: "chief-of-staff", preview: "booked the venue and sent the confirmation around.", time: "12:13 AM" },
  { id: "sales", name: "Sales Outbound", avatar: "chat-sales-outbound", role: "sales-outbound", preview: "The drafts are ready for your review.", time: "8:13 PM" },
  { id: "inbox", name: "Inbox Manager", avatar: "chat-inbox-manager", role: "chief-of-staff", preview: "sent. inbox at zero, 5 drafts parked for tomorrow.", time: "5:13 PM" },
  { id: "accounts", name: "Account Manager", avatar: "chat-account-manager", role: "account-health", preview: "invite’s out to Vicky. Globex note held in drafts.", time: "3:13 PM" },
  { id: "talent", name: "Talent Scout", avatar: "chat-talent-scout", role: "talent-scout", preview: "3 intros drafted in your voice, held for your OK.", time: "12:13 PM" },
  { id: "expenses", name: "Expense Manager", avatar: "chat-expense-manager", role: "expense-manager", preview: "report filed. 9 receipts, nothing outstanding.", time: "4:13 PM" },
];

export const features = [
  { title: "Blot works where you work", body: "Log Blot in once. It uses your apps and websites just like you would, including the tools that are harder to navigate." },
  { title: "Show a Bot how it’s done", body: "Ask a Bot to follow along as you complete a workflow once. It saves it as a routine and runs it on its own next time." },
  { title: "Bots get smarter over time", body: "Bots keep context and learn from each other. Show one a workflow today, hand off the project by Friday." },
  { title: "Connect the Bots", body: "Put a few Bots in the same thread and they pass work between themselves. You watch them take action instead of approving every step." },
];

export const individualPlans = [
  { name: "Premium", price: 30, intro: "Includes:", features: ["Blot’s own computer", "Signs into your tools", "Routines on a schedule", "Work anywhere: desktop, mobile, and more", "Weekly Blot usage included"] },
  { name: "Super", price: 100, intro: "Everything in Premium, plus:", features: ["3.5× Premium usage", "Priority model access at peak times"] },
  { name: "Ultra", price: 200, intro: "Everything in Super, plus:", features: ["12× Premium usage", "Earliest access to all products & models"] },
];

export const teamFeatures = ["Blot’s own computer", "Routines on a schedule", "Centralized billing and admin", "Team marketplace for skills and plugins", "Shared usage analytics", "Team-wide privacy settings", "SAML/OIDC SSO", "Mix-and-match seat types"];
export const enterpriseFeatures = ["Invoice/PO billing", "SCIM", "Granular spend controls", "Group-level settings and spend limits", "Auto-run, browser, and network controls", "Repository, model, and MCP access controls", "Audit logs and service accounts", "Access, network, and audit controls for Blot", "Priority support"];

export const faqs = [
  ["How is Blot different from AI assistants?", "Bots have their own computer, so they can work inside your apps and tools. They also run in parallel, 24/7, even when your laptop is closed."],
  ["Who is Blot available for today?", "Blot is included with Premium, Super, Ultra, Teams, and Enterprise."],
  ["Is Blot available for enterprises?", "Yes. Blot is generally available for Enterprise, as well as for teams on the Teams plan. Contact sales to set up Enterprise access for your organization, including people who don’t already have a seat."],
  ["Where do I talk to Blot?", "Work with Blot from your desktop (macOS or Windows) or your phone with the iOS app."],
  ["How much does Blot cost?", "Blot subscriptions come with weekly usage included, with additional usage billed based on token cost. Enterprise customers should contact sales."],
  ["Do Bots share one computer?", "Yes. Every user has one persistent cloud computer. Your Bots share that machine — files, browser, and logins — so they can hand work off and keep context. Isolation is per user, not per Bot."],
  ["How does Blot handle my data & privacy?", "Your cloud computer is encrypted in transit and at rest, with training opt-out. Sensitive actions can go through Auto Review before they run. Enterprise admins can set DLP, certificates, proxies, and network controls."],
];

export const menuGroups = {
  Products: [["Overview", "/"], ["Demo", "/#demo"], ["Agents", "/features"], ["Workspace", "/workspace"]],
  Solutions: [["Agent roles", "/#use-cases"], ["Teams", "/#pricing"], ["Enterprise", "/contact"], ["Integrations", "/docs"]],
  Developer: [["Documentation", "/docs"], ["MCP integrations", "/workspace/documents/mcp-developer-guide"], ["GitHub", "/github"]],
  Company: [["About Blot", "/#statement"], ["Changelog", "/changelog"], ["Contact", "/contact"], ["Privacy", "/privacy"]],
};

export const footerGroups = [
  ["Blot", [["Overview", "/"], ["Features", "/features"], ["Agent roles", "/#use-cases"], ["Pricing", "/#pricing"]]],
  ["Download", [["macOS", "/beta?platform=macos"], ["iOS", "/beta?platform=ios"], ["Android", "/beta?platform=android"], ["Windows", "/beta?platform=windows"]]],
  ["Resources", [["Documentation", "/docs"], ["MCP guide", "/workspace/documents/mcp-developer-guide"], ["Workspace", "/workspace"], ["GitHub", "/github"]]],
  ["Company", [["Changelog", "/changelog"], ["Contact", "/contact"]]],
  ["Privacy", [["Website privacy", "/privacy"], ["Data lifecycle", "/workspace/documents/P0.9"]]],
];
