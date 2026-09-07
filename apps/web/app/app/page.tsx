import { VaultExplorer } from "@/components/app/vault-explorer";
import { BrandMark } from "@/components/brand-mark";

const metrics = [
  ["Total deposited", "$1.78m", "Across all vaults"],
  ["Open markets", "2", "ETH / USDC"],
  ["Senior share", "74%", "$1.24m"],
  ["Loss buffer", "30%", "Funded by Junior"],
] as const;

export default function AppPage() {
  return (
    <main className="appPage">
      <div className="appContent">
        <section className="appHero">
          <div>
            <p className="appEyebrow">Vault marketplace</p>
            <h1>
              Choose your risk
              <br />
              <em>level.</em>
            </h1>
          </div>
          <p>
            Senior has lower risk and gets paid first. Junior takes the first
            loss and can earn more.
          </p>
        </section>

        <section className="choiceGuide" aria-label="Risk level guide">
          <article>
            <span className="choiceLabel">Senior</span>
            <h2>Lower risk</h2>
            <p>Senior gets paid first from the available vault value.</p>
          </article>
          <article>
            <span className="choiceLabel">Junior</span>
            <h2>More upside</h2>
            <p>
              Junior takes the first loss and receives the value that remains.
            </p>
          </article>
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
            <strong>Preview only</strong>
            <p>
              The values are examples. Wallet transactions are not available.
            </p>
          </div>
        </aside>
      </div>
    </main>
  );
}
