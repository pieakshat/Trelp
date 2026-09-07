export default function SettingsPage() {
  return (
    <main className="appPage">
      <div className="simpleAppPage">
        <p className="appEyebrow">Preferences</p>
        <h1>Settings</h1>
        <section className="settingsList">
          <div>
            <span className="settingsLabel">Network</span>
            <strong>Ethereum</strong>
          </div>
          <div>
            <span className="settingsLabel">Currency</span>
            <strong>USD</strong>
          </div>
          <div>
            <span className="settingsLabel">Wallet</span>
            <strong>Not connected</strong>
          </div>
        </section>
      </div>
    </main>
  );
}
