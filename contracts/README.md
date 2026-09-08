# Contracts

Protocol workspace for the tranched LP vault. Foundry, Solidity 0.8.30.

```sh
forge test --root contracts
```

> Note: `SPEC.md` §2 and §3 still describe this directory as reserved and Solidity as a non-goal.
> That is now out of date and needs a decision at the repo level.

## What is here

| File | Role |
|---|---|
| `src/libraries/SolvencyLib.sol` | Canonical accounting: `j`, senior accrual, coverage `b`, waterfall |
| `src/TrancheVault.sol` | Single-epoch state machine, subscription, the call, settlement |
| `src/TrancheToken.sol` | Transferable senior/junior claims |
| `src/interfaces/IPositionVenue.sol` | The Uniswap v4 leg, behind an interface |
| `src/interfaces/IBufferVenue.sol` | The 1inch Aqua leg (ship / dock) |
| `src/interfaces/IQuoteOracle.sol` | Valuation for the coverage signal |

`SolvencyLib` is the single source of truth for every number the product quotes. The tests pin the
build plan's worked example (j=30%, f=12%, c=1% → junior +37.7%, senior +1%) directly against the
implementation so the pitch and the settlement code cannot drift.

## Design decisions worth knowing

**One epoch per deployment.** The vault terminates in `Settled`; rolling is a new deployment. This
removes cross-epoch accounting state that nothing in the demo needs.

**No entry or exit during `Active`.** The senior coupon is only quotable against a known `j`, and
redemption at NAV mid-drawdown would let junior exit before absorbing the loss it exists to absorb.
Claims are ERC-20, so secondary trading is the exit.

**`Settling` is a distinct phase.** Every epoch ends in a forced conversion to the quote asset at a
scheduled, publicly known time. `unwindCost` records what that costs instead of leaving it outside
the reported returns.

**The senior payout is `S0 + min(S0·c, s·F)`.** The build plan's third term, a `max_rate` cap, can
never bind: `min(S0·c, s·F) ≤ S0·c` by construction, so the fixed rate already is the cap on senior
upside. `maxCouponWad` is therefore enforced as a bound on the curator's choice of `c`, not as a
term in the payout. If the intent was for senior to *participate* in a blowout month, the operator
is `max`, not `min` — and that is a different product, because `max` reintroduces exactly the quiet
month problem the split clause exists to solve.

**Degenerate epochs are rejected.** A one-sided raise, or `j` outside `[min, max]`, reverts at
activation rather than mis-quoting a structure that is not a structure.

**`donate()` is the minimal cure right.** It lifts coverage with no mid-epoch share price to argue
about. A donor recovers it only through the junior residual, so it is rational only for a
concentrated junior holder. A share-minting cure is the better product and remains open.

## What Aqua actually is, and what it changes

Read from `1inch/aqua` @ `main`. Aqua is a **shared-liquidity registry**, not a pricing VM.

- **No custody.** `ship()` writes a virtual balance (`balances[maker][app][strategyHash][token]`);
  the tokens stay in the maker's wallet. Takers `pull()` and `push()` against that wallet at fill
  time. So buffer capital shipped to Aqua is *still inside the vault* — `nav()` counts it once, from
  the vault's own balance, and must not add a venue balance on top. `test_shippedBufferStaysIn
  VaultAndIsNotDoubleCounted` pins this.
- **The call is `dock()`**, a permission revocation. Genuinely one transaction, and it cannot fail
  for liquidity reasons. The build plan §8 assumption holds.
- **`dock()` must close all tokens in a strategy.** The call is all-or-nothing per strategy; a
  partial buffer call needs two shipped strategies.
- **Strategies are immutable once shipped.** A spread or skew that depends on live coverage cannot
  be a strategy parameter. It must be read from the vault by the app at swap time — which is fine,
  because an Aqua app is ordinary Solidity (see below).
- **No coverage primitive.** Aqua has no notion of coverage. All of it is ours.

## Licensing (read before importing Aqua)

Aqua is **not** open source. It is `LicenseRef-Degensoft-Aqua-Source-1.1`, © Degensoft Ltd.

- §4 makes hackathon and prototype use free of charge.
- §3.3: code that merely *calls* Aqua through its ABI stays independent. `TrancheVault` only calls
  `ship`/`dock`, so it stays MIT.
- §3.1: a **Modification** — which the licence defines to include extending `AquaApp` or overriding
  a strategy app — must be published under Aqua-Source-1.1, with changes marked and dated, and
  requires "Powered by Aqua — © Degensoft Ltd 2025" in the repository README.

So a custom quoting app must live in its own directory under the Aqua licence, not under this
repo's MIT header, and the root README needs the attribution line before submission.

## Not built yet

- `PositionVenue` (v4): pool creation with the hook, range mint/burn/flip, `beforeAddLiquidity` gate.
- `BufferVenue` (Aqua): the concrete app, ship/dock wiring, coverage-aware pricing.
- Breaker stage 3: the keeper that converts residual risky inventory. `settle()` currently requires
  the risky leg to be flat and reverts otherwise, rather than doing an unpriced market sell inside
  the accounting step.
- TWAP oracle and breach persistence. `callBuffer()` reads a live signal today, which a single-block
  manipulation could move.

## Demo

```bash
forge test --root contracts --match-path "test/DemoPaths.t.sol" -vv
```

Five paths, one vault, one set of parameters (j=30%, c=1%/epoch cap, λ=0.7 → s=40%).

| path | senior | junior |
|---|---|---|
| 1 — flat price, f = 12% | **+1.00%** | **+37.67%** |
| 3 — −60% crash, policy **on** | **−1.24%** | −100% |
| 4 — same crash, policy **off** | **−15.44%** | −100% |

An unlevered LP would have made +12% in path 1. Path 2 shows the spread widening 0.30% → 0.62% as
coverage falls 42.9% → 20.3%. Paths 5a–5c price the buffer-placement frontier: with the buffer fully
in the pool senior loses 9.65%, at 50% out 1.77%.

Paths 3 and 4 differ by **one constructor argument** — whether the buffer's program carries the
`Extruction` target. That pairing is the pitch.

## Known holes

**The demo drives its own flow.** A fresh v4 pool with a novel hook is in no router's default set,
and `docs/PROGRAMS.md` confirms 1inch production routing uses only a predefined, security-reviewed
subset of SwapVM programs. Neither venue gets organic volume, so every fee number here comes from
scripted swaps. Say this before a judge does.

**Junior is short a knockout.** Calling the buffer crystallises junior's loss and forecloses the
rebound. Junior demand is what killed BarnBridge and Saffron, and nothing here solves it.

**The oracle is a mock.** `TwapOracle` is unbuilt: coverage reads a live mark, so a single-block
move could push the policy around. The breaker needs a TWAP and a persistence requirement.

**Settlement sells at the mark.** `liquidate()` converts leftover risky inventory through an
external venue, floored against the oracle so a permissionless call cannot be pushed through at a
bad price. Quoting the leg out over the unwind window at a widening discount — what `unwindDeadline`
is reserved for — is still unimplemented.

**Every epoch has two forced conversions**, not one: seeding the v4 position buys the risky leg
externally, and settlement sells it back.

## Unexplained

Running three full epochs in a single test function panics with an arithmetic overflow that no
trace attributes to any call. Each epoch passes in isolation, so the frontier is three tests rather
than a loop. Worked around, not root-caused.
