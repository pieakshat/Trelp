"use client";

import { motion } from "motion/react";
import Link from "next/link";
import { useEffect, useRef, useState } from "react";
import { getVaultEvents } from "@/app/actions/protocol";
import {
  AddressLink,
  chainName,
  signedUnits,
  units,
  VaultBoundary,
} from "@/components/app/protocol-ui";
import {
  AssetMark,
  Badge,
  PageHeading,
  TokenAmount,
  TrancheMark,
} from "@/components/app/ui";
import {
  buildCapitalHistory,
  buildRangeBars,
  type CapitalPoint,
} from "@/lib/chart-data";
import {
  compactTokenAmount,
  formatWadPercent,
  phaseNames,
  tranchePools,
} from "@/lib/vault-domain";
import type { LiveVaultSnapshot } from "@/stores/vault-store";

const WAD = 1_000_000_000_000_000_000n;
const DAY = 86_400n;
type EventResult = Extract<
  Awaited<ReturnType<typeof getVaultEvents>>,
  { ok: true }
>;

function percent(value: bigint, total: bigint) {
  return total > 0n ? Number((value * 10_000n) / total) / 100 : 0;
}

function boundedPercent(value: bigint) {
  return Math.max(0, Math.min(100, Number((value * 10_000n) / WAD) / 100));
}

function epochLabel(value: bigint) {
  const milliseconds = Number(value) * 1_000;
  return Number.isFinite(milliseconds)
    ? new Intl.DateTimeFormat("en-US", {
        day: "numeric",
        month: "short",
        timeZone: "UTC",
        year: "numeric",
      }).format(new Date(milliseconds))
    : "Not reported";
}

function durationLabel(value: bigint) {
  const days = Number(value / DAY);
  return days > 0 ? `${days} days` : `${value.toString()} seconds`;
}

function rangeLabel(value: number | null | undefined) {
  return value === null || value === undefined
    ? "Not reported"
    : value.toString();
}

function RangePlot({
  lower,
  upper,
  liquidity,
}: {
  lower: number;
  upper: number;
  liquidity: bigint | null;
}) {
  const [detail, setDetail] = useState(false);
  const [pan, setPan] = useState(0);
  const [hovered, setHovered] = useState<number | null>(null);
  const drag = useRef<{ pan: number; x: number } | null>(null);
  const start = Math.min(lower, upper);
  const end = Math.max(lower, upper);
  const spread = Math.max(1, end - start);
  const padding = detail ? spread * 0.08 : spread * 0.3;
  const domainStart = start - padding + pan;
  const domainSpread = spread + padding * 2;
  const bars = buildRangeBars(start, end, 31);
  const x = (value: number) =>
    48 + ((value - domainStart) / domainSpread) * 524;
  const move = (event: React.PointerEvent<SVGSVGElement>) => {
    if (!drag.current) return;
    const delta = ((event.clientX - drag.current.x) / 524) * domainSpread;
    setPan(Math.max(-spread, Math.min(spread, drag.current.pan - delta)));
  };

  return (
    <div className="transparencyPlotShell">
      <div
        aria-label="Range zoom"
        className="transparencyPlotControls"
        role="toolbar"
      >
        <button
          aria-pressed={!detail}
          onClick={() => setDetail(false)}
          type="button"
        >
          Fit
        </button>
        <button
          aria-pressed={detail}
          onClick={() => setDetail(true)}
          type="button"
        >
          Detail
        </button>
        <button disabled={pan === 0} onClick={() => setPan(0)} type="button">
          Reset
        </button>
      </div>
      <svg
        aria-label={`Reported liquidity range from tick ${lower} to tick ${upper}`}
        className="transparencyRangePlot"
        onDoubleClick={() => setPan(0)}
        onPointerDown={(event) => {
          drag.current = { pan, x: event.clientX };
          event.currentTarget.setPointerCapture(event.pointerId);
        }}
        onPointerMove={move}
        onPointerUp={(event) => {
          drag.current = null;
          event.currentTarget.releasePointerCapture(event.pointerId);
        }}
        role="img"
        viewBox="0 0 620 260"
      >
        <title>Drag to pan the reported liquidity range</title>
        {[70, 110, 150, 190].map((y) => (
          <path
            d={`M48 ${y}H572`}
            key={y}
            stroke="currentColor"
            strokeOpacity=".1"
          />
        ))}
        <rect
          className="rangeActiveWindow"
          height="156"
          width={Math.max(2, x(upper) - x(lower))}
          x={x(lower)}
          y="42"
        />
        {bars.map((bar, index) => {
          const barX = x(bar.tick) - 6;
          const height = bar.inRange ? 112 : 42;
          return (
            <motion.rect
              animate={{ height, y: 198 - height }}
              className={bar.inRange ? "isActive" : ""}
              initial={false}
              key={bar.tick}
              onMouseEnter={() => setHovered(index)}
              onMouseLeave={() => setHovered(null)}
              rx="2"
              width="12"
              x={barX}
            >
              <title>
                Tick {bar.tick} · {bar.inRange ? "inside" : "outside"} the
                reported range
              </title>
            </motion.rect>
          );
        })}
        <path
          className="rangeBoundary"
          d={`M${x(lower)} 35V210M${x(upper)} 35V210`}
        />
        <path
          className="rangeMidpoint"
          d={`M${x((lower + upper) / 2)} 26V205`}
        />
        <text
          className="transparencyPlotLabel"
          textAnchor="middle"
          x={x(lower)}
          y="24"
        >
          {lower}
        </text>
        <text
          className="transparencyPlotLabel"
          textAnchor="middle"
          x={x(upper)}
          y="24"
        >
          {upper}
        </text>
        <text
          className="transparencyPlotCaption"
          textAnchor="middle"
          x="120"
          y="235"
        >
          DRAG TO PAN
        </text>
        <text
          className="transparencyPlotCaption"
          textAnchor="middle"
          x="500"
          y="235"
        >
          DOUBLE-CLICK TO RESET
        </text>
        {hovered !== null && bars[hovered] ? (
          <g className="rangeTooltip">
            <rect height="34" rx="4" width="146" x="237" y="208" />
            <text textAnchor="middle" x="310" y="222">
              TICK {bars[hovered].tick}
            </text>
            <text textAnchor="middle" x="310" y="236">
              {bars[hovered].inRange
                ? `LIQUIDITY ${liquidity?.toString() ?? "NOT REPORTED"}`
                : "OUTSIDE POSITION"}
            </text>
          </g>
        ) : null}
      </svg>
    </div>
  );
}

function CapitalHistoryChart({
  points,
  decimals,
  symbol,
}: {
  points: readonly CapitalPoint[];
  decimals: number;
  symbol: string;
}) {
  const [series, setSeries] = useState<"all" | "senior" | "junior">("all");
  const [hovered, setHovered] = useState<number | null>(null);
  const [zoom, setZoom] = useState<[number, number] | null>(null);
  const drag = useRef<number | null>(null);
  const offset = zoom?.[0] ?? 0;
  const visible = zoom ? points.slice(zoom[0], zoom[1] + 1) : points;
  const divisor = 10 ** decimals;
  const values = visible.flatMap((point) => [
    Number(point.senior) / divisor,
    Number(point.junior) / divisor,
  ]);
  const maximum = Math.max(1, ...values);
  const x = (index: number) =>
    58 + (index * 526) / Math.max(1, visible.length - 1);
  const y = (value: bigint) => 198 - (Number(value) / divisor / maximum) * 138;
  const line = (key: "senior" | "junior") =>
    visible
      .map((point, index) => `${index ? "L" : "M"}${x(index)} ${y(point[key])}`)
      .join(" ");
  const area = (key: "senior" | "junior") =>
    `${line(key)} L${x(visible.length - 1)} 198 L${x(0)} 198 Z`;
  const indexAt = (event: React.PointerEvent<SVGSVGElement>) => {
    const bounds = event.currentTarget.getBoundingClientRect();
    const ratio = Math.max(
      0,
      Math.min(1, (event.clientX - bounds.left) / bounds.width),
    );
    return Math.round(ratio * Math.max(0, visible.length - 1));
  };

  if (!visible.length)
    return (
      <p className="transparencyPending">No capital events reported yet.</p>
    );

  return (
    <div className="capitalHistoryShell">
      <div
        aria-label="Capital chart series"
        className="transparencyGraphControls"
        role="toolbar"
      >
        {(["all", "senior", "junior"] as const).map((option) => (
          <button
            aria-pressed={series === option}
            key={option}
            onClick={() => setSeries(option)}
            type="button"
          >
            {option === "all"
              ? "Both tranches"
              : option === "senior"
                ? "Senior"
                : "Junior"}
          </button>
        ))}
        <button disabled={!zoom} onClick={() => setZoom(null)} type="button">
          Reset zoom
        </button>
      </div>
      <svg
        aria-label="On-chain tranche capital history by block"
        className="capitalHistoryChart"
        onDoubleClick={() => setZoom(null)}
        onPointerDown={(event) => {
          drag.current = indexAt(event);
          event.currentTarget.setPointerCapture(event.pointerId);
        }}
        onPointerMove={(event) => setHovered(indexAt(event))}
        onPointerUp={(event) => {
          const start = drag.current;
          const end = indexAt(event);
          drag.current = null;
          event.currentTarget.releasePointerCapture(event.pointerId);
          if (start !== null && Math.abs(end - start) > 0)
            setZoom([
              offset + Math.min(start, end),
              offset + Math.max(start, end),
            ]);
        }}
        onPointerLeave={() => setHovered(null)}
        role="img"
        viewBox="0 0 640 260"
      >
        <title>Drag between events to zoom. Double-click to reset.</title>
        {[60, 106, 152, 198].map((gridY, index) => (
          <g key={gridY}>
            <path d={`M58 ${gridY}H584`} />
            <text x="10" y={gridY + 4}>
              {Math.round(maximum * (1 - index / 3)).toLocaleString()}
            </text>
          </g>
        ))}
        {series !== "junior" ? (
          <motion.path
            animate={{ opacity: 1 }}
            className="capitalArea senior"
            d={area("senior")}
            initial={{ opacity: 0 }}
          />
        ) : null}
        {series !== "senior" ? (
          <motion.path
            animate={{ opacity: 1 }}
            className="capitalArea junior"
            d={area("junior")}
            initial={{ opacity: 0 }}
          />
        ) : null}
        {series !== "junior" ? (
          <path className="capitalLine senior" d={line("senior")} />
        ) : null}
        {series !== "senior" ? (
          <path className="capitalLine junior" d={line("junior")} />
        ) : null}
        {visible.map((point, index) => (
          <text
            className="capitalBlockLabel"
            key={point.block}
            textAnchor="middle"
            x={x(index)}
            y="224"
          >
            #{point.block}
          </text>
        ))}
        {hovered !== null && visible[hovered] ? (
          <g className="capitalHover">
            <path d={`M${x(hovered)} 52V204`} />
            <circle cx={x(hovered)} cy={y(visible[hovered].senior)} r="5" />
            <circle
              className="junior"
              cx={x(hovered)}
              cy={y(visible[hovered].junior)}
              r="5"
            />
          </g>
        ) : null}
      </svg>
      <div className="capitalHistoryFooter">
        <span>Drag across events to zoom · double-click to reset</span>
        {hovered !== null && visible[hovered] ? (
          <strong>
            Block {visible[hovered].block} · Senior{" "}
            {units(visible[hovered].senior, decimals, symbol)} · Junior{" "}
            {units(visible[hovered].junior, decimals, symbol)}
          </strong>
        ) : (
          <strong>{visible.length} verified capital events</strong>
        )}
      </div>
    </div>
  );
}

function DistributionGauge({
  junior,
  senior,
  focus,
  onFocus,
}: {
  junior: number;
  senior: number;
  focus: "all" | "senior" | "junior";
  onFocus: (value: "senior" | "junior") => void;
}) {
  const dragging = useRef(false);
  const selected = focus === "all" ? null : focus;
  const selectedValue = selected === "senior" ? senior : junior;
  const selectOnKey = (
    event: React.KeyboardEvent<SVGPathElement>,
    value: "senior" | "junior",
  ) => {
    if (event.key === "Enter" || event.key === " ") {
      event.preventDefault();
      onFocus(value);
    }
  };
  const selectAt = (event: React.PointerEvent<SVGSVGElement>) => {
    const bounds = event.currentTarget.getBoundingClientRect();
    onFocus(
      event.clientX < bounds.left + bounds.width / 2 ? "senior" : "junior",
    );
  };

  return (
    <aside className="transparencyDistributionGauge">
      <svg
        aria-label={`Senior ${senior}%, Junior ${junior}%. Drag across the arc to inspect a tranche.`}
        onPointerDown={(event) => {
          dragging.current = true;
          event.currentTarget.setPointerCapture(event.pointerId);
          selectAt(event);
        }}
        onPointerMove={(event) => {
          if (dragging.current) selectAt(event);
        }}
        onPointerUp={(event) => {
          dragging.current = false;
          event.currentTarget.releasePointerCapture(event.pointerId);
        }}
        role="img"
        viewBox="0 0 240 155"
      >
        <title>Current pool distribution</title>
        <path
          className="distributionGaugeBase"
          d="M30 125a90 90 0 0 1 180 0"
          pathLength="100"
        />
        <motion.path
          animate={{
            opacity: focus === "junior" ? 0.22 : 1,
            strokeWidth: focus === "senior" ? 23 : 18,
          }}
          aria-label={`Select Senior, ${senior}%`}
          className="distributionGaugeSenior"
          d="M30 125a90 90 0 0 1 180 0"
          initial={{ opacity: 0 }}
          onKeyDown={(event) => selectOnKey(event, "senior")}
          onClick={() => onFocus("senior")}
          pathLength="100"
          role="button"
          strokeDasharray={`${senior} 100`}
          tabIndex={0}
          transition={{ damping: 24, stiffness: 250, type: "spring" }}
        >
          <title>Senior: {senior}%</title>
        </motion.path>
        <motion.path
          animate={{
            opacity: focus === "senior" ? 0.22 : 1,
            strokeWidth: focus === "junior" ? 23 : 18,
          }}
          aria-label={`Select Junior, ${junior}%`}
          className="distributionGaugeJunior"
          d="M30 125a90 90 0 0 1 180 0"
          initial={{ opacity: 0 }}
          onKeyDown={(event) => selectOnKey(event, "junior")}
          onClick={() => onFocus("junior")}
          pathLength="100"
          role="button"
          strokeDasharray={`${junior} 100`}
          strokeDashoffset={`${-senior}`}
          tabIndex={0}
          transition={{ damping: 24, stiffness: 250, type: "spring" }}
        >
          <title>Junior: {junior}%</title>
        </motion.path>
        <text
          className="distributionGaugeLabel"
          textAnchor="middle"
          x="120"
          y="86"
        >
          {selected ? selected.toUpperCase() : "TOTAL ALLOCATION"}
        </text>
        <text
          className="distributionGaugeValue"
          textAnchor="middle"
          x="120"
          y="116"
        >
          {selected ? `${selectedValue}%` : "100%"}
        </text>
      </svg>
      <div className="distributionGaugeLegend">
        <button
          aria-pressed={focus === "senior"}
          onClick={() => onFocus("senior")}
          type="button"
        >
          <i className="senior" />
          Senior <strong>{senior}%</strong>
        </button>
        <button
          aria-pressed={focus === "junior"}
          onClick={() => onFocus("junior")}
          type="button"
        >
          <i className="junior" />
          Junior <strong>{junior}%</strong>
        </button>
      </div>
    </aside>
  );
}

function TransparencyContent({ vault }: { vault: LiveVaultSnapshot }) {
  const [trancheFocus, setTrancheFocus] = useState<"all" | "senior" | "junior">(
    "all",
  );
  const [capitalEvents, setCapitalEvents] = useState<EventResult["events"]>([]);
  useEffect(() => {
    let live = true;
    void getVaultEvents().then((result) => {
      if (live && result.ok) setCapitalEvents(result.events);
    });
    return () => {
      live = false;
    };
  }, []);
  const pools = tranchePools(
    vault.phase,
    vault.nav,
    vault.seniorClaim ?? vault.senior.supply,
    vault.seniorPot,
    vault.juniorPot,
  );
  const totalPool = pools.senior + pools.junior;
  const seniorShare = percent(pools.senior, totalPool);
  const juniorShare = totalPool > 0n ? 100 - seniorShare : 0;
  const coverage =
    vault.coverageWad === null ? null : boundedPercent(vault.coverageWad);
  const position = vault.position;
  const compactUnits = (value: bigint) =>
    `${compactTokenAmount(value, vault.quote.decimals)} ${vault.quote.symbol}`;
  const principalLabel = vault.terms ? "Epoch principal" : "Current supply";
  const seniorPrincipal = vault.terms?.seniorPrincipal ?? vault.senior.supply;
  const juniorPrincipal = vault.terms?.juniorPrincipal ?? vault.junior.supply;
  const tranches = [
    {
      key: "senior",
      label: "Senior",
      role: "Paid first",
      pool: pools.senior,
      principal: seniorPrincipal,
      supply: vault.senior.supply,
    },
    {
      key: "junior",
      label: "Junior",
      role: "First loss · residual",
      pool: pools.junior,
      principal: juniorPrincipal,
      supply: vault.junior.supply,
    },
  ] as const;
  const contractRows = [
    ["Core", "Tranche vault", vault.deployment.id, vault.deployment.address],
    ["Venue", "Managed position", "Vault-managed LP", position?.address],
    ["Claims", "Senior token", "trSNR", vault.senior.address],
    ["Claims", "Junior token", "trJNR", vault.junior.address],
    ["Assets", "Quote token", vault.quote.symbol, vault.quote.address],
    ["Assets", "Risky token", vault.risky.symbol, vault.risky.address],
    ["Module", "Oracle", "Price source", vault.contracts.oracle],
    ["Module", "Aqua", "Liquidity venue", vault.contracts.aqua],
    ["Module", "Buffer strategy", "Protection", vault.buffer.strategy],
    ["Module", "Buffer app", "Optional", vault.buffer.app],
    ["Authority", "Curator", "Optional manager", vault.contracts.curator],
  ] as const;

  return (
    <main className="appPage transparencyPage">
      <PageHeading
        action={
          <Link className="uiButton secondary" href="/dashboard">
            Back to markets ↗
          </Link>
        }
        description="A read-only view of the configured vault, its managed position, and the payment waterfall."
        label="On-chain transparency"
        title="Every number has an address."
      />

      <section className="panel transparencyHeroPanel">
        <div className="transparencyHeroCopy">
          <div className="transparencyHeroKicker">
            <span className="eyebrow">Live snapshot</span>
            <Badge tone={vault.phase === 3 ? "green" : "red"}>
              {phaseNames[vault.phase]}
            </Badge>
          </div>
          <h2>
            <span className="transparencyAssetIdentity">
              <AssetMark
                asset={`${vault.risky.symbol} / ${vault.quote.symbol}`}
              />
              {vault.risky.symbol} / {vault.quote.symbol}
            </span>
            <br />
            <span>
              {position
                ? "one managed position."
                : "position not yet deployed."}
            </span>
          </h2>
          <p>
            Read from {chainName(vault.deployment.chainId)} at the configured
            vault address. No depositor action is required here.
          </p>
        </div>
        <div className="transparencyHeroValue">
          <span>Vault NAV</span>
          <strong>{compactUnits(vault.nav)}</strong>
          <AddressLink
            address={vault.deployment.address}
            chainId={vault.deployment.chainId}
          />
        </div>
      </section>

      <section aria-label="Live vault metrics" className="transparencyMetrics">
        <div>
          <span>Net asset value</span>
          <strong>{compactUnits(vault.nav)}</strong>
          <small>Vault-reported NAV</small>
        </div>
        <div>
          <span>Venue value</span>
          <strong>
            {position ? compactUnits(position.value) : "Not deployed"}
          </strong>
          <small>{position ? "Position venue read" : "No venue address"}</small>
        </div>
        <div>
          <span>Coverage</span>
          <strong>
            {vault.coverageWad === null
              ? "At activation"
              : formatWadPercent(vault.coverageWad)}
          </strong>
          <small>Buffer versus senior claim</small>
        </div>
        <div>
          <span>Range moves</span>
          <strong>{vault.rebalanceCount.toString()}</strong>
          <small>Reported rebalances</small>
        </div>
      </section>

      <div className="transparencyTopGrid">
        <section className="panel transparencyPanel">
          <div className="transparencyPanelHead">
            <div>
              <p className="eyebrow">Lifecycle</p>
              <h2>Phase path</h2>
              <p>Each phase is a contract state, not a dashboard estimate.</p>
            </div>
            <Badge>{phaseNames[vault.phase]}</Badge>
          </div>
          <ol className="transparencyPhaseTrack">
            {phaseNames.map((name, index) => (
              <li
                className={
                  index === vault.phase
                    ? "isCurrent"
                    : index < vault.phase
                      ? "isComplete"
                      : ""
                }
                key={name}
              >
                <span>{String(index + 1).padStart(2, "0")}</span>
                <strong>{name}</strong>
              </li>
            ))}
          </ol>
          {vault.terms ? (
            <dl className="transparencyTerms">
              <div>
                <dt>Epoch starts</dt>
                <dd>{epochLabel(vault.terms.start)}</dd>
              </div>
              <div>
                <dt>Duration</dt>
                <dd>{durationLabel(vault.terms.duration)}</dd>
              </div>
              <div>
                <dt>Coupon cap</dt>
                <dd>{formatWadPercent(vault.terms.couponWad)}</dd>
              </div>
              <div>
                <dt>Fee split</dt>
                <dd>{formatWadPercent(vault.terms.feeSplitWad)}</dd>
              </div>
            </dl>
          ) : (
            <p className="transparencyPending">
              Terms are written when the vault activates.
            </p>
          )}
        </section>

        <section className="panel transparencyPanel transparencyHealthPanel">
          <div className="transparencyPanelHead">
            <div>
              <p className="eyebrow">Risk boundary</p>
              <h2>Protection has a number.</h2>
              <p>
                Coverage is read from the vault and can fall short of a full
                loss.
              </p>
            </div>
            <Badge tone={coverage === null ? "neutral" : "green"}>
              {coverage === null ? "Pending" : "Reported"}
            </Badge>
          </div>
          <div
            className="transparencyCoverage"
            aria-label={
              coverage === null
                ? "Coverage pending activation"
                : `Coverage ${formatWadPercent(vault.coverageWad ?? 0n)}`
            }
            role="img"
          >
            <div className="transparencyCoverageLabel">
              <span>Coverage</span>
              <strong>
                {vault.coverageWad === null
                  ? "At activation"
                  : formatWadPercent(vault.coverageWad)}
              </strong>
            </div>
            <div
              className={`transparencyCoverageTrack${coverage === null ? " isPending" : ""}`}
            >
              <span style={{ width: `${coverage ?? 0}%` }} />
            </div>
            <div className="transparencyCoverageScale">
              <span>0%</span>
              <span>100%</span>
            </div>
          </div>
          <dl className="transparencyHealthRows">
            <div>
              <dt>Buffer shipped</dt>
              <dd>
                {vault.buffer.shipped
                  ? units(
                      vault.buffer.amount,
                      vault.quote.decimals,
                      vault.quote.symbol,
                    )
                  : "Not shipped"}
              </dd>
            </div>
            <div>
              <dt>Unwind cost</dt>
              <dd>
                {units(
                  vault.unwindCost,
                  vault.quote.decimals,
                  vault.quote.symbol,
                )}
              </dd>
            </div>
            <div>
              <dt>Rebalance cost</dt>
              <dd>
                {units(
                  vault.rebalanceCost,
                  vault.quote.decimals,
                  vault.quote.symbol,
                )}
              </dd>
            </div>
          </dl>
        </section>
      </div>

      <section className="panel transparencyPanel transparencyRangePanel">
        <div className="transparencyPanelHead">
          <div>
            <p className="eyebrow">Managed position</p>
            <h2>The range is visible before the outcome.</h2>
            <p>
              Ticks and liquidity are read from the configured position venue.
            </p>
          </div>
          <Badge tone={position ? "green" : "neutral"}>
            {position ? "Venue connected" : "Not deployed"}
          </Badge>
        </div>
        {position ? (
          <div className="transparencyRangeLayout">
            <div className="transparencyRangeGraphic">
              {position.tickLower !== null &&
              position.tickLower !== undefined &&
              position.tickUpper !== null &&
              position.tickUpper !== undefined ? (
                <RangePlot
                  liquidity={position.liquidity}
                  lower={position.tickLower}
                  upper={position.tickUpper}
                />
              ) : (
                <p className="transparencyPending">
                  The venue has not reported both range ticks.
                </p>
              )}
            </div>
            <dl className="transparencyRangeStats">
              <div>
                <dt>Lower tick</dt>
                <dd>{rangeLabel(position.tickLower)}</dd>
              </div>
              <div>
                <dt>Upper tick</dt>
                <dd>{rangeLabel(position.tickUpper)}</dd>
              </div>
              <div>
                <dt>Liquidity</dt>
                <dd>
                  {position.liquidity === null ||
                  position.liquidity === undefined
                    ? "Not reported"
                    : position.liquidity.toLocaleString("en-US", {
                        maximumFractionDigits: 2,
                        notation: "compact",
                      })}
                </dd>
              </div>
              <div>
                <dt>Venue value</dt>
                <dd>
                  {units(
                    position.value,
                    vault.quote.decimals,
                    vault.quote.symbol,
                  )}
                </dd>
              </div>
            </dl>
          </div>
        ) : (
          <p className="transparencyPending transparencyRangeEmpty">
            The vault has no position venue in this phase.
          </p>
        )}
      </section>

      <section className="panel transparencyPanel transparencyCapitalPanel">
        <div className="transparencyPanelHead">
          <div>
            <p className="eyebrow">Verified capital history</p>
            <h2>Follow each tranche block by block.</h2>
            <p>
              Reconstructed only from Deposited, Activated, Settled, and
              Redeemed vault events.
            </p>
          </div>
          <Badge tone="green">ABI events</Badge>
        </div>
        <CapitalHistoryChart
          decimals={vault.quote.decimals}
          points={buildCapitalHistory(capitalEvents)}
          symbol={vault.quote.symbol}
        />
      </section>

      <section className="panel transparencyPanel transparencyEarningsPanel">
        <div className="transparencyPanelHead">
          <div>
            <p className="eyebrow">Payment waterfall</p>
            <h2>See what each tranche can claim.</h2>
            <p>
              Pool values follow the same senior-first settlement rule shown in
              the contract.
            </p>
          </div>
          <span className="transparencyStackTotal">
            <TokenAmount token={vault.quote.symbol}>
              {compactUnits(totalPool)} total pool
            </TokenAmount>
          </span>
        </div>
        <div className="transparencyDistributionLayout">
          <div className="transparencyDistributionDetails">
            <div
              aria-label="Filter payment waterfall"
              className="transparencyGraphControls"
              role="toolbar"
            >
              {(["all", "senior", "junior"] as const).map((option) => (
                <button
                  aria-pressed={trancheFocus === option}
                  key={option}
                  onClick={() => setTrancheFocus(option)}
                  type="button"
                >
                  {option === "all"
                    ? "All claims"
                    : option === "senior"
                      ? "Senior"
                      : "Junior"}
                </button>
              ))}
            </div>
            <div
              className="transparencyStack"
              aria-label={`Senior ${seniorShare}% and Junior ${juniorShare}% of current pool`}
              role="toolbar"
            >
              <button
                aria-label={`Senior: ${seniorShare}% of current pool`}
                className={`transparencyStackSenior${trancheFocus === "junior" ? " isMuted" : ""}`}
                onClick={() => setTrancheFocus("senior")}
                style={{ width: `${seniorShare}%` }}
                title={`Senior · ${units(pools.senior, vault.quote.decimals, vault.quote.symbol)}`}
                type="button"
              />
              <button
                aria-label={`Junior: ${juniorShare}% of current pool`}
                className={`transparencyStackJunior${trancheFocus === "senior" ? " isMuted" : ""}`}
                onClick={() => setTrancheFocus("junior")}
                style={{ width: `${juniorShare}%` }}
                title={`Junior · ${units(pools.junior, vault.quote.decimals, vault.quote.symbol)}`}
                type="button"
              />
            </div>
            <div className="tableWrap transparencyTrancheTable">
              <table className="dataTable">
                <thead>
                  <tr>
                    <th>Tranche</th>
                    <th>Current pool</th>
                    <th>{principalLabel}</th>
                    <th>{vault.terms ? "Earnings / loss" : "Earnings"}</th>
                    <th>Return</th>
                    <th>Token supply</th>
                  </tr>
                </thead>
                <tbody>
                  {tranches.map((tranche) => {
                    const delta = vault.terms
                      ? tranche.pool - tranche.principal
                      : null;
                    return (
                      <tr
                        className={`${trancheFocus === tranche.key ? "isSelected" : ""}${trancheFocus !== "all" && trancheFocus !== tranche.key ? " isMuted" : ""}`}
                        key={tranche.key}
                      >
                        <th scope="row">
                          <button
                            className="trancheTableButton"
                            onClick={() => setTrancheFocus(tranche.key)}
                            type="button"
                          >
                            <TrancheMark tranche={tranche.key} />
                            <span>
                              <strong>{tranche.label}</strong>
                              <small>{tranche.role}</small>
                            </span>
                          </button>
                        </th>
                        <td>
                          <strong>
                            <TokenAmount token={vault.quote.symbol}>
                              {units(
                                tranche.pool,
                                vault.quote.decimals,
                                vault.quote.symbol,
                              )}
                            </TokenAmount>
                          </strong>
                        </td>
                        <td>
                          <TokenAmount token={vault.quote.symbol}>
                            {units(
                              tranche.principal,
                              vault.quote.decimals,
                              vault.quote.symbol,
                            )}
                          </TokenAmount>
                        </td>
                        <td>
                          {delta === null ? (
                            "Terms pending"
                          ) : (
                            <TokenAmount token={vault.quote.symbol}>
                              {signedUnits(
                                delta,
                                vault.quote.decimals,
                                vault.quote.symbol,
                              )}
                            </TokenAmount>
                          )}
                        </td>
                        <td>
                          {delta === null || tranche.principal === 0n ? (
                            "Pending activation"
                          ) : (
                            <span className="returnPercent">
                              <strong>
                                {formatWadPercent(
                                  (delta * WAD) / tranche.principal,
                                )}
                              </strong>
                              <span aria-hidden="true">
                                <i
                                  style={{
                                    width: `${Math.min(100, Math.abs(Number((delta * 10_000n) / tranche.principal) / 100))}%`,
                                  }}
                                />
                              </span>
                            </span>
                          )}
                        </td>
                        <td>
                          {units(
                            tranche.supply,
                            vault.quote.decimals,
                            tranche.key === "senior" ? "trSNR" : "trJNR",
                          )}
                        </td>
                      </tr>
                    );
                  })}
                </tbody>
              </table>
            </div>
          </div>
          <DistributionGauge
            focus={trancheFocus}
            junior={juniorShare}
            onFocus={(value) => setTrancheFocus(value)}
            senior={seniorShare}
          />
        </div>
      </section>

      <section className="panel transparencyPanel transparencyContractsPanel">
        <div className="transparencyPanelHead">
          <div>
            <p className="eyebrow">Address map</p>
            <h2>One vault, connected surfaces.</h2>
            <p>Every address below is returned by the configured deployment.</p>
          </div>
          <span className="transparencyChainLabel">
            {chainName(vault.deployment.chainId)}
          </span>
        </div>
        <div className="tableWrap">
          <table className="dataTable transparencyContractsTable">
            <thead>
              <tr>
                <th>Layer</th>
                <th>Contract</th>
                <th>Role / asset</th>
                <th>Address</th>
              </tr>
            </thead>
            <tbody>
              {contractRows.map(([layer, contract, role, address]) => (
                <tr key={`${layer}-${contract}`}>
                  <td>{layer}</td>
                  <td>
                    <strong>{contract}</strong>
                  </td>
                  <td>{role}</td>
                  <td>
                    {address ? (
                      <AddressLink
                        address={address}
                        chainId={vault.deployment.chainId}
                      />
                    ) : (
                      <small>Not deployed</small>
                    )}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
        <div className="transparencyDeploymentMeta">
          <span>Deployment block</span>
          <strong>{vault.deployment.deploymentBlock.toString()}</strong>
          <span>Vault address</span>
          <AddressLink
            address={vault.deployment.address}
            chainId={vault.deployment.chainId}
          />
        </div>
      </section>

      <p className="transparencyFootnote">
        Read-only transparency surface. Values can change with the next vault
        snapshot; this page does not initiate transactions.
      </p>
    </main>
  );
}

export default function TransparencyPage() {
  return (
    <VaultBoundary>
      {(vault) => <TransparencyContent vault={vault} />}
    </VaultBoundary>
  );
}
