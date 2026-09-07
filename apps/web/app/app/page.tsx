import { VaultExplorer } from "@/components/app/vault-explorer";
import { BrandMark } from "@/components/brand-mark";

const metrics = [
  ["Total value", "$1.78m", "+8.4%"],
  ["Active epochs", "02", "30 days"],
  ["Senior funded", "74%", "$1.24m"],
  ["Junior cushion", "30%", "$540k"],
] as const;

export default function AppPage() {
  return (
    <main className="appShell">
      <header className="appHeader">
        <a aria-label="Trelp landing page" className="logo" href="/">
          <BrandMark />
          <span>TRELP</span>
        </a>
        <nav aria-label="Application navigation">
          <a className="appNavActive" href="/app">
            Markets
          </a>
          <a href="#portfolio">Portfolio</a>
          <a href="#activity">Activity</a>
        </nav>
        <button className="connectButton" type="button">
          Connect wallet
        </button>
      </header>

      <div className="appContent">
        <section className="appHero">
          <div>
            <p className="appEyebrow">Protocol overview / Simulation</p>
            <h1>
              Choose your
              <br />
              <em>risk layer.</em>
            </h1>
          </div>
          <p>
            Senior claims take payment priority. Junior claims absorb first loss
            and receive the residual LP return.
          </p>
        </section>

        <section className="metricGrid" aria-label="Protocol metrics">
          {metrics.map(([label, value, detail]) => (
            <article key={label}>
              <span>{label}</span>
              <strong>{value}</strong>
              <small>{detail}</small>
            </article>
          ))}
        </section>

        <VaultExplorer />

        <aside className="simulationNotice">
          <BrandMark className="simulationMark" />
          <div>
            <strong>Simulation environment</strong>
            <p>
              Returns and liquidity are illustrative. No wallet transaction is
              enabled.
            </p>
          </div>
        </aside>
      </div>
    </main>
  );
}
