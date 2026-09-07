export default function CreateVaultPage() {
  return (
    <main className="appPage">
      <div className="simpleAppPage">
        <p className="appEyebrow">Vault builder</p>
        <h1>Create a vault</h1>
        <p className="pageLead">
          Set the market, time, and loss buffer. Review each term before you
          publish the vault.
        </p>
        <form className="vaultForm">
          <label>
            Market
            <select defaultValue="ETH / USDC">
              <option>ETH / USDC</option>
              <option>BTC / USDC</option>
            </select>
          </label>
          <label>
            Vault length
            <select defaultValue="30 days">
              <option>14 days</option>
              <option>30 days</option>
              <option>90 days</option>
            </select>
          </label>
          <label>
            Junior loss buffer
            <div className="formInput">
              <input defaultValue="30" inputMode="decimal" />
              <span>%</span>
            </div>
          </label>
          <button disabled type="button">
            Preview vault
          </button>
          <p>This builder is a preview. It does not create a contract.</p>
        </form>
      </div>
    </main>
  );
}
