import Link from "next/link";
export default function NotFound() {
  return (
    <main
      className="appFrame"
      style={{ display: "block", minHeight: "100svh" }}
    >
      <div className="appPage">
        <section className="panel uiEmpty">
          <p className="eyebrow">404 · Page not found</p>
          <h1>This market isn’t here</h1>
          <p>The link may have changed. Return to the configured vault.</p>
          <Link className="uiButton" href="/dashboard">
            Back to dashboard
          </Link>
        </section>
      </div>
    </main>
  );
}
