"use client";

import { useState } from "react";
import { Badge, PageHeading } from "@/components/app/ui";
import {
  nativeBalanceLabel,
  networkName,
  useWallet,
  WalletButton,
} from "@/components/app/wallet-provider";
import { BrandMark } from "@/components/brand-mark";
import { useAppStore } from "@/stores/app-store";

const trancheOptions = [
  { label: "All tranches", value: "all" as const },
  { label: "Senior", value: "senior" as const },
  { label: "Junior", value: "junior" as const },
];

export default function SettingsPage() {
  const preferences = useAppStore((state) => state.preferences);
  const setPreferences = useAppStore((state) => state.setPreferences);
  const wallet = useWallet();
  const [message, setMessage] = useState("");
  const address = wallet.connectedAddress;
  const update = (next: Partial<typeof preferences>) => {
    setPreferences({ ...preferences, ...next });
    setMessage("Preferences saved in this browser.");
  };
  return (
    <main className="appPage">
      <PageHeading
        action={<BrandMark className="settingsBrandMark" />}
        description="Control local display preferences and your wallet connection."
        label="Preferences"
        title="Settings"
      />
      <section className="panel">
        <div className="panelHead">
          <div>
            <h2>Display</h2>
            <p>These settings never change protocol state.</p>
          </div>
          <Badge>Local</Badge>
        </div>
        <div className="panelBody">
          <label className="checkRow">
            <input
              checked={preferences.compact}
              onChange={(event) => update({ compact: event.target.checked })}
              type="checkbox"
            />
            <span>
              <strong>Compact tables</strong>
              <small>Use tighter rows for vault and activity data.</small>
            </span>
          </label>
          <label className="checkRow">
            <input
              checked={preferences.hideBalances}
              onChange={(event) =>
                update({ hideBalances: event.target.checked })
              }
              type="checkbox"
            />
            <span>
              <strong>Hide wallet balances</strong>
              <small>Mask account-specific amounts across the app.</small>
            </span>
          </label>
          <fieldset className="field">
            <legend>Default tranche filter</legend>
            <div className="segmented">
              {trancheOptions.map((option) => (
                <button
                  aria-pressed={preferences.defaultTranche === option.value}
                  className={
                    preferences.defaultTranche === option.value
                      ? "selected"
                      : undefined
                  }
                  key={option.value}
                  onClick={() => update({ defaultTranche: option.value })}
                  type="button"
                >
                  {option.label}
                </button>
              ))}
            </div>
          </fieldset>
          {message ? (
            <p className="uiSuccess" role="status">
              {message}
            </p>
          ) : null}
        </div>
      </section>
      <section className="panel sectionGap">
        <div className="panelHead">
          <div>
            <h2>Connected wallet</h2>
            <p>
              The account used for deposits, claim balances, and redemption.
            </p>
          </div>
          <Badge tone={address ? "green" : "neutral"}>
            {address ? "Connected" : "Optional"}
          </Badge>
        </div>
        <div className="panelBody">
          {address ? (
            <dl className="termList">
              <div>
                <dt>Address</dt>
                <dd
                  title={address}
                >{`${address.slice(0, 6)}…${address.slice(-4)}`}</dd>
              </div>
              <div>
                <dt>Network</dt>
                <dd>{networkName(wallet.chainId)}</dd>
              </div>
              <div>
                <dt>Native balance</dt>
                <dd>
                  {wallet.balanceLoading
                    ? "Refreshing…"
                    : nativeBalanceLabel(
                        wallet.nativeBalance,
                        preferences.hideBalances,
                      )}
                </dd>
              </div>
            </dl>
          ) : (
            <div className="uiNotice">
              Connect only when you want to deposit or view your claim tokens.
            </div>
          )}
          {wallet.error || wallet.balanceError ? (
            <p className="uiError" role="alert">
              {wallet.error || wallet.balanceError}
            </p>
          ) : null}
          <div className="dialogActions">
            <WalletButton />
            {address ? (
              <button
                className="uiButton secondary"
                onClick={() => void wallet.disconnect()}
                type="button"
              >
                Disconnect
              </button>
            ) : null}
          </div>
        </div>
      </section>
    </main>
  );
}
