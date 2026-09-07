import { notFound } from "next/navigation";
import { ArrowMark, BrandMark } from "@/components/brand-mark";

const vaults = {
  "BTC-30D-S": {
    asset: "BTC / USDC",
    cushion: "25.0%",
    return: "9.20%",
    tranche: "Senior",
  },
  "ETH-30D-J": {
    asset: "ETH / USDC",
    cushion: "First loss",
    return: "31.80%",
    tranche: "Junior",
  },
  "ETH-30D-S": {
    asset: "ETH / USDC",
    cushion: "30.0%",
    return: "12.40%",
    tranche: "Senior",
  },
} as const;

type VaultId = keyof typeof vaults;

export default async function VaultPage({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  const { id } = await params;
  if (!(id in vaults)) notFound();

  const vault = vaults[id as VaultId];

  return (
    <main className="vaultDetail">
      <header className="appHeader">
        <a aria-label="Trelp landing page" className="logo" href="/">
          <BrandMark />
          <span>TRELP</span>
        </a>
        <a className="backLink" href="/app">
          ← All vaults
        </a>
        <button className="connectButton" type="button">
          Connect wallet
        </button>
      </header>

      <div className="vaultDetailBody">
        <p className="appEyebrow">Vault / {id}</p>
        <div className="vaultDetailTitle">
          <h1>
            {vault.asset}
            <br />
            <em>{vault.tranche}</em>
          </h1>
          <span className="status statusOpen">Subscription open</span>
        </div>

        <section className="vaultDetailGrid">
          <div className="vaultTerms">
            <p className="sectionIndex">[ CURRENT TERMS ]</p>
            <dl>
              <div>
                <dt>Target APY</dt>
                <dd>{vault.return}</dd>
              </div>
              <div>
                <dt>Junior cushion</dt>
                <dd>{vault.cushion}</dd>
              </div>
              <div>
                <dt>Epoch</dt>
                <dd>30 days</dd>
              </div>
              <div>
                <dt>Settlement</dt>
                <dd>USDC</dd>
              </div>
            </dl>
          </div>

          <aside className="depositCard">
            <p className="sectionIndex">[ ENTER VAULT ]</p>
            <label htmlFor="deposit">Deposit amount</label>
            <div className="amountInput">
              <input disabled id="deposit" placeholder="0.00" />
              <span>USDC</span>
            </div>
            <div className="depositSummary">
              <span>Environment</span>
              <strong>Simulation</strong>
            </div>
            <button disabled type="button">
              Connect wallet to continue <ArrowMark className="depositArrow" />
            </button>
            <p>
              Illustrative terms only. Returns are variable and capital is at
              risk.
            </p>
          </aside>
        </section>
      </div>
    </main>
  );
}
