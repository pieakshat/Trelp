"use client";

import Link from "next/link";
import { units, VaultBoundary } from "@/components/app/protocol-ui";
import {
  AssetMark,
  Badge,
  PageHeading,
  TokenAmount,
  TrancheMark,
} from "@/components/app/ui";
import { WalletButton } from "@/components/app/wallet-provider";
import { claimableAssets, phaseNames, tranchePools } from "@/lib/vault-domain";
import { useAppStore } from "@/stores/app-store";

export default function PortfolioPage() {
  const hidden = useAppStore((state) => state.preferences.hideBalances);
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
        const seniorValue = claimableAssets(
          vault.account?.seniorBalance ?? 0n,
          pools.senior,
          vault.senior.supply,
        );
        const juniorValue = claimableAssets(
          vault.account?.juniorBalance ?? 0n,
          pools.junior,
          vault.junior.supply,
        );
        const display = (value: bigint, symbol = vault.quote.symbol) =>
          hidden ? "••••" : units(value, vault.quote.decimals, symbol);
        return (
          <main className="appPage">
            <PageHeading
              label="Your funds"
              title="Portfolio"
              description="Your position is exactly the claim tokens held by your wallet."
              action={
                <Link
                  className="uiButton secondary"
                  href={`/vaults/${vault.deployment.id}`}
                >
                  Open vault ↗
                </Link>
              }
            />
            <section
              className="workspaceIdentity"
              aria-label="Portfolio market and wallet"
            >
              <div>
                <AssetMark
                  asset={`${vault.risky.symbol} / ${vault.quote.symbol}`}
                />
                <strong>
                  {vault.risky.symbol} / {vault.quote.symbol}
                </strong>
              </div>
              {vault.account ? (
                <code>{`${vault.account.address.slice(0, 6)}…${vault.account.address.slice(-4)}`}</code>
              ) : (
                <span>Wallet not connected</span>
              )}
            </section>
            {!vault.account ? (
              <section className="panel uiEmpty">
                <h2>Connect your wallet</h2>
                <p>
                  Trelp reads Senior and Junior balances directly from their
                  ERC-20 contracts.
                </p>
                <WalletButton />
              </section>
            ) : (
              <>
                <section
                  className="metricRibbon"
                  aria-label="Portfolio summary"
                >
                  <div>
                    <span>Estimated current value</span>
                    <strong>
                      <TokenAmount token={vault.quote.symbol}>
                        {display(seniorValue + juniorValue)}
                      </TokenAmount>
                    </strong>
                  </div>
                  <div>
                    <span>Senior claim</span>
                    <strong>
                      {display(vault.account.seniorBalance, "trSNR")}
                    </strong>
                  </div>
                  <div>
                    <span>Junior claim</span>
                    <strong>
                      {display(vault.account.juniorBalance, "trJNR")}
                    </strong>
                  </div>
                  <div>
                    <span>Vault phase</span>
                    <strong>{phaseNames[vault.phase]}</strong>
                  </div>
                </section>
                <section className="panel sectionGap">
                  <div className="panelHead">
                    <div>
                      <h2>Claim-token positions</h2>
                      <p>
                        Current values are estimates until the vault settles.
                      </p>
                    </div>
                    <Badge tone={vault.phase === 3 ? "green" : "neutral"}>
                      {vault.phase === 3
                        ? "Redeemable"
                        : "Locked until settlement"}
                    </Badge>
                  </div>
                  <div className="tableWrap">
                    <table className="dataTable">
                      <thead>
                        <tr>
                          <th scope="col">Claim</th>
                          <th scope="col">Token balance</th>
                          <th scope="col">Current value</th>
                          <th scope="col">Status</th>
                          <th scope="col">
                            <span className="srOnly">Action</span>
                          </th>
                        </tr>
                      </thead>
                      <tbody>
                        {[
                          {
                            key: "senior",
                            label: "Senior",
                            balance: vault.account.seniorBalance,
                            value: seniorValue,
                          },
                          {
                            key: "junior",
                            label: "Junior",
                            balance: vault.account.juniorBalance,
                            value: juniorValue,
                          },
                        ].map((position) => (
                          <tr key={position.key}>
                            <td>
                              <span className="trancheCell">
                                <TrancheMark
                                  tranche={position.key as "senior" | "junior"}
                                />
                                <span>
                                  <strong>{position.label}</strong>
                                  <small>
                                    {position.key === "senior"
                                      ? "Payment priority"
                                      : "First loss · residual"}
                                  </small>
                                </span>
                              </span>
                            </td>
                            <td>
                              {display(
                                position.balance,
                                position.key === "senior" ? "trSNR" : "trJNR",
                              )}
                            </td>
                            <td>
                              <strong>
                                <TokenAmount token={vault.quote.symbol}>
                                  {display(position.value)}
                                </TokenAmount>
                              </strong>
                            </td>
                            <td>
                              <Badge
                                tone={
                                  vault.phase === 3 && position.balance > 0n
                                    ? "green"
                                    : "neutral"
                                }
                              >
                                {position.balance === 0n
                                  ? "No position"
                                  : vault.phase === 3
                                    ? "Ready"
                                    : "Active"}
                              </Badge>
                            </td>
                            <td>
                              {position.balance > 0n ? (
                                <Link
                                  className="rowLink"
                                  aria-label={`Open ${position.label}`}
                                  href={`/vaults/${vault.deployment.id}?tranche=${position.key}`}
                                >
                                  ↗
                                </Link>
                              ) : (
                                "—"
                              )}
                            </td>
                          </tr>
                        ))}
                      </tbody>
                    </table>
                  </div>
                </section>
              </>
            )}
          </main>
        );
      }}
    </VaultBoundary>
  );
}
