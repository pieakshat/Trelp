"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { type ReactNode, useEffect, useRef, useState } from "react";
import { BrandMark } from "@/components/brand-mark";
import { useAppShellStore } from "@/stores/app-shell-store";
import { useAppStore } from "@/stores/app-store";
import { WalletButton } from "./wallet-provider";

const navigation = [
  ["Dashboard", "/dashboard", "dashboard"],
  ["Portfolio", "/portfolio", "portfolio"],
  ["Activity", "/activity", "activity"],
  ["Transparency", "/transparency", "transparency"],
  ["Curator", "/create", "create"],
  ["Resources", "/resources", "resources"],
  ["Settings", "/settings", "settings"],
] as const;

function NavIcon({ name }: { name: (typeof navigation)[number][2] }) {
  const paths = {
    dashboard: <path d="M4 4h6v6H4zM14 4h6v6h-6zM4 14h6v6H4zM14 14h6v6h-6z" />,
    resources: <path d="M6 3h8l4 4v14H6zM14 3v5h4M9 12h6m-6 4h6" />,
    activity: <path d="M4 12h4l2-6 4 12 2-6h4" />,
    create: <path d="M12 5v14M5 12h14" />,
    portfolio: <path d="M4 7h16v12H4zM8 7V4h8v3" />,
    transparency: <path d="M4 18V9m5 9V5m5 13v-8m5 8V3M2 21h20" />,
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
  const [ready, setReady] = useState(false);
  const [storageWarning, setStorageWarning] = useState(false);
  const [mobile, setMobile] = useState(false);
  const aside = useRef<HTMLElement>(null);
  const menuButton = useRef<HTMLButtonElement>(null);
  const compact = useAppStore((s) => s.preferences.compact);
  useEffect(() => {
    let live = true;
    const warn = () => setStorageWarning(true);
    window.addEventListener("trelp-storage-error", warn);
    Promise.resolve(useAppStore.persist.rehydrate())
      .catch(() => {
        if (live) setStorageWarning(true);
      })
      .finally(() => {
        if (live) setReady(true);
      });
    const media = window.matchMedia("(max-width: 860px)");
    const update = () => setMobile(media.matches);
    update();
    media.addEventListener("change", update);
    const sync = (e: StorageEvent) => {
      if (e.key === "trelp-local-v2") void useAppStore.persist.rehydrate();
    };
    window.addEventListener("storage", sync);
    return () => {
      live = false;
      window.removeEventListener("trelp-storage-error", warn);
      media.removeEventListener("change", update);
      window.removeEventListener("storage", sync);
    };
  }, []);
  const collapsed = useAppShellStore((state) => state.collapsed);
  const mobileOpen = useAppShellStore((state) => state.mobileOpen);
  const closeMobile = useAppShellStore((state) => state.closeMobile);
  const toggleCollapsed = useAppShellStore((state) => state.toggleCollapsed);
  const toggleMobile = useAppShellStore((state) => state.toggleMobile);
  useEffect(() => {
    if (!mobile || !mobileOpen) return;
    const previous = document.body.style.overflow;
    document.body.style.overflow = "hidden";
    const links = () =>
      Array.from(
        aside.current?.querySelectorAll<HTMLElement>("a,button") ?? [],
      ).filter((el) => el.getClientRects().length > 0);
    links()[0]?.focus();
    const keydown = (e: KeyboardEvent) => {
      if (e.key === "Escape") {
        closeMobile();
        return;
      }
      if (e.key !== "Tab") return;
      const targets = links(),
        first = targets[0],
        last = targets.at(-1);
      if (e.shiftKey && document.activeElement === first) {
        e.preventDefault();
        last?.focus();
      } else if (!e.shiftKey && document.activeElement === last) {
        e.preventDefault();
        first?.focus();
      }
    };
    document.addEventListener("keydown", keydown);
    return () => {
      document.body.style.overflow = previous;
      document.removeEventListener("keydown", keydown);
      menuButton.current?.focus();
    };
  }, [mobile, mobileOpen, closeMobile]);
  const title =
    (pathname.startsWith("/vaults")
      ? "Vault"
      : navigation.find(
          ([, href]) => pathname === href || pathname.startsWith(`${href}/`),
        )?.[0]) ?? "Trelp";

  return (
    <div
      className={`appFrame${collapsed ? " sidebarCollapsed" : ""}${mobileOpen ? " sidebarMobileOpen" : ""}${compact ? " compactMode" : ""}`}
    >
      <button
        aria-label="Close navigation"
        className="sidebarOverlay"
        onClick={closeMobile}
        type="button"
      />
      <aside
        className="appSidebar"
        id="app-navigation"
        ref={aside}
        inert={mobile && !mobileOpen}
      >
        <div className="sidebarHead">
          <Link aria-label="Trelp home" className="sidebarLogo" href="/">
            <BrandMark className="sidebarBrandMark" />
          </Link>
          <button
            className="mobileSidebarClose"
            type="button"
            aria-label="Close navigation"
            onClick={closeMobile}
          >
            ×
          </button>
          <button
            aria-label={collapsed ? "Expand navigation" : "Collapse navigation"}
            className="sidebarCollapseButton"
            onClick={toggleCollapsed}
            type="button"
          >
            <svg
              aria-hidden="true"
              className="sidebarCollapseIcon"
              viewBox="0 0 24 24"
            >
              <path d={collapsed ? "m9 5 7 7-7 7" : "m15 5-7 7 7 7"} />
            </svg>
          </button>
        </div>

        <p className="sidebarSectionLabel sidebarWord">Workspace</p>
        <nav aria-label="Application navigation">
          {navigation.map(([label, href, icon]) => {
            const active = pathname === href || pathname.startsWith(`${href}/`);

            return (
              <Link
                aria-label={label}
                title={label}
                aria-current={active ? "page" : undefined}
                className={active ? "sidebarLinkActive" : undefined}
                href={href}
                key={href}
                onClick={closeMobile}
              >
                <NavIcon name={icon} />
                <span className="sidebarWord">{label}</span>
              </Link>
            );
          })}
        </nav>

        <div className="sidebarFoot">
          <Link
            className="sidebarGuide sidebarWord"
            href="/resources"
            onClick={closeMobile}
          >
            <span>Make the first move.</span>
            <strong>Understand your vault ↗</strong>
          </Link>
          <span className="sidebarWord">
            <span className="statusDot" /> Live protocol
            <br />
            <small>Reads directly from the vault</small>
          </span>
        </div>
      </aside>

      <div className="appMain" inert={mobile && mobileOpen}>
        <header className="appTopbar">
          <button
            aria-label="Open navigation"
            aria-expanded={mobileOpen}
            aria-controls="app-navigation"
            ref={menuButton}
            className="mobileMenuButton"
            onClick={toggleMobile}
            type="button"
          >
            <svg aria-hidden="true" viewBox="0 0 24 24">
              <path d="M4 7h16M4 12h16M4 17h16" />
            </svg>
          </button>
          <strong>
            <BrandMark className="topbarMark" />
            <span className="topbarBrand">
              Workspace <span aria-hidden="true">/</span>{" "}
            </span>
            {title}
          </strong>
          <WalletButton />
        </header>
        <div className="demoBanner">
          <span className="statusDot" /> On-chain workspace{" "}
          <span>Vault data comes from the configured deployment</span>
        </div>
        {storageWarning && (
          <p className="uiNotice" role="status">
            Local display preferences could not be restored.
          </p>
        )}
        {ready ? (
          children
        ) : (
          <main className="appPage" aria-busy="true">
            <p role="status">Loading your workspace…</p>
          </main>
        )}
      </div>
    </div>
  );
}
