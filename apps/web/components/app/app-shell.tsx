"use client";

import { usePathname } from "next/navigation";
import type { ReactNode } from "react";
import { BrandMark } from "@/components/brand-mark";
import { useAppShellStore } from "@/stores/app-shell-store";

const navigation = [
  ["Markets", "/app", "markets"],
  ["Portfolio", "/app/portfolio", "portfolio"],
  ["Activity", "/app/activity", "activity"],
  ["Create vault", "/app/create", "create"],
  ["Settings", "/app/settings", "settings"],
] as const;

function NavIcon({ name }: { name: (typeof navigation)[number][2] }) {
  const paths = {
    activity: <path d="M4 12h4l2-6 4 12 2-6h4" />,
    create: <path d="M12 5v14M5 12h14" />,
    markets: <path d="M4 18V9m6 9V5m6 13v-7m4 7H2" />,
    portfolio: <path d="M4 7h16v12H4zM8 7V4h8v3" />,
    settings: (
      <>
        <circle cx="12" cy="12" r="3" />
        <path d="M12 3v3m0 12v3M3 12h3m12 0h3M5.6 5.6l2.1 2.1m8.6 8.6 2.1 2.1m0-12.8-2.1 2.1m-8.6 8.6-2.1 2.1" />
      </>
    ),
  };

  return (
    <svg aria-hidden="true" className="sidebarNavIcon" viewBox="0 0 24 24">
      <g
        fill="none"
        stroke="currentColor"
        strokeLinecap="round"
        strokeWidth="1.7"
      >
        {paths[name]}
      </g>
    </svg>
  );
}

export function AppShell({ children }: { children: ReactNode }) {
  const pathname = usePathname();
  const collapsed = useAppShellStore((state) => state.collapsed);
  const mobileOpen = useAppShellStore((state) => state.mobileOpen);
  const closeMobile = useAppShellStore((state) => state.closeMobile);
  const toggleCollapsed = useAppShellStore((state) => state.toggleCollapsed);
  const toggleMobile = useAppShellStore((state) => state.toggleMobile);
  const title =
    navigation.find(([, href]) =>
      href === "/app"
        ? pathname === href || pathname.startsWith("/app/vaults")
        : pathname.startsWith(href),
    )?.[0] ?? "Trelp";

  return (
    <div
      className={`appFrame${collapsed ? " sidebarCollapsed" : ""}${mobileOpen ? " sidebarMobileOpen" : ""}`}
    >
      <button
        aria-label="Close navigation"
        className="sidebarOverlay"
        onClick={closeMobile}
        type="button"
      />
      <aside className="appSidebar">
        <a aria-label="Trelp home" className="sidebarLogo" href="/">
          <BrandMark className="sidebarBrandMark" />
          <span className="sidebarWord">TRELP</span>
        </a>

        <nav aria-label="Application navigation">
          {navigation.map(([label, href, icon]) => {
            const active =
              href === "/app"
                ? pathname === href || pathname.startsWith("/app/vaults")
                : pathname.startsWith(href);

            return (
              <a
                aria-current={active ? "page" : undefined}
                className={active ? "sidebarLinkActive" : undefined}
                href={href}
                key={href}
                onClick={closeMobile}
              >
                <NavIcon name={icon} />
                <span className="sidebarWord">{label}</span>
              </a>
            );
          })}
        </nav>

        <div className="sidebarFoot">
          <span className="sidebarWord">Preview mode</span>
          <button onClick={toggleCollapsed} type="button">
            <svg
              aria-hidden="true"
              className="sidebarCollapseIcon"
              viewBox="0 0 24 24"
            >
              <path d={collapsed ? "m9 5 7 7-7 7" : "m15 5-7 7 7 7"} />
            </svg>
            <span className="sidebarWord">
              {collapsed ? "Expand" : "Collapse"}
            </span>
          </button>
        </div>
      </aside>

      <div className="appMain">
        <header className="appTopbar">
          <button
            aria-label="Open navigation"
            className="mobileMenuButton"
            onClick={toggleMobile}
            type="button"
          >
            <svg aria-hidden="true" viewBox="0 0 24 24">
              <path d="M4 7h16M4 12h16M4 17h16" />
            </svg>
          </button>
          <strong>{title}</strong>
          <button className="connectButton" type="button">
            Connect wallet
          </button>
        </header>
        {children}
      </div>
    </div>
  );
}
