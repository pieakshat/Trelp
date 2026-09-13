"use client";

import Link from "next/link";
import type { CSSProperties } from "react";
import {
  AddressLink,
  chainName,
  units,
  VaultBoundary,
} from "@/components/app/protocol-ui";
import { AssetMark, Badge, TokenAmount } from "@/components/app/ui";
import { WalletButton } from "@/components/app/wallet-provider";
import {
  compactTokenAmount,
  formatWadPercent,
  phaseNames,
  tranchePools,
} from "@/lib/vault-domain";

const phaseCopy = [
  "Choose Senior or Junior and fund the epoch.",
  "Capital is deployed while coverage and range policy stay live.",
  "The position is converted back into the quote asset.",
  "The waterfall is final and claim tokens can be redeemed.",
] as const;

export default function DashboardPage() {
  return (
    <VaultBoundary>
      {(vault) => {
        const pools = tranchePools(
          vault.phase,
          vault.nav,
          vault.seniorClaim ?? vault.senior.supply,
          vault.seniorPot,
          vault.juniorPot,
        );
        const total = pools.senior + pools.junior;
        const seniorPercent =
          total === 0n ? 0 : Number((pools.senior * 10_000n) / total) / 100;
        const juniorPercent = 100 - seniorPercent;
        const compactUnits = (value: bigint) =>
          `${compactTokenAmount(value, vault.quote.decimals)} ${vault.quote.symbol}`;
        const allocationStyle = {
          "--senior": `${seniorPercent}%`,
          "--invested": "100%",
        } as CSSProperties;

        return (
          <main className="appPage dashboardPage">
            <section className="dashboardHero">
              <div className="dashboardHeroCopy">
                <div className="dashboardHeroMeta">
                  <p className="eyebrow">Live protocol workspace</p>
                  <Badge>{phaseNames[vault.phase]}</Badge>
                </div>
                <div className="dashboardAssetIdentity">
                  <AssetMark
                    asset={`${vault.risky.symbol} / ${vault.quote.symbol}`}
                  />
                  <span>
                    {vault.risky.symbol} / {vault.quote.symbol}
                  </span>
                </div>
                <h1>Your vault, at a glance.</h1>
                <p>
                  Follow capital, coverage, execution, and your claim tokens
                  from one live contract view.
                </p>
                <div className="dashboardHeroActions">
                  <Link
                    className="uiButton dashboardPrimaryAction"
                    href={`/vaults/${vault.deployment.id}`}
                  >
                    Open vault ↗
                  </Link>
                  <Link className="dashboardTextLink" href="/transparency">
                    Inspect the full model →
                  </Link>
                </div>
              </div>
              <div
                className="dashboardHeroStack"
                aria-label="Current capital stack"
                role="img"
              >
                <span style={{ width: `${seniorPercent}%` }}>
                  <small>Paid first</small>
                  <strong>Senior</strong>
                  <b>{seniorPercent.toFixed(1)}%</b>
                </span>
                <span style={{ width: `${juniorPercent}%` }}>
                  <small>First loss</small>
                  <strong>Junior</strong>
                  <b>{juniorPercent.toFixed(1)}%</b>
                </span>
              </div>
            </section>

            <section className="dashboardMetrics" aria-label="Vault summary">
              <div>
                <span>Net asset value</span>
                <strong>
                  <TokenAmount token={vault.quote.symbol}>
                    {compactUnits(vault.nav)}
                  </TokenAmount>
                </strong>
                <small>Live vault value</small>
              </div>
              <div>
                <span>Senior value</span>
                <strong>
                  <TokenAmount token={vault.quote.symbol}>
                    {compactUnits(pools.senior)}
                  </TokenAmount>
                </strong>
                <small>Payment priority</small>
              </div>
              <div>
                <span>Junior value</span>
                <strong>
                  <TokenAmount token={vault.quote.symbol}>
                    {compactUnits(pools.junior)}
                  </TokenAmount>
                </strong>
                <small>Residual capital</small>
              </div>
              <div>
                <span>Coverage</span>
                <strong>
                  {vault.coverageWad === null
                    ? "Pending"
                    : formatWadPercent(vault.coverageWad)}
                </strong>
                <small>{phaseNames[vault.phase]} phase</small>
              </div>
            </section>

            <div className="dashboardFeatureGrid">
              <section className="panel dashboardAllocation">
                <div className="panelHead">
                  <div>
                    <p className="eyebrow">Live composition</p>
                    <h2>Capital deployment</h2>
                  </div>
                  <Badge>On-chain</Badge>
                </div>
                <div className="allocationBody">
                  <div className="allocationRing" style={allocationStyle}>
                    <div>
                      <span>Total NAV</span>
                      <strong>
                        {compactTokenAmount(vault.nav, vault.quote.decimals)}
                      </strong>
                      <small>{vault.quote.symbol}</small>
                    </div>
                  </div>
                  <dl className="allocationLegend">
                    <div>
                      <dt>
                        <span className="legendDot senior" /> Senior
                      </dt>
                      <dd>{seniorPercent.toFixed(1)}%</dd>
                    </div>
                    <div>
                      <dt>
                        <span className="legendDot junior" /> Junior
                      </dt>
                      <dd>{juniorPercent.toFixed(1)}%</dd>
                    </div>
                    <div>
                      <dt>
                        <span className="legendDot cash" /> Managed position
                      </dt>
                      <dd>
                        {vault.position
                          ? units(
                              vault.position.value,
                              vault.quote.decimals,
                              vault.quote.symbol,
                            )
                          : "Not deployed"}
                      </dd>
                    </div>
                  </dl>
                </div>
              </section>

              <section className="panel dashboardLifecycle">
                <div className="panelHead">
                  <div>
                    <p className="eyebrow">State machine</p>
                    <h2>Protocol lifecycle</h2>
                  </div>
                  <Badge>{vault.phase + 1} / 4</Badge>
                </div>
                <ol className="phaseTimeline">
                  {phaseNames.map((phase, index) => (
                    <li
                      className={
                        index === vault.phase
                          ? "current"
                          : index < vault.phase
                            ? "complete"
                            : undefined
                      }
                      key={phase}
                    >
                      <span>{index < vault.phase ? "✓" : index + 1}</span>
                      <div>
                        <strong>{phase}</strong>
                        <small>{phaseCopy[index]}</small>
                      </div>
                    </li>
                  ))}
                </ol>
              </section>
            </div>

            <div className="dashboardDetailGrid">
              <section className="panel">
                <div className="panelHead">
                  <div>
                    <p className="eyebrow">Wallet position</p>
                    <h2>Your claim tokens</h2>
                  </div>
                  <Badge tone={vault.account ? "green" : "neutral"}>
                    {vault.account ? "Connected" : "Wallet needed"}
                  </Badge>
                </div>
                <div className="panelBody">
                  {vault.account ? (
                    <div className="claimCards">
                      <div>
                        <span>Senior</span>
                        <strong>
                          {units(
                            vault.account.seniorBalance,
                            vault.quote.decimals,
                            "trSNR",
                          )}
                        </strong>
                      </div>
                      <div>
                        <span>Junior</span>
                        <strong>
                          {units(
                            vault.account.juniorBalance,
                            vault.quote.decimals,
                            "trJNR",
                          )}
                        </strong>
                      </div>
                      <p>
                        Available:{" "}
                        {units(
                          vault.account.quoteBalance,
                          vault.quote.decimals,
                          vault.quote.symbol,
                        )}
                      </p>
                    </div>
                  ) : (
                    <div className="uiEmpty">
                      <h3>Connect your wallet</h3>
                      <p>Read the claim tokens held by your address.</p>
                      <WalletButton />
                    </div>
                  )}
                </div>
              </section>

              <section className="panel">
                <div className="panelHead">
                  <div>
                    <p className="eyebrow">Risk controls</p>
                    <h2>Execution health</h2>
                  </div>
                  <Badge>Live contract</Badge>
                </div>
                <div className="panelBody">
                  <dl className="dashboardFacts">
                    <div>
                      <dt>Buffer committed</dt>
                      <dd>
                        {vault.buffer.shipped
                          ? units(
                              vault.buffer.amount,
                              vault.quote.decimals,
                              vault.quote.symbol,
                            )
                          : "Not shipped"}
                      </dd>
                    </div>
                    <div>
                      <dt>Range moves</dt>
                      <dd>{vault.rebalanceCount}</dd>
                    </div>
                    <div>
                      <dt>Rebalance cost</dt>
                      <dd>
                        {units(vault.rebalanceCost, vault.quote.decimals)}
                      </dd>
                    </div>
                    <div>
                      <dt>Unwind cost</dt>
                      <dd>{units(vault.unwindCost, vault.quote.decimals)}</dd>
                    </div>
                  </dl>
                </div>
              </section>

              <section className="panel dashboardContracts">
                <div className="panelHead">
                  <div>
                    <p className="eyebrow">Verified surfaces</p>
                    <h2>Protocol contracts</h2>
                  </div>
                  <Badge>{chainName(vault.deployment.chainId)}</Badge>
                </div>
                <div className="panelBody">
                  <dl className="dashboardFacts">
                    <div>
                      <dt>Vault</dt>
                      <dd>
                        <AddressLink
                          address={vault.deployment.address}
                          chainId={vault.deployment.chainId}
                        />
                      </dd>
                    </div>
                    <div>
                      <dt>Oracle</dt>
                      <dd>
                        <AddressLink
                          address={vault.contracts.oracle}
                          chainId={vault.deployment.chainId}
                        />
                      </dd>
                    </div>
                    <div>
                      <dt>Aqua</dt>
                      <dd>
                        <AddressLink
                          address={vault.contracts.aqua}
                          chainId={vault.deployment.chainId}
                        />
                      </dd>
                    </div>
                    <div>
                      <dt>Curator</dt>
                      <dd>
                        <AddressLink
                          address={vault.contracts.curator}
                          chainId={vault.deployment.chainId}
                        />
                      </dd>
                    </div>
                  </dl>
                </div>
              </section>
            </div>
          </main>
        );
      }}
    </VaultBoundary>
  );
}
