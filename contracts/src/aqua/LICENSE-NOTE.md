# `src/aqua/` — Degensoft licence

Everything in this directory is licensed **`LicenseRef-Degensoft-SwapVM-1.1`**, not MIT.

1inch Aqua and SwapVM are source-available, not open source. §3.1 of the Degensoft licence extends
its copyleft to anything that links against the licensed work — and §1.7 defines linking to include
static linking, which is exactly what importing SwapVM's `internal` instruction builders does: they
inline into our bytecode.

§3.3 exempts "independent code that simply calls, interfaces with, or is distributed alongside" the
work. That is why the split is a directory boundary:

| Code | Licence | Why |
|---|---|---|
| `src/` (vault, libraries, v4 venue) | MIT | Calls Aqua only through a hand-written `IAquaRegistry` interface — §3.3 |
| `src/aqua/` | Degensoft SwapVM-1.1 | Imports SwapVM instruction builders — §3.1 static linking |

The vault receives strategy bytes as opaque `bytes` and never imports a 1inch source file, so the
boundary holds without contorting the design.

## Obligations still outstanding

- [ ] Root `README.md` must carry **"Powered by Aqua — © Degensoft Ltd 2025"** (§3.1 C)
- [x] Changes marked and dated in file headers (§3.1 D)
- [x] Existing copyright and licence notices preserved (§3.1 B)
- [ ] Build and deployment instructions sufficient for reproducibility (§3.1 E)

Hackathon and prototype use is free of charge under §4. Commercial use has triggers — see
`lib/swap-vm/LICENSES/`.
