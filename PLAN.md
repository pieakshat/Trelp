# UI refresh and dashboard enhancement

## Objective
Refresh the complete Trelp interface, integrate real brand SVG assets, add a useful dashboard and downloadable PDF/DOCX factsheets, and improve actual wallet connection and balance display. Keep the existing financial simulation intact until live contracts/backend exist.

## Research
Existing Next.js app has six connected pages, real EIP-6963/EIP-1193 wallet connection and SIWE Server Actions, persisted demo data, and no document templates. Preserve working routes and operations. Keep Trelp’s existing mark and burgundy identity; replace generic token drawings with sourced logos.

## Proposal / approval
The user explicitly authorized the entire refresh and requested an implemented dashboard and real wallet connection. Use a charcoal sidebar, warm white surfaces, burgundy accents, clearer typography, restrained SVG artwork, and consistent responsive controls. Root owns checkout edits; asset research and document creation are staged in temporary directories by subagents.

## Execution
- [x] Refresh shared UI and landing page; integrate Trelp SVG, sourced token/network logos and favicon.
- [x] Add /dashboard with derived allocation, positions, recent activity, real wallet card and linked resources.
- [x] Extend real wallet UI with safe provider icons, address copy/explorer links, actual native balance and error states.
- [x] Integrate rendered and verified factsheet PDF and editable DOCX, linked through a resources page.

## Verification
- [x] Core domain/auth tests and browser journeys, including live-wallet balance changes and dashboard navigation.
- [x] Biome, TypeScript and production build.
- [x] Desktop/mobile visual checks, SVG and document link checks.
- [x] One independent read-only review of this refresh; resolve concrete findings and inspect final diff.

## Limits
No private keys, live deposit transactions, external publishing or production data writes. Wallet RPC balances and sign-in are real; sample portfolio values remain explicitly separate. The existing single-process session store needs shared storage before a multi-instance launch. No claim of flawless compatibility with untested wallet extensions.

## Next step
Complete. Open http://localhost:3000/dashboard. All changes are local and ready for integration; no external deployment was performed.

## Final evidence
- 3 domain/auth tests pass; 4 complete browser journeys pass against the production server, including real signature verification with an ephemeral EOA, RPC balance errors/retry, hiding balances, explicit network changes without provider events, account-change logout and session invalidation retry.
- Biome, TypeScript and Next.js production build pass. The standard start command is available.
- Desktop and 320/390px mobile views checked. Both pages of the DOCX and matching exported PDF visually reviewed. All 9 public SVGs parse and contain no executable or external resource references; factsheet/download routes return successfully.
- One independent GPT-5.5 review completed. Accepted its single finding: explicit network switching relied on chainChanged to revoke the old SIWE session. Switching now invalidates in-flight session refresh and directly revokes after the confirmed chain change. Regression failed before the fix and passes afterward. No findings rejected.
- Root also corrected native-balance privacy to respect Hide balances and verified the final diff. A personal wallet extension/hardware wallet was not available for manual signing; connector tests use an EIP-1193 provider and real ephemeral signatures.
