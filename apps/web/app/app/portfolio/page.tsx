const positions = [
  ["Deposited", "$0.00"],
  ["Current value", "$0.00"],
  ["Earned", "$0.00"],
] as const;

export default function PortfolioPage() {
  return (
    <main className="appPage">
      <div className="simpleAppPage">
        <p className="appEyebrow">Your funds</p>
        <h1>Portfolio</h1>
        <section className="summaryGrid" aria-label="Portfolio summary">
          {positions.map(([label, value]) => (
            <article key={label}>
              <span className="summaryLabel">{label}</span>
              <strong>{value}</strong>
            </article>
          ))}
        </section>
        <section className="emptyState">
          <h2>No deposits yet.</h2>
          <p>Your active and completed vaults will appear here.</p>
          <a className="emptyStateLink" href="/app">
            Explore markets
          </a>
        </section>
      </div>
    </main>
  );
}
