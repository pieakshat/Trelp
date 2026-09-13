# Privy wallet and live contract wiring

## Objective

Use Privy for the real connected wallet, keep every deployment value in environment configuration, refresh account-dependent contract reads after confirmed writes, and expose only ABI-authorized depositor and curator operations.

## Current state

- Contract reads come from the configured RPC, vault address, and deployment block.
- Deposits approve the quote token only when needed; redemptions unlock after settlement.
- Curator controls expose only `rebalance(bytes)` and `callBuffer()`, gated by wallet role and live vault state.
- Privy replaces the hardcoded Anvil account and the custom SIWE session.

## Decisions

- `NEXT_PUBLIC_PRIVY_APP_ID` is partner-supplied public configuration; missing it keeps the app read-only.
- External wallet writes use the EIP-1193 provider returned by Privy's connected wallet so the contract sees the actual authorized address.
- The deployment chain is the only supported transaction chain for a configured instance.
- Wallet balances, allowance, claims, and vault state refresh after each confirmed receipt.

## Checks

- [x] Unit tests cover read state, phase/role gates, approvals, receipts, chain configuration, and Uniswap tick bounds.
- [x] Browser journeys cover live contract pages, mobile layout, missing Privy configuration, and locked writes.
- [x] TypeScript, Biome, and the production build pass.
- [x] Independent ABI, env, and wallet-boundary reviews; all concrete findings resolved.
- [x] 20 unit tests, 13 browser journeys, TypeScript, app-scoped Biome, and the production build pass.

## Next step

Add the partner-supplied Privy App ID, restart the web app, and perform one interactive transaction with the intended external wallet.
