# Trelp

Tranched LP positions. Senior takes a capped, priority claim on an LP position; junior takes first
loss and the entire residual.

Full-stack monorepo: the Next.js product in `apps/web`, the protocol in `contracts`.

```bash
corepack pnpm install
corepack pnpm dev
```

The landing page runs at http://localhost:3000. See [SPEC.md](./SPEC.md) for the product and
engineering requirements, and [contracts/README.md](./contracts/README.md) for the protocol.

```bash
forge test --root contracts
```

## Attribution

Powered by Aqua — © Degensoft Ltd 2025

1inch Aqua and SwapVM are source-available under the Degensoft licences, not open source. Code in
`contracts/src/aqua/` is a Modification under §3.1 and carries `LicenseRef-Degensoft-SwapVM-1.1`;
the rest of `contracts/src/` calls Aqua only through a hand-written interface and stays MIT. See
[contracts/src/aqua/LICENSE-NOTE.md](./contracts/src/aqua/LICENSE-NOTE.md).

## Design provenance

- Hero artwork: project-supplied `apps/web/public/trelp-rider.png`
- Animation runtime and interaction patterns: [Motion](https://motion.dev)
- Section rhythm references: [Supermemory](https://supermemory.ai) and [Greptile](https://www.greptile.com)
- Decorative graphics and marks: original inline SVGs; no icon library
