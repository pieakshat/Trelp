# Trelp web

The product UI reads one deployed `TrancheVault`, its Senior and Junior claim tokens, quote token, managed position, and vault events. Depositors approve quote tokens only when required, deposit during Subscription, and redeem claim tokens after settlement. Curator operations are sent only by the configured curator wallet when their on-chain conditions are satisfied.

## Configure a deployment

Copy the values in `.env.example` into `.env.local`:

```sh
TRELP_CHAIN_ID=31337
TRELP_VAULT_ADDRESS=0x...
TRELP_DEPLOYMENT_BLOCK=0
TRELP_RPC_URL=http://127.0.0.1:8545
TRELP_VAULT_ID=eth-usdc
```

The configured RPC chain ID is checked before any data is shown. Missing configuration produces an explicit setup state rather than sample financial data.

## Run

```sh
corepack pnpm --filter @trelp/web dev
corepack pnpm --filter @trelp/web test
corepack pnpm --filter @trelp/web typecheck
corepack pnpm --filter @trelp/web test:e2e
```

Wallet connection supports EIP-6963/EIP-1193 providers. Ethereum, Base, and Sepolia are supported; Anvil chain `31337` is accepted only by the authentication service outside production. Sign-In with Ethereum creates an HTTP-only, in-memory session. A server restart clears sessions.

The transparency page at `/transparency` reads live NAV, tranche pools, coverage, position range, liquidity, costs, addresses, and the payment waterfall. Activity is reconstructed from vault logs starting at `TRELP_DEPLOYMENT_BLOCK`.
