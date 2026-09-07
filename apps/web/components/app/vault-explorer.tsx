"use client";

import {
  useVaultFilterStore,
  type VaultFilter,
} from "@/stores/vault-filter-store";

type Vault = {
  apy: string;
  asset: string;
  capacity: string;
  cushion: string;
  id: string;
  status: "Open" | "Soon";
  tranche: Exclude<VaultFilter, "all">;
};

const vaults: readonly Vault[] = [
  {
    apy: "12.40%",
    asset: "ETH / USDC",
    capacity: "$1.24m",
    cushion: "30.0%",
    id: "ETH-30D-S",
    status: "Open",
    tranche: "senior",
  },
  {
    apy: "31.80%",
    asset: "ETH / USDC",
    capacity: "$540k",
    cushion: "First loss",
    id: "ETH-30D-J",
    status: "Open",
    tranche: "junior",
  },
  {
    apy: "9.20%",
    asset: "BTC / USDC",
    capacity: "$2.10m",
    cushion: "25.0%",
    id: "BTC-30D-S",
    status: "Soon",
    tranche: "senior",
  },
];

const filters: readonly { label: string; value: VaultFilter }[] = [
  { label: "All vaults", value: "all" },
  { label: "Senior", value: "senior" },
  { label: "Junior", value: "junior" },
];

function Sparkline({ junior }: { junior: boolean }) {
  return (
    <svg aria-hidden="true" className="sparkline" viewBox="0 0 120 34">
      <path d="M1 32H119" stroke="currentColor" strokeOpacity=".18" />
      <path
        d={
          junior
            ? "M2 28 18 24 34 29 50 13 66 20 82 5 99 11 118 2"
            : "M2 25 18 23 34 22 50 19 66 17 82 15 99 12 118 10"
        }
        fill="none"
        stroke="currentColor"
        strokeWidth="2"
      />
    </svg>
  );
}

export function VaultExplorer() {
  const filter = useVaultFilterStore((state) => state.filter);
  const setFilter = useVaultFilterStore((state) => state.setFilter);
  const visibleVaults = vaults.filter(
    (vault) => filter === "all" || vault.tranche === filter,
  );

  return (
    <section className="explorer" aria-labelledby="vaults-title">
      <div className="explorerHeader">
        <div>
          <p className="appEyebrow">Live markets</p>
          <h2 id="vaults-title">Vaults</h2>
        </div>
        <fieldset className="filters">
          <legend className="srOnly">Filter vaults</legend>
          {filters.map((item) => (
            <button
              aria-pressed={filter === item.value}
              className={filter === item.value ? "filterActive" : undefined}
              key={item.value}
              onClick={() => setFilter(item.value)}
              type="button"
            >
              {item.label}
            </button>
          ))}
        </fieldset>
      </div>

      <table className="vaultTable">
        <caption className="srOnly">Available vaults</caption>
        <thead>
          <tr className="vaultRow vaultTableHead">
            <th scope="col">Market</th>
            <th scope="col">Target APY</th>
            <th scope="col">Protection</th>
            <th scope="col">Capacity</th>
            <th scope="col">30D shape</th>
            <th scope="col">Status</th>
          </tr>
        </thead>
        <tbody>
          {visibleVaults.map((vault) => (
            <tr className="vaultRow" key={vault.id}>
              <td>
                <a className="marketCell" href={`/app/vaults/${vault.id}`}>
                  <i>{vault.asset.slice(0, 1)}</i>
                  <span>
                    <strong>{vault.asset}</strong>
                    <small>{vault.tranche} · 30 days</small>
                  </span>
                </a>
              </td>
              <td className="apy">{vault.apy}</td>
              <td>{vault.cushion}</td>
              <td>{vault.capacity}</td>
              <td>
                <Sparkline junior={vault.tranche === "junior"} />
              </td>
              <td>
                <b className={`status status${vault.status}`}>{vault.status}</b>
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </section>
  );
}
