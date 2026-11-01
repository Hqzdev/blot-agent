import { Downloads, FAQ, Features, FinalCTA, Guides, Hero, Pricing, RolePicker, Statement } from "./Sections";

export function LandingPage() {
  return <main id="main-content" tabIndex={-1}>
      <Hero />
      <Statement />
      <Features />
      <RolePicker />
      <Pricing />
      <Downloads />
      <Guides />
      <FAQ />
      <FinalCTA />
    </main>;
}
