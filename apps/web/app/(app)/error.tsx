"use client";
export default function ErrorPage({ reset }: { reset: () => void }) {
  return (
    <main className="appPage">
      <section className="panel uiEmpty">
        <h1>We couldn’t load this page</h1>
        <p>Your local preferences are safe. Try loading the live data again.</p>
        <button className="uiButton" type="button" onClick={reset}>
          Try again
        </button>
      </section>
    </main>
  );
}
