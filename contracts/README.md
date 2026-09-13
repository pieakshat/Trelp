# Contracts

Protocol workspace for the tranched LP vault. Foundry.

```sh
forge test --root contracts
```

98 tests across 11 suites. The mainnet fork suite is opt in and skips without an RPC:

```sh
MAINNET_RPC_URL=<rpc> forge test --root contracts --match-path test/fork
```

## What is here

| File | Role |
|---|---|
| `src/TrancheVault.sol` | Phases, deposits, the buffer call, settlement. The only contract holding funds |
| `src/TrancheToken.sol` | Transferable senior and junior claims |
| `src/libraries/SolvencyLib.sol` | Canonical accounting: `j`, `s`, senior accrual, coverage, waterfall |
| `src/libraries/RiskPolicy.sol` | Turns coverage into a spread and a bid gate |
| `src/libraries/RangeMath.sol` | Range composition and the bound where the position is all risky |
| `src/venues/V4PositionVenue.sol` | Holds the Uniswap v4 position, enforces the range covenant |
| `src/venues/TrancheHook.sol` | Gates liquidity, overrides the LP fee, halts one direction |
| `src/aqua/BufferStrategy.sol` | Composes the Aqua program for the standing bid |
| `src/aqua/SolvencyAdjuster.sol` | Anchors that bid to the oracle and widens it with distress |
| `src/oracles/UniswapV3TwapOracle.sol` | The mark that coverage, the breaker and the floor all read |
| `src/swappers/V3SpotSwapper.sol` | Converts between the two assets at both ends of the epoch |

Interfaces in `src/interfaces/` keep venue types out of the vault. That is load bearing, not
stylistic. See the solc split below.

`SolvencyLib` is the single source of truth for every number the product quotes. The tests pin the
worked example (`j=30%`, `f=12%`, `c=1%` gives junior +37.7%, senior +1%) against the implementation
so the pitch and the settlement code cannot drift.

## The solc split

v4-core pins solc `0.8.26` exactly. Aqua and SwapVM pin `0.8.30` exactly. **No single file can name
both venues concretely.**

This shapes the whole layout:

- The vault reaches both through hand written interfaces, so it imports neither.
- Test suites take one venue concretely and mock the other.
- `test/DeployStack.t.sol` takes the v4 side concretely and reaches Aqua through `deployCode`, which
  carries bytecode rather than types. That is the only place both run together.
- `script/Deploy.s.sol` does the same for real deployments.

`foundry.toml` scopes `via_ir` to SwapVM, Aqua, `src/aqua/`, and `src/TrancheVault.sol`, so the rest
of the project keeps fast legacy codegen builds.

## Design decisions worth knowing

**One epoch per deployment.** The vault terminates in `Settled`; rolling is a new deployment. This
removes cross epoch accounting state entirely.

**No entry or exit during `Active`.** The senior coupon is only quotable against a known `j`, and
redemption at NAV mid drawdown would let junior exit before absorbing the loss it exists to absorb.
Claims are ERC-20, so secondary trading is the exit.

**`Unwinding` is a distinct phase.** Every epoch ends in a forced conversion to the quote asset at a
scheduled, publicly known time. `unwindCost` records what that costs instead of leaving it outside
the reported returns.

**The senior payout is `S0 + min(S0*c, s*gain)`.** A separate `max_rate` cap can never bind, since
`min(S0*c, s*gain) <= S0*c` by construction. The fixed rate already is the cap on senior upside, so
`maxCouponWad` is enforced as a bound on the curator's choice of `c`, not as a term in the payout.
Using `max` instead would be a different product, because it reintroduces the quiet month problem
the split clause exists to solve.

**The claim is anchored on net profit and loss, not gross fees.** Earning spread while being
adversely selected is not income, and a gross fee split would overpay senior in exactly the epochs
where junior absorbs the loss. NAV is then sufficient and no fee oracle is needed.

**Degenerate epochs are rejected.** A one sided raise, or `j` outside `[min, max]`, reverts at
activation rather than mis-quoting a structure that is not a structure.

**Asset ordering is derived, never declared.** A pool price is currency1 per currency0, so which
bound exposes the vault to the risky asset flips with token ordering. `TrancheHook.setVenue` reads
it off the pool key and checks it against the vault's own assets. A constructor bool would invert
the halt silently, refusing the de-risking side and permitting the risk increasing one.

**Decimals need no reconciliation.** A tick already expresses token1 per token0 in raw base units,
so passing an amount in the risky asset's own units yields a value in the quote asset's own units.
`IQuoteOracle` states that unit contract, and the fork suite exercises it against real USDC at 6
decimals.

**`donate()` is the minimal cure right.** It lifts coverage with no mid epoch share price to argue
about. A donor recovers it only through the junior residual, so it is rational only for a
concentrated junior holder. A share minting cure is the better product and remains open.

## What Aqua is, and what it changes

Aqua is a shared liquidity registry, not a pricing VM.

- **No custody.** `ship()` writes a virtual balance; the tokens stay in the maker's wallet. Takers
  pull and push against that wallet at fill time. Buffer capital shipped to Aqua is still inside the
  vault, so `nav()` counts it once from the vault's own balance and must not add a venue balance on
  top. `test_shippedBufferStaysInVaultAndIsNotDoubleCounted` pins this.
- **The call is `dock()`**, a permission revocation. One transaction, and it cannot fail for
  liquidity reasons.
- **`dock()` closes every token in a strategy.** All or nothing, so a partial buffer call needs two
  shipped strategies.
- **Strategies are immutable once shipped.** A spread that depends on live coverage cannot be a
  strategy parameter. It is read from the vault at swap time through an `Extruction` target, which
  is why `SolvencyAdjuster` exists and why the official deployed SwapVM needs no redeployment.
- **No coverage primitive.** Aqua has no notion of coverage. All of it is ours.

## Scripts

| Script | Purpose |
|---|---|
| `Deploy.s.sol` | Real venues against a live chain or fork. Mines the hook, loads Aqua by artifact |
| `DeployTestnet.s.sol` | Public testnet on a compressed clock, mintable tokens, settable mark |
| `DriveTestnet.s.sol` | Steps a live testnet vault through a falling market. `STEP=fall1..4\|call\|settle` |
| `Demo.s.sol` | One full epoch on a mainnet fork, simulation only |
| `DeployDevnet.s.sol` | All mocks, for frontend work without an RPC |

Live addresses land in `deployments/`.

## Demo

```bash
forge test --root contracts --match-path "test/DemoPaths.t.sol" -vv
```

Five paths, one vault, one set of parameters (`j=30%`, `c=1%` per epoch, `lambda=0.7` giving
`s=40%`).

| Path | Senior | Junior |
|---|---|---|
| 1, flat price, f = 12% | +1.00% | +37.67% |
| 3, 60% crash, policy on | -1.24% | -100% |
| 4, same crash, policy off | -15.44% | -100% |

An unlevered LP would have made +12% in path 1. Path 2 shows the spread widening 0.30% to 0.62% as
coverage falls 42.9% to 20.3%. Paths 5a to 5c price the buffer placement frontier: with the buffer
fully in the pool senior loses 9.65%, at 50% out 1.77%.

Paths 3 and 4 differ by one constructor argument, whether the buffer's program carries the
`Extruction` target. That pairing is the pitch.

## Known holes

**Neither venue gets organic volume.** A fresh v4 pool with a novel hook is in no router's default
set, and 1inch production routing uses only a predefined, security reviewed subset of SwapVM
programs. Every fee number here comes from scripted swaps. Say this before a judge does.

**Junior is short a knockout.** Calling the buffer crystallises junior's loss and forecloses the
rebound. Junior demand is what killed BarnBridge and Saffron, and nothing here solves it.

**Senior's coupon is contingent.** It is paid from realised gain, so a flat epoch returns principal
and nothing else. A CLO style interest waterfall, paying senior from collected fees and diverting
them on a coverage breach, is the fix and is not built.

**The breaker fires on a single reading.** `UniswapV3TwapOracle` removes the single block attack on
the mark, but `callBuffer()` acts the first time coverage crosses its threshold. It should require
the breach to persist.

**No early settlement.** If junior is exhausted on day 3 of a 30 day epoch, senior rides it out.
`beginSettlement()` will not open early, so the only protection for the rest of the epoch is a vault
that has stopped quoting.

**Settlement sells at the mark.** `liquidate()` converts leftover inventory through an external
venue, floored against the oracle so a permissionless call cannot be pushed through at a bad price.
Quoting the leg out over the unwind window at a widening discount, which `unwindDeadline` is
reserved for, is unimplemented.

**Every epoch has two forced conversions**, not one. Seeding the v4 position buys the risky leg
externally, and settlement sells it back.

**Parts of `RiskPolicy` are inert.** `skewWad`, `kappaWad` and `askAllowed` are computed and read
nowhere.

## Unexplained

Running three full epochs in a single test function panics with an arithmetic overflow that no trace
attributes to any call. Each epoch passes in isolation, so the frontier is three tests rather than a
loop. Worked around, not root caused.

## Licensing

Aqua and SwapVM are source available under the Degensoft licences, not open source.

- Section 4 makes hackathon and prototype use free of charge.
- Section 3.3: code that merely calls Aqua through its ABI stays independent. The vault only calls
  `ship` and `dock` through a hand written interface, so it stays MIT.
- Section 3.1: a Modification, which the licence defines to include extending `AquaApp` or overriding
  a strategy app, must be published under the Aqua licence with changes marked and dated, and
  requires the attribution line in the repository README.

`src/aqua/` is therefore its own directory under `LicenseRef-Degensoft-SwapVM-1.1`. Everything else
in `src/` is MIT. See [src/aqua/LICENSE-NOTE.md](./src/aqua/LICENSE-NOTE.md).
