"use client";

import { useState } from "react";
import { encodeAbiParameters, encodeFunctionData, formatEther } from "viem";
import { trancheVaultAbi } from "@/lib/contracts";
import { dateLabel } from "@/lib/local-data";
import {
  curatorCapabilities,
  formatWadPercent,
  phaseNames,
  rebalanceTicks,
} from "@/lib/vault-domain";
import { AddressLink, TransactionLink, VaultBoundary } from "./protocol-ui";
import { AssetMark, Badge, PageHeading } from "./ui";
import {
  type ConfirmedReceipt,
  useWallet,
  WalletButton,
} from "./wallet-provider";

function transactionError(error: unknown) {
  if (
    typeof error === "object" &&
    error &&
    "code" in error &&
    error.code === 4001
  )
    return "Transaction cancelled in your wallet.";
  return error instanceof Error ? error.message : "The transaction failed.";
}

export function VaultBuilder() {
  const wallet = useWallet();
  const [lower, setLower] = useState("-120");
  const [upper, setUpper] = useState("120");
  const [busy, setBusy] = useState(false);
  const [status, setStatus] = useState("");
  const [error, setError] = useState("");
  const [receipt, setReceipt] = useState<ConfirmedReceipt | null>(null);

  return (
    <VaultBoundary>
      {(vault) => {
        const isCurator =
          !!vault.account &&
          vault.account.address.toLowerCase() ===
            vault.contracts.curator.toLowerCase();
        const capabilities = curatorCapabilities({
          phase: vault.phase,
          isCurator,
          bufferShipped: vault.buffer.shipped,
          coverageWad: vault.coverageWad,
          minRebalanceCoverageWad: vault.config.minRebalanceCoverageWad,
          lastRebalanceAt: vault.lastRebalanceAt,
          rebalanceCooldown: vault.config.rebalanceCooldown,
          blockTimestamp: vault.blockTimestamp,
        });
        const ticks = rebalanceTicks(lower, upper);

        async function submit(
          action: "callBuffer" | "rebalance",
          data: `0x${string}`,
        ) {
          setError("");
          setReceipt(null);
          try {
            setBusy(true);
            setStatus(
              `Confirm ${action === "rebalance" ? "range rebalance" : "buffer call"}…`,
            );
            const hash = await wallet.sendTransaction({
              chainId: vault.deployment.chainId,
              to: vault.deployment.address,
              data,
            });
            setStatus("Waiting for confirmation…");
            const confirmation = await wallet.waitForReceipt(hash);
            setReceipt(confirmation);
            setStatus("Transaction confirmed on-chain.");
          } catch (failure) {
            setError(transactionError(failure));
            setStatus("");
          } finally {
            setBusy(false);
          }
        }

        const roleMessage = !vault.account
          ? "Connect the configured curator wallet to operate this vault."
          : !isCurator
            ? "The connected wallet is not this vault’s curator."
            : vault.phase !== 1
              ? `Transactions unlock after Subscription when the vault enters Active. Subscription ends ${dateLabel(vault.config.subscriptionEnd)}.`
              : "Curator wallet verified. Each action remains bounded by the vault contract.";

        return (
          <main className="appPage">
            <PageHeading
              label="Contract authority"
              title="Curator operations"
              description="Operate the configured vault. Nothing here creates or edits a vault."
            />
            <section className="workspaceIdentity" aria-label="Curator market">
              <div>
                <AssetMark
                  asset={`${vault.risky.symbol} / ${vault.quote.symbol}`}
                />
                <strong>
                  {vault.risky.symbol} / {vault.quote.symbol}
                </strong>
              </div>
              <Badge tone={isCurator ? "green" : "neutral"}>
                {isCurator ? "Curator verified" : phaseNames[vault.phase]}
              </Badge>
            </section>

            <section className="panel sectionGap">
              <div className="panelHead">
                <div>
                  <h2>Authority and conditions</h2>
                  <p>{roleMessage}</p>
                </div>
                {!vault.account ? <WalletButton /> : null}
              </div>
              <div className="detailStats">
                <div>
                  <span>Immutable curator</span>
                  <strong>
                    <AddressLink
                      address={vault.contracts.curator}
                      chainId={vault.deployment.chainId}
                    />
                  </strong>
                </div>
                <div>
                  <span>Vault phase</span>
                  <strong>{phaseNames[vault.phase]}</strong>
                </div>
                <div>
                  <span>Coverage floor</span>
                  <strong>
                    {formatWadPercent(vault.config.minRebalanceCoverageWad)}
                  </strong>
                </div>
              </div>
            </section>

            <div className="detailColumns sectionGap">
              <section className="panel panelBody">
                <p className="eyebrow">Range authority</p>
                <h2>Rebalance the managed position</h2>
                <p>
                  Available only while Active, above the coverage floor and
                  after the contract cooldown.
                </p>
                <div className="formGrid sectionGap">
                  <label className="field">
                    Lower tick
                    <input
                      inputMode="numeric"
                      value={lower}
                      disabled={busy}
                      onChange={(event) => setLower(event.target.value)}
                    />
                  </label>
                  <label className="field">
                    Upper tick
                    <input
                      inputMode="numeric"
                      value={upper}
                      disabled={busy}
                      onChange={(event) => setUpper(event.target.value)}
                    />
                  </label>
                </div>
                {!ticks ? (
                  <p className="uiError">
                    Use valid ticks with lower below upper.
                  </p>
                ) : null}
                <button
                  className="uiButton fullWidth sectionGap"
                  type="button"
                  disabled={busy || !capabilities.canRebalance || !ticks}
                  onClick={() => {
                    if (!ticks) return;
                    void submit(
                      "rebalance",
                      encodeFunctionData({
                        abi: trancheVaultAbi,
                        functionName: "rebalance",
                        args: [
                          encodeAbiParameters(
                            [{ type: "int24" }, { type: "int24" }],
                            ticks,
                          ),
                        ],
                      }),
                    );
                  }}
                >
                  Rebalance range
                </button>
              </section>

              <section className="panel panelBody">
                <p className="eyebrow">Risk control</p>
                <h2>Call the loss buffer</h2>
                <p>
                  The curator may revoke the shipped buffer while the vault is
                  Active. No transaction is available when nothing is shipped.
                </p>
                <dl className="termList sectionGap">
                  <div>
                    <dt>Buffer status</dt>
                    <dd>{vault.buffer.shipped ? "Shipped" : "Not shipped"}</dd>
                  </div>
                  <div>
                    <dt>Venue wiring</dt>
                    <dd>{vault.position ? "Configured" : "Missing"}</dd>
                  </div>
                </dl>
                <button
                  className="uiButton fullWidth sectionGap"
                  type="button"
                  disabled={busy || !capabilities.canCallBuffer}
                  onClick={() =>
                    void submit(
                      "callBuffer",
                      encodeFunctionData({
                        abi: trancheVaultAbi,
                        functionName: "callBuffer",
                      }),
                    )
                  }
                >
                  Call buffer
                </button>
              </section>
            </div>

            {status ? (
              <section
                className="panel panelBody transactionReceipt sectionGap"
                aria-live="polite"
              >
                <strong>{status}</strong>
                {receipt ? (
                  <dl className="receiptGrid">
                    <div>
                      <dt>Transaction</dt>
                      <dd>
                        <TransactionLink
                          hash={receipt.hash}
                          chainId={vault.deployment.chainId}
                        />
                      </dd>
                    </div>
                    <div>
                      <dt>Block</dt>
                      <dd>{receipt.blockNumber.toLocaleString("en-US")}</dd>
                    </div>
                    <div>
                      <dt>Gas used</dt>
                      <dd>{receipt.gasUsed.toLocaleString("en-US")}</dd>
                    </div>
                    <div>
                      <dt>Fee</dt>
                      <dd>
                        {receipt.fee === null
                          ? "Unavailable"
                          : `${formatEther(receipt.fee)} ETH`}
                      </dd>
                    </div>
                  </dl>
                ) : null}
              </section>
            ) : null}
            {error ? (
              <p className="uiError" role="alert">
                {error}
              </p>
            ) : null}
          </main>
        );
      }}
    </VaultBoundary>
  );
}
