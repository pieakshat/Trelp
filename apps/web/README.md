# Trelp web

The product UI reads one deployed `TrancheVault`, its Senior and Junior claim tokens, quote token, managed position, and vault events. Depositors approve quote tokens only when required, deposit during Subscription, and redeem claim tokens after settlement. Curator operations are sent only by the configured curator wallet when their on-chain conditions are satisfied.

## Configure a deployment

Copy the values in `.env.example` into `.env.local`:

```sh
NEXT_PUBLIC_PRIVY_APP_ID=your-privy-app-id
# NEXT_PUBLIC_PRIVY_CLIENT_ID=your-optional-privy-client-id
TRELP_CHAIN_ID=31337
TRELP_VAULT_ADDRESS=0x...
TRELP_DEPLOYMENT_BLOCK=the-vault-creation-block
TRELP_RPC_URL=http://127.0.0.1:8545
TRELP_VAULT_ID=eth-usdc
```

The configured RPC chain ID is checked before any data is shown. Missing contract configuration produces an explicit setup state rather than sample financial data. `NEXT_PUBLIC_PRIVY_APP_ID` is public client configuration: when it is missing, reads remain available and transaction controls show a setup prompt.

## Run

```sh
corepack pnpm --filter @trelp/web dev
corepack pnpm --filter @trelp/web test
corepack pnpm --filter @trelp/web typecheck
corepack pnpm --filter @trelp/web test:e2e
```

Privy owns wallet connection. Contract writes use the selected Privy wallet on the configured deployment chain; no wallet address or private key is hardcoded. Ethereum, Base, Sepolia, and local Anvil chain `31337` are supported.

The transparency page at `/transparency` reads live NAV, tranche pools, coverage, position range, liquidity, costs, addresses, and the payment waterfall. Activity is reconstructed from vault logs starting at `TRELP_DEPLOYMENT_BLOCK`.
