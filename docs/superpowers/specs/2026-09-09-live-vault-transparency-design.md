# Live Vault and Transparency Design

## Product boundary

Depositors choose Senior or Junior, approve the quote token, deposit, monitor the epoch, and redeem after settlement. The vault owns LP deployment and unwinding. Curator controls are optional operator tooling and are not shown as depositor actions.

## Data ownership

The configured `TrancheVault` deployment and its claim/quote tokens are the source of truth. Vault state comes from contract reads; positions come from `balanceOf`; history comes from emitted logs. Browser state holds only display preferences and pending UI state. Missing deployment configuration produces an explicit setup state, never sample financial data.

## Visual philosophy

Keep Trelp's warm paper, charcoal, burgundy, editorial typography, rider, and animated gradient. Borrow only the references' hierarchy: compact metric ribbons, thin bordered panels, dense comparison rows, segmented controls, and large code-drawn charts. The transparency page uses a NAV/claim chart, capital-stack graph, venue map, contract table, and epoch timeline. Charts explain contract state and use no fabricated time series.

## Pages

- Markets: configured vault deployment with live phase, NAV, principals, coupon, coverage, and tranche funding.
- Vault detail: shared terms and two tranche cards; phase-aware deposit/redeem action.
- Portfolio: connected wallet's Senior and Junior token balances and claimable settlement assets.
- Activity: decoded vault events from the configured deployment block.
- Transparency: public vault health, earnings, capital stack, venue addresses, position value, buffer status, costs, and lifecycle events.
- Curator: existing draft workflow remains optional and visually separated from depositor navigation.

## Reliability

Reads are phase-aware because terms-derived calls can revert before activation. Token values stay as `bigint` base units until formatting. Deposits use exact allowances when needed and wait for the approval receipt before sending the vault call. Redemptions require no approval. Wrong-chain, rejected, reverted, missing-config, loading, and empty states are explicit.

## Missing deployment input

`TRELP_CHAIN_ID`, `TRELP_VAULT_ADDRESS`, `TRELP_DEPLOYMENT_BLOCK`, and `TRELP_RPC_URL` must be supplied for live reads. Until then the UI shows a configuration-required state with no dummy vault values.
