# Live Vault and Transparency Implementation Plan

**Goal:** Replace simulated depositor data with phase-aware ABI reads/writes and add a public transparency surface while preserving Trelp's design.

**Architecture:** Server actions read the configured deployment through `viem`; a small tested domain layer formats and derives values; the injected wallet signs approvals, deposits, and redemptions. Zustand retains preferences only. SVG/CSS charts render only values derived from current contract state and decoded events.

**Tech Stack:** Next.js 16, React 19, TypeScript, viem, Zod, Zustand, native CSS/SVG, Node test runner, Playwright.

**Spec:** `docs/superpowers/specs/2026-09-09-live-vault-transparency-design.md`

## Constraints

- No push or deployment.
- No dummy vault, portfolio, activity, earnings, or chart data.
- No depositor LP-management controls.
- No new dependency.
- Preserve existing uncommitted work and Trelp visual identity.

## Tasks

- [ ] Add failing domain/service tests for units, signed WAD values, phase gating, payout math, approval sequencing, and ABI-shaped reads.
- [ ] Add exact ABI fragments and validated single-deployment configuration.
- [ ] Implement phase-aware read service and typed server actions.
- [ ] Expose safe wallet transaction/receipt methods and implement approve-deposit/redeem flows.
- [ ] Replace market, dashboard, vault, portfolio, and activity demo queries with contract reads and explicit empty/setup states.
- [ ] Add Transparency with contract metrics, venue map, capital stack, live health graph, and decoded epoch timeline.
- [ ] Reduce the local store to display preferences and optional curator drafts.
- [ ] Restore the transparent rider directly over the shared landing gradient.
- [ ] Update browser journeys and visually verify desktop/mobile layouts.
- [ ] Run tests, Biome, TypeScript, production build, final diff review, and one read-only cross-model review.

## Deliverables

- Tested contract domain/service boundary.
- Real approval, deposit, and redemption requests.
- ABI-backed depositor pages and transparency page.
- Dummy financial state removed.
- Responsive code-drawn visual system matching Trelp.
