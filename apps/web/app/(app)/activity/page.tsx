"use client";

import { useEffect, useState } from "react";
import { getVaultEvents } from "@/app/actions/protocol";
import {
  TransactionLink,
  units,
  VaultBoundary,
} from "@/components/app/protocol-ui";
import {
  AssetMark,
  Badge,
  PageHeading,
  TokenAmount,
  TrancheMark,
} from "@/components/app/ui";

type EventResult = Extract<
  Awaited<ReturnType<typeof getVaultEvents>>,
  { ok: true }
>;

function eventDetail(
  event: EventResult["events"][number],
  decimals: number,
  symbol: string,
) {
  const amount =
    event.args.assets ??
    event.args.shares ??
    event.args.nav ??
    event.args.shippedQuote;
  return typeof amount === "string" ? (
    <TokenAmount token={symbol}>
      {units(BigInt(amount), decimals, symbol)}
    </TokenAmount>
  ) : (
    "Protocol state change"
  );
}

export default function ActivityPage() {
  const [result, setResult] = useState<EventResult | null>(null);
  const [error, setError] = useState("");
  const [loading, setLoading] = useState(true);
  useEffect(() => {
    let live = true;
    void getVaultEvents()
      .then((next) => {
        if (!live) return;
        if (next.ok) setResult(next);
        else setError(next.error);
        setLoading(false);
      })
      .catch((failure) => {
        if (!live) return;
        setError(
          failure instanceof Error
            ? failure.message
            : "Vault activity is unavailable.",
        );
        setLoading(false);
      });
    return () => {
      live = false;
    };
  }, []);
  return (
    <VaultBoundary>
      {(vault) => (
        <main className="appPage">
          <PageHeading
            label="On-chain history"
            title="Activity"
            description="Deposits, activation, buffer calls, settlement, and redemptions emitted by the vault."
          />
          <section className="workspaceIdentity" aria-label="Activity market">
            <div>
              <AssetMark
                asset={`${vault.risky.symbol} / ${vault.quote.symbol}`}
              />
              <strong>
                {vault.risky.symbol} / {vault.quote.symbol}
              </strong>
            </div>
            <span>Live contract events</span>
          </section>
          <section className="panel">
            <div className="panelHead">
              <div>
                <h2>Vault events</h2>
                <p>Ordered by block and log position.</p>
              </div>
              <Badge tone="green">Verified logs</Badge>
            </div>
            {loading ? (
              <div className="uiEmpty" aria-live="polite">
                Reading contract events…
              </div>
            ) : error ? (
              <div className="uiEmpty">
                <h3>Activity unavailable</h3>
                <p>{error}</p>
              </div>
            ) : result && result.events.length ? (
              <div className="tableWrap">
                <table className="dataTable">
                  <thead>
                    <tr>
                      <th scope="col">Event</th>
                      <th scope="col">Value</th>
                      <th scope="col">Block</th>
                      <th scope="col">Transaction</th>
                    </tr>
                  </thead>
                  <tbody>
                    {result.events.map((event) => (
                      <tr key={event.id}>
                        <td>
                          <Badge
                            tone={
                              event.name === "Settled" ||
                              event.name === "Redeemed"
                                ? "green"
                                : "neutral"
                            }
                          >
                            {event.name}
                          </Badge>
                          {typeof event.args.isSenior === "boolean" ? (
                            <span className="eventTranche">
                              <TrancheMark
                                tranche={
                                  event.args.isSenior ? "senior" : "junior"
                                }
                              />
                              <small>
                                {event.args.isSenior ? "Senior" : "Junior"}
                              </small>
                            </span>
                          ) : (
                            <small>Vault lifecycle</small>
                          )}
                        </td>
                        <td>
                          {eventDetail(
                            event,
                            vault.quote.decimals,
                            vault.quote.symbol,
                          )}
                        </td>
                        <td>{event.blockNumber}</td>
                        <td>
                          <TransactionLink
                            hash={event.transactionHash}
                            chainId={result.chainId}
                          />
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            ) : (
              <div className="uiEmpty">
                <h3>No vault events yet</h3>
                <p>
                  The configured deployment has not emitted a supported event
                  since its deployment block.
                </p>
              </div>
            )}
          </section>
        </main>
      )}
    </VaultBoundary>
  );
}
