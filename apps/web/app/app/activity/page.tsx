export default function ActivityPage() {
  return (
    <main className="appPage">
      <div className="simpleAppPage">
        <p className="appEyebrow">Account history</p>
        <h1>Activity</h1>
        <section className="emptyState">
          <h2>No activity yet.</h2>
          <p>Your deposits, withdrawals, and settlements will appear here.</p>
          <a className="emptyStateLink" href="/app">
            Explore markets
          </a>
        </section>
      </div>
    </main>
  );
}
