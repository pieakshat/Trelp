"use client";

import Link from "next/link";
import { useState } from "react";
import { encodeFunctionData, formatEther } from "viem";
import { erc20Abi, faucetAbi, trancheVaultAbi } from "@/lib/contracts";
import { dateLabel } from "@/lib/local-data";
import {
  claimableAssets,
  compactTokenAmount,
  depositPlan,
  formatTokenAmount,
  formatWadPercent,
  parseTokenAmount,
  phaseCapabilities,
  phaseNames,
  tranchePools,
} from "@/lib/vault-domain";
import {
  AddressLink,
  chainName,
  TransactionLink,
  units,
  VaultBoundary,
} from "./protocol-ui";
import { AssetMark, Badge } from "./ui";
import { useVaultStore } from "@/stores/vault-store";
import {
  type ConfirmedReceipt,
  useWallet,
  WalletButton,
} from "./wallet-provider";

type Tranche = "senior" | "junior";

const faucetEnabled = process.env.NEXT_PUBLIC_TRELP_FAUCET === "true";
const FAUCET_AMOUNT = "10000";

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

export function VaultDetail({
  id,
  initialTranche,
}: {
  id: string;
  initialTranche: Tranche;
}) {
  const wallet = useWallet();
  const refreshVault = useVaultStore((state) => state.refresh);
  const [tranche, setTranche] = useState<Tranche>(initialTranche);
  const [amount, setAmount] = useState("");
  const [accepted, setAccepted] = useState(false);
  const [status, setStatus] = useState("");
  const [receipt, setReceipt] = useState<ConfirmedReceipt | null>(null);
  const [error, setError] = useState("");
  const [busy, setBusy] = useState(false);

  return (
    <VaultBoundary>
      {(vault) => {
        if (id !== vault.deployment.id)
          return (
            <main className="appPage">
              <section className="panel uiEmpty">
                <h1>Vault not configured</h1>
                <p>This route does not match the configured deployment.</p>
                <Link className="uiButton" href="/dashboard">
                  Back to dashboard
                </Link>
              </section>
            </main>
          );
        const capabilities = phaseCapabilities(vault.phase);
        const pools = tranchePools(
          vault.phase,
          vault.nav,
          vault.seniorClaim ?? vault.senior.supply,
          vault.seniorPot,
          vault.juniorPot,
        );
        const selected = tranche === "senior" ? vault.senior : vault.junior;
        const shares =
          tranche === "senior"
            ? (vault.account?.seniorBalance ?? 0n)
            : (vault.account?.juniorBalance ?? 0n);
        const claimable = claimableAssets(
          shares,
          tranche === "senior" ? pools.senior : pools.junior,
          selected.supply,
        );
        const principal = vault.terms
          ? tranche === "senior"
            ? vault.terms.seniorPrincipal
            : vault.terms.juniorPrincipal
          : selected.supply;
        const total = pools.senior + pools.junior;
        const seniorPercent =
          total === 0n ? 0 : Number((pools.senior * 10_000n) / total) / 100;
        const juniorPercent = 100 - seniorPercent;
        const compactUnits = (value: bigint) =>
          `${compactTokenAmount(value, vault.quote.decimals)} ${vault.quote.symbol}`;

        async function submitDeposit() {
          setError("");
          setStatus("");
          setReceipt(null);
          try {
            if (!vault.account)
              throw new Error("Connect your wallet before depositing.");
            if (!accepted)
              throw new Error("Accept the risk notice before depositing.");
            const value = parseTokenAmount(amount, vault.quote.decimals);
            if (value > vault.account.quoteBalance)
              throw new Error(`Your ${vault.quote.symbol} balance is too low.`);
            setBusy(true);
            let confirmation: ConfirmedReceipt | null = null;
            for (const step of depositPlan(value, vault.account.allowance)) {
              const approval = step.kind === "approve";
              setStatus(
                approval
                  ? `Approve ${vault.quote.symbol} in your wallet…`
                  : `Confirm the ${tranche} deposit…`,
              );
              const hash = await wallet.sendTransaction({
                chainId: vault.deployment.chainId,
                to: approval ? vault.quote.address : vault.deployment.address,
                data: approval
                  ? encodeFunctionData({
                      abi: erc20Abi,
                      functionName: "approve",
                      args: [vault.deployment.address, value],
                    })
                  : encodeFunctionData({
                      abi: trancheVaultAbi,
                      functionName:
                        tranche === "senior"
                          ? "depositSenior"
                          : "depositJunior",
                      args: [value],
                    }),
              });
              setStatus(
                approval
                  ? "Waiting for approval confirmation…"
                  : "Waiting for deposit confirmation…",
              );
              confirmation = await wallet.waitForReceipt(hash);
            }
            setStatus("Deposit confirmed on-chain.");
            setReceipt(confirmation);
            setAmount("");
            setAccepted(false);
          } catch (failure) {
            setError(transactionError(failure));
          } finally {
            setBusy(false);
          }
        }

        async function mintTestTokens() {
          setError("");
          setStatus("");
          setReceipt(null);
          try {
            if (!vault.account)
              throw new Error("Connect your wallet before minting.");
            const value = parseTokenAmount(
              FAUCET_AMOUNT,
              vault.quote.decimals,
            );
            setBusy(true);
            setStatus(`Confirm the ${vault.quote.symbol} mint…`);
            const hash = await wallet.sendTransaction({
              chainId: vault.deployment.chainId,
              to: vault.quote.address,
              data: encodeFunctionData({
                abi: faucetAbi,
                functionName: "mint",
                args: [vault.account.address, value],
              }),
            });
            setStatus("Waiting for mint confirmation…");
            const confirmation = await wallet.waitForReceipt(hash);
            setStatus(`${FAUCET_AMOUNT} ${vault.quote.symbol} minted.`);
            setReceipt(confirmation);
            await refreshVault(vault.account.address);
          } catch (failure) {
            setError(transactionError(failure));
          } finally {
            setBusy(false);
          }
        }

        async function redeem() {
          setError("");
          setStatus("");
          setReceipt(null);
          try {
            if (!vault.account || shares === 0n)
              throw new Error("There are no claim tokens to redeem.");
            setBusy(true);
            setStatus(`Confirm the ${tranche} redemption…`);
            const hash = await wallet.sendTransaction({
              chainId: vault.deployment.chainId,
              to: vault.deployment.address,
              data: encodeFunctionData({
                abi: trancheVaultAbi,
                functionName:
                  tranche === "senior" ? "redeemSenior" : "redeemJunior",
                args: [shares],
              }),
            });
            setStatus("Waiting for redemption confirmation…");
            const confirmation = await wallet.waitForReceipt(hash);
            setStatus("Redemption confirmed on-chain.");
            setReceipt(confirmation);
          } catch (failure) {
            setError(transactionError(failure));
          } finally {
            setBusy(false);
          }
        }

        return (
          <main className="appPage vaultPage">
            <section className="vaultHero">
              <div className="vaultHeroMeta">
                <Link href="/dashboard">← Dashboard</Link>
                <Badge>{phaseNames[vault.phase]}</Badge>
              </div>
              <div className="vaultAssetIdentity">
                <AssetMark
                  asset={`${vault.risky.symbol} / ${vault.quote.symbol}`}
                />
                <span>
                  {vault.risky.symbol} / {vault.quote.symbol}
                </span>
              </div>
              <p className="eyebrow">
                {chainName(vault.deployment.chainId)} · Live vault
              </p>
              <h1>The vault.</h1>
              <p>
                Choose Senior or Junior. The same live contract manages the
                underlying position and settlement.
              </p>
              <div
                className="capitalStackGraph"
                role="img"
                aria-label={`Senior pool ${units(pools.senior, vault.quote.decimals)}, Junior pool ${units(pools.junior, vault.quote.decimals)}`}
              >
                <span
                  className="stackSenior"
                  style={{ width: `${seniorPercent}%` }}
                >
                  <small>Paid first</small>
                  <strong>Senior</strong>
                  <b>{seniorPercent.toFixed(1)}%</b>
                </span>
                <span
                  className="stackJunior"
                  style={{ width: `${juniorPercent}%` }}
                >
                  <small>First loss</small>
                  <strong>Junior</strong>
                  <b>{juniorPercent.toFixed(1)}%</b>
                </span>
              </div>
            </section>
            <div className="detailColumns">
              <div className="detailInfo">
                <section className="panel">
                  <div className="panelHead">
                    <div>
                      <h2>Live vault state</h2>
                      <p>
                        Every amount below is read from the configured
                        contracts.
                      </p>
                    </div>
                    <AddressLink
                      address={vault.deployment.address}
                      chainId={vault.deployment.chainId}
                    />
                  </div>
                  <div className="detailStats">
                    <div>
                      <span>Net asset value</span>
                      <strong>{compactUnits(vault.nav)}</strong>
                    </div>
                    <div>
                      <span>Current {tranche} value</span>
                      <strong>
                        {compactUnits(
                          tranche === "senior" ? pools.senior : pools.junior,
                        )}
                      </strong>
                    </div>
                    <div>
                      <span>Coverage</span>
                      <strong>
                        {vault.coverageWad === null
                          ? "At activation"
                          : formatWadPercent(vault.coverageWad)}
                      </strong>
                    </div>
                  </div>
                </section>
                <section className="panel">
                  <div className="panelHead">
                    <div>
                      <h2>Terms and mechanics</h2>
                      <p>Epoch terms are fixed when the vault activates.</p>
                    </div>
                  </div>
                  <div className="panelBody">
                    <dl className="termList">
                      <div>
                        <dt>{tranche} principal</dt>
                        <dd>
                          {units(
                            principal,
                            vault.quote.decimals,
                            vault.quote.symbol,
                          )}
                        </dd>
                      </div>
                      <div>
                        <dt>Senior epoch coupon cap</dt>
                        <dd>
                          {vault.terms
                            ? formatWadPercent(vault.terms.couponWad)
                            : "Set at activation"}
                        </dd>
                      </div>
                      <div>
                        <dt>Senior P&amp;L split</dt>
                        <dd>
                          {vault.terms
                            ? formatWadPercent(vault.terms.feeSplitWad)
                            : "Set at activation"}
                        </dd>
                      </div>
                      <div>
                        <dt>Epoch window</dt>
                        <dd>
                          {vault.terms
                            ? `${dateLabel(vault.terms.start)} · ${Number(vault.terms.duration) / 86_400} days`
                            : "Subscription open"}
                        </dd>
                      </div>
                      <div>
                        <dt>Claim token</dt>
                        <dd>
                          <AddressLink
                            address={selected.address}
                            chainId={vault.deployment.chainId}
                          />
                        </dd>
                      </div>
                    </dl>
                  </div>
                </section>
                <section className="panel">
                  <div className="panelHead">
                    <h2>Risk boundary</h2>
                  </div>
                  <div className="panelBody riskNotes">
                    <p>
                      <strong>Junior absorbs losses first.</strong> It can be
                      fully impaired, and sufficiently large losses can reach
                      Senior.
                    </p>
                    <p>
                      <strong>Claims are locked during the epoch.</strong>{" "}
                      Redemption opens only after settlement.
                    </p>
                    <p>
                      <strong>The vault manages execution.</strong> Range
                      changes, buffer calls, swaps, and unwind costs affect
                      final value.
                    </p>
                  </div>
                </section>
              </div>
              <aside className="depositPanel panel">
                <div className="panelHead">
                  <h2>
                    {capabilities.canDeposit
                      ? `Deposit ${vault.quote.symbol}`
                      : capabilities.canRedeem
                        ? `Redeem ${tranche}`
                        : "Position status"}
                  </h2>
                  <Badge>
                    {vault.account ? "Wallet connected" : "Wallet required"}
                  </Badge>
                </div>
                <div className="panelBody">
                  <fieldset className="trancheSwitch segmented">
                    <legend className="srOnly">Select tranche</legend>
                    {(["senior", "junior"] as const).map((key) => (
                      <button
                        key={key}
                        type="button"
                        aria-pressed={tranche === key}
                        className={tranche === key ? "selected" : undefined}
                        onClick={() => {
                          setTranche(key);
                          setError("");
                          setStatus("");
                        }}
                      >
                        {key === "senior"
                          ? "Senior · paid first"
                          : "Junior · first loss"}
                      </button>
                    ))}
                  </fieldset>
                  {!vault.account ? (
                    <>
                      <p>
                        Connect to read your quote and claim-token balances.
                      </p>
                      <WalletButton />
                    </>
                  ) : (
                    <>
                      <dl className="termList">
                        <div>
                          <dt>Available {vault.quote.symbol}</dt>
                          <dd>
                            {units(
                              vault.account.quoteBalance,
                              vault.quote.decimals,
                              vault.quote.symbol,
                            )}
                          </dd>
                        </div>
                        <div>
                          <dt>Your {tranche} claims</dt>
                          <dd>
                            {units(
                              shares,
                              vault.quote.decimals,
                              tranche === "senior" ? "trSNR" : "trJNR",
                            )}
                          </dd>
                        </div>
                        <div>
                          <dt>Current claim value</dt>
                          <dd>
                            {units(
                              claimable,
                              vault.quote.decimals,
                              vault.quote.symbol,
                            )}
                          </dd>
                        </div>
                      </dl>
                      {capabilities.canDeposit ? (
                        <>
                          <label className="field" htmlFor="deposit-amount">
                            Deposit amount
                          </label>
                          <div className="depositInput">
                            <input
                              id="deposit-amount"
                              inputMode="decimal"
                              placeholder="0"
                              value={amount}
                              disabled={busy}
                              onChange={(event) => {
                                if (/^\d*\.?\d*$/.test(event.target.value)) {
                                  setAmount(event.target.value);
                                  setError("");
                                }
                              }}
                            />
                            <span>{vault.quote.symbol}</span>
                          </div>
                          <div className="balanceLine">
                            <span>Approval is requested only when needed.</span>
                            {faucetEnabled ? (
                              <button
                                type="button"
                                disabled={busy}
                                onClick={() => void mintTestTokens()}
                              >
                                Get test {vault.quote.symbol}
                              </button>
                            ) : null}
                            <button
                              type="button"
                              disabled={busy}
                              onClick={() =>
                                setAmount(
                                  formatTokenAmount(
                                    vault.account?.quoteBalance ?? 0n,
                                    vault.quote.decimals,
                                  ),
                                )
                              }
                            >
                              Max
                            </button>
                          </div>
                          <label className="checkRow">
                            <input
                              type="checkbox"
                              checked={accepted}
                              disabled={busy}
                              onChange={(event) =>
                                setAccepted(event.target.checked)
                              }
                            />
                            <span>
                              I understand that both tranches can lose money and
                              funds cannot be redeemed before settlement.
                            </span>
                          </label>
                          <button
                            className="uiButton fullWidth"
                            type="button"
                            disabled={busy || !amount || !accepted}
                            onClick={() => void submitDeposit()}
                          >
                            {busy
                              ? "Transaction pending…"
                              : `Deposit into ${tranche}`}
                          </button>
                        </>
                      ) : capabilities.canRedeem ? (
                        <button
                          className="uiButton fullWidth"
                          type="button"
                          disabled={busy || shares === 0n}
                          onClick={() => void redeem()}
                        >
                          {busy
                            ? "Transaction pending…"
                            : `Redeem all ${tranche} claims`}
                        </button>
                      ) : (
                        <p className="uiNotice">
                          The vault is {phaseNames[vault.phase].toLowerCase()}.
                          Claims remain in your wallet until settlement.
                        </p>
                      )}
                    </>
                  )}
                  {error ? (
                    <p className="uiError" role="alert">
                      {error}
                    </p>
                  ) : null}
                  {receipt ? (
                    <div className="uiSuccess transactionReceipt" role="status">
                      <strong>{status}</strong>
                      <dl>
                        <div>
                          <dt>Transaction</dt>
                          <dd>
                            <TransactionLink
                              chainId={vault.deployment.chainId}
                              hash={receipt.hash}
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
                        {receipt.fee === null ? null : (
                          <div>
                            <dt>Network fee</dt>
                            <dd>{formatEther(receipt.fee)} ETH</dd>
                          </div>
                        )}
                      </dl>
                      {vault.phase === 0 ? (
                        <small>
                          Deposits remain in Subscription until the vault is
                          activated.
                        </small>
                      ) : null}
                    </div>
                  ) : status ? (
                    <p className="uiSuccess" role="status">
                      {status}
                    </p>
                  ) : null}
                  <p className="footnote">
                    Transactions are sent directly to the configured token and
                    vault contracts. Trelp never receives your private key.
                  </p>
                </div>
              </aside>
            </div>
          </main>
        );
      }}
    </VaultBoundary>
  );
}
