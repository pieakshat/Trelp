"use client";

import type { ReactNode } from "react";
import { compactTokenAmount } from "@/lib/vault-domain";
import { type LiveVaultSnapshot, useVaultStore } from "@/stores/vault-store";
import { explorerUrl } from "./wallet-provider";

export function units(value: bigint, decimals: number, symbol?: string) {
  const label = compactTokenAmount(value, decimals);
  return symbol ? `${label} ${symbol}` : label;
}

export function signedUnits(value: bigint, decimals: number, symbol: string) {
  const sign = value > 0n ? "+" : "";
  return `${sign}${units(value, decimals)} ${symbol}`;
}

export function chainName(chainId: number) {
  return chainId === 31337
    ? "Local"
    : chainId === 1
      ? "Ethereum"
      : chainId === 8453
        ? "Base"
        : chainId === 11155111
          ? "Sepolia"
          : `Chain ${chainId}`;
}

export function AddressLink({
  address,
  chainId,
}: {
  address: string;
  chainId: number;
}) {
  const href = explorerUrl(address, chainId);
  const label = `${address.slice(0, 6)}…${address.slice(-4)}`;
  return href ? (
    <a className="contractLink" href={href} rel="noreferrer" target="_blank">
      {label} ↗
    </a>
  ) : (
    <code>{label}</code>
  );
}

export function TransactionLink({
  hash,
  chainId,
}: {
  hash: string;
  chainId: number;
}) {
  const href = explorerUrl(hash, chainId, "tx");
  const label = `${hash.slice(0, 6)}…${hash.slice(-4)}`;
  return href ? (
    <a className="contractLink" href={href} rel="noreferrer" target="_blank">
      {label} ↗
    </a>
  ) : (
    <code>{label}</code>
  );
}

export function VaultBoundary({
  children,
}: {
  children: (snapshot: LiveVaultSnapshot) => ReactNode;
}) {
  const snapshot = useVaultStore((state) => state.snapshot);
  const status = useVaultStore((state) => state.status);
  const error = useVaultStore((state) => state.error);
  const refresh = useVaultStore((state) => state.refresh);
  if (snapshot) return children(snapshot);
  return (
    <main className="appPage">
      <section className="panel uiEmpty liveStatePanel" aria-live="polite">
        <p className="eyebrow">Live vault</p>
        <h1>
          {status === "not_configured"
            ? "Deployment configuration required"
            : status === "error"
              ? "Vault data unavailable"
              : "Reading the vault…"}
        </h1>
        <p>
          {error ||
            "Trelp is reading the configured contract and token balances."}
        </p>
        {status === "error" ? (
          <button
            className="uiButton"
            onClick={() => void refresh()}
            type="button"
          >
            Retry read
          </button>
        ) : null}
      </section>
    </main>
  );
}
