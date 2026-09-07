# Trelp Full-Stack Product Specification

**Status:** Approved foundation scope

**Date:** 2026-09-07

**Product:** Curated discovery and management interface for tranched LP vaults

## 1. Product statement

Trelp lets a user choose how to take LP risk:

- **Senior:** priority settlement and a capped, fee-dependent target return, protected by junior first-loss capital.
- **Junior:** the residual LP return after the senior claim, in exchange for absorbing losses first.

The first release presents a small set of curated ETH/USDC vaults. A permissionless vault marketplace is a later release after the product proves junior demand, reliable data, and safe parameter selection.

## 2. Scope

This repository owns the full-stack web product:

- public landing and vault discovery;
- vault detail pages with tranche comparison and scenario analysis;
- wallet authentication and eligibility state;
- deposit, redemption, and rollover transaction preparation;
- portfolio and epoch history;
- curator administration;
- indexing and storage of product-facing protocol data;
- disclosures, consent records, access decisions, and audit events.

The `/contracts` directory is reserved for future protocol work and contains no Solidity implementation in this foundation. The web product integrates deployed protocols through typed adapters once verified ABIs, addresses, and chain IDs are supplied.

## 3. Non-goals for the foundation

- Solidity contracts, deployment scripts, audits, or protocol parameter design.
- Custody of user keys or funds.
- Promising a fixed or guaranteed return.
- Permissionless vault creation.
- A separate API service when Next.js Route Handlers cover the need.
- Client-side duplication of server or indexed blockchain state.

## 4. Users and permissions

### Depositor

Connects a wallet, reviews risk, passes applicable eligibility checks, compares tranches, prepares transactions, and tracks positions.

### Curator

Creates draft vault listings, configures product metadata, attaches verified protocol identifiers, publishes disclosures, and pauses deposits in the product interface. Curators cannot bypass validation or edit immutable historical records.

### Compliance operator

Reviews provider decisions and exceptions, manages jurisdiction policies, and exports evidence. The application stores decision references rather than raw identity documents whenever the provider can retain them.

### Administrator

Manages users and integrations. Administrative actions require strong authentication and are written to an append-only audit log.

## 5. Core product flows

### Discover

The vault list shows asset pair, epoch dates, tranche funding, target return methodology, junior cushion, status, and risk level. Filters are encoded in URL search parameters so pages remain shareable and server-rendered.

### Evaluate

The vault page shows senior and junior outcomes under the same price and fee assumptions. Every projected value is labelled as an estimate. Users can inspect the settlement waterfall, breaker events supplied by the protocol adapter, fees, oracle source, and known failure conditions.

### Participate

The app verifies network, wallet session, eligibility, current epoch state, available capacity, disclosure version, and transaction simulation before asking the wallet to sign. The server never receives a private key or seed phrase.

### Track

The portfolio uses indexed protocol events as a read model and links every material state to its transaction. It clearly separates pending, confirmed, failed, claimable, and settled positions.

### Curate

Vault publication is a draft-review-publish workflow. The server validates identifiers, duplicate listings, disclosure availability, supported assets, supported networks, and provider configuration before publication.

## 6. Monorepo architecture

The repository uses pnpm workspaces and Turborepo.

```text
apps/
  web/                    Next.js App Router product and backend
packages/
  database/               Drizzle schema and PostgreSQL client
  domain/                 Shared schemas, types, and pure calculations
  typescript-config/      Strict compiler configuration
  ui/                     Shared accessible UI primitives
contracts/                Reserved protocol workspace; documentation only
docs/superpowers/plans/   Executable implementation plans
```

One Next.js application owns pages, Server Actions, and Route Handlers. A separate worker or API app is added only when measured indexing volume or independent deployment requirements justify it.

## 7. Technology standards

- Next.js 16 App Router and React 19.
- TypeScript only, with `strict`, `noUncheckedIndexedAccess`, `exactOptionalPropertyTypes`, and `allowJs: false`.
- React Server Components by default. A component becomes a client component only for browser APIs, wallet interaction, or local interaction state.
- PostgreSQL with Drizzle ORM and checked-in migrations.
- Zod schemas at every untrusted input boundary.
- Zustand for ephemeral browser state only.
- Native CSS in the foundation. Add shadcn/ui components individually when a product flow needs them.
- Biome for formatting and static checks.
- Vitest for pure domain logic. Use browser tests only for critical user journeys.

## 8. Data ownership

PostgreSQL is the product read model, not the source of truth for protocol balances.

### Product-owned records

- curated vault metadata and publication status;
- supported assets, networks, and integration configuration;
- disclosure documents and versions;
- wallet consent receipts;
- eligibility decision references and expiry;
- user preferences;
- administrative audit events.

### Indexed records

- epochs and status transitions;
- tranche funding snapshots;
- user position events;
- settlements, claims, and transaction status.

Indexed rows include chain ID, block number, block hash, transaction hash, log index, and confirmation state. Reorg handling rewinds indexed data to the last canonical block and replays deterministically.

## 9. Database rules

- IDs are UUIDs for product records and canonical chain identifiers for indexed records.
- Token amounts are stored as integer base units or exact PostgreSQL numerics, never floating-point values.
- Addresses are normalized and compared case-insensitively while preserving the display form.
- Timestamps are UTC `timestamptz` values.
- Published disclosures and audit events are append-only.
- Migrations are generated by Drizzle Kit, reviewed, and applied once per environment.
- Application code uses transactions for multi-row state changes and unique constraints for idempotency.

## 10. Server Components, Actions, and Route Handlers

### Server Components

Use Server Components for initial database reads, vault pages, portfolio pages, and administrative lists. Parallelize independent reads and stream slow sections behind Suspense boundaries.

### Server Actions

Use Server Actions only for mutations initiated by the Trelp UI. Every action must:

1. parse `unknown` input with Zod;
2. authenticate the session and bind it to the claimed wallet;
3. authorize the requested resource and role;
4. check current database state rather than trusting hidden fields;
5. perform the mutation in a database transaction when atomicity is required;
6. return a typed success or field-safe error result;
7. write an audit event for privileged changes;
8. invalidate the narrowest affected cache or redirect.

Do not place reusable business logic in an action file. Actions call functions in `packages/domain` or a server-only application module.

### Route Handlers

Use Route Handlers for health checks, provider callbacks, public machine APIs, and future indexer ingestion. Verify signatures against the raw request body, enforce size and rate limits, and use idempotency keys before changing state.

## 11. Zustand rules

Zustand may hold:

- selected tranche;
- scenario slider values;
- deposit form progress before submission;
- dismissed educational UI;
- pending wallet interaction state.

Zustand must not hold canonical vaults, positions, permissions, eligibility decisions, or indexed chain state. Server data comes from Server Components or a request cache; URL-addressable filters remain in the URL.

Stores are small and feature-local. Actions describe user intent, selectors avoid broad subscriptions, and persisted state contains no sensitive data.

## 12. Protocol adapter boundary

The application defines a typed adapter per supported deployment with read, simulate, and transaction-preparation methods. An adapter must reject an unknown chain, address, ABI version, or epoch state. Transaction requests shown to the wallet display chain, destination, function, asset, amount, and expected effect.

Mock adapters are allowed in demo mode and must display a persistent `Simulation` label. Demo data must never share a database or deployment environment with production data.

## 13. Security baseline

- Wallet authentication uses a nonce, domain, URI, chain ID, issued-at time, and expiry; nonces are single-use.
- Authorization is checked on the server for every mutation.
- Administrative roles use least privilege and strong authentication.
- Secrets stay in server-only environment variables validated at startup.
- Content Security Policy and secure cookie attributes are enabled before production.
- State-changing endpoints have origin checks, rate limits, request size limits, and idempotency protection.
- Wallet and provider inputs are treated as untrusted.
- Logs exclude signatures, tokens, provider payloads containing identity data, and secrets.
- Dependency updates, secret scanning, static analysis, and database backups run in CI or the deployment platform.

## 14. Regulatory and policy readiness

The product must not claim legal compliance until counsel confirms the operating entity, activities, assets, users, and launch jurisdictions. Product controls make those decisions enforceable after they are defined.

Before public or mainnet access, obtain a written classification covering whether Trelp, its curator, or an operator is a virtual-asset service provider, crypto-asset service provider, broker, exchange, investment adviser, collective investment scheme operator, or other regulated person in each launch jurisdiction.

The full-stack product supports:

- configurable country and residency eligibility policies;
- sanctions and wallet-risk screening with provider reference, result, reason code, timestamp, and expiry;
- KYC/CDD status references without storing raw identity documents when avoidable;
- ongoing monitoring, case escalation, and record export where required;
- versioned terms, privacy notices, risk disclosures, and consent receipts;
- product restrictions by jurisdiction, user class, asset, and vault;
- retention and deletion schedules for personal data;
- user access, correction, and deletion workflows subject to legal holds;
- incident, complaint, and regulatory request audit trails;
- plain-language disclosure that returns are variable, junior capital takes first loss, senior capital can still be impaired, and smart-contract/oracle/liquidity risks remain.

Reference baselines include the FATF risk-based virtual asset guidance and its 2026 DeFi report, FIU-IND's January 2026 VDA AML/CFT/CPF guidelines if India is in scope, OFAC virtual-currency sanctions guidance where U.S. nexus exists, and MiCA where EU services are in scope. Counsel must map the final facts to the current law before launch.

## 15. Observability and operations

- Structured logs carry request and job correlation IDs.
- Errors report operational context without user secrets.
- Health checks cover the application and database separately.
- Alerts cover failed provider callbacks, stale indexed blocks, repeated reorgs, failed transaction reconciliation, and elevated privileged-action failures.
- Production changes use preview deployments, reviewed migrations, and rollback instructions.

## 16. Testing strategy

- Pure unit tests for tranche calculations, state transitions, validation, and normalization.
- Database integration tests for constraints, idempotency, consent versioning, and audit records.
- Route and action tests for authentication, authorization, validation, and replay rejection.
- Browser tests for wallet sign-in, risk acknowledgement, simulated participation, and curator publication.
- Contract behavior is tested by the protocol repository and verified again through adapter fixtures; it is not implemented here.

## 17. Foundation acceptance criteria

- The repository installs with one pnpm command.
- Formatting, static checks, type checking, tests, and production build run from the root.
- The web app renders a responsive tranche-selection foundation.
- A typed Zustand store controls only local scenario state.
- Shared domain code contains a checked tranche waterfall calculation.
- The Drizzle package exposes a lazy PostgreSQL client and initial product schema.
- `/contracts` clearly states its reserved status.
- No JavaScript source or configuration file exists; JSON configuration is allowed.
- No database URL is required for a static production build.

## 18. Regulatory references

- FATF, Virtual Assets: https://www.fatf-gafi.org/en/topics/virtual-assets.html
- FATF, 2026 Targeted Report on DeFi: https://www.fatf-gafi.org/en/publications/Virtualassets/targeted-report-decentralised-finance-2026.html
- FIU-IND, VDA AML/CFT/CPF Guidelines updated 8 January 2026: https://fiuindia.gov.in/pdfs/downloads/VDA08012026.pdf
- OFAC, Sanctions Compliance Guidance for the Virtual Currency Industry: https://ofac.treasury.gov/recent-actions/20211015
- Regulation (EU) 2023/1114 (MiCA): https://eur-lex.europa.eu/legal-content/EN/TXT/?uri=celex%3A32023R1114
