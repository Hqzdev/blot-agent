import { SiteText } from "./LocaleProvider";
import Link from "next/link";
import { ArrowUpRight } from "lucide-react";

export function PageFrame({ eyebrow, title, intro, children, className = "" }) {
  return <main id="main-content" tabIndex={-1} className={`site-page ${className}`}>
    <header className="site-page-header"><Link className="site-eyebrow" href="/">Blot{eyebrow && <><span>/</span><SiteText>{eyebrow}</SiteText></>}</Link><h1><SiteText>{title}</SiteText></h1>{intro && <p><SiteText>{intro}</SiteText></p>}</header>
    {children}
  </main>;
}

export function PageLink({ href, children }) {
  return <Link className="site-text-link" href={href}>{typeof children === "string" ? <SiteText>{children}</SiteText> : children}<ArrowUpRight size={15} /></Link>;
}
