import Image from "next/image";
import type { ReactNode } from "react";

const tokenFiles: Record<string, string> = {
  ETH: "ethereum",
  WETH: "ethereum",
  USDC: "usdc",
  WBTC: "wbtc",
  USDT: "usdt",
};

export function PageHeading({
  label,
  title,
  description,
  action,
}: {
  label: string;
  title: string;
  description: string;
  action?: ReactNode;
}) {
  return (
    <div className="pageHeading">
      <div>
        <p className="eyebrow">{label}</p>
        <h1>{title}</h1>
        <p>{description}</p>
      </div>
      {action}
    </div>
  );
}
export function Badge({
  children,
  tone = "neutral",
}: {
  children: ReactNode;
  tone?: "neutral" | "green" | "red";
}) {
  return (
    <span
      className={`badge ${tone === "green" ? "badgeGreen" : tone === "red" ? "badgeRed" : ""}`}
    >
      {children}
    </span>
  );
}
export function Trend({
  values,
  large = false,
}: {
  values: readonly number[];
  large?: boolean;
}) {
  const min = Math.min(...values) - 1;
  const max = Math.max(...values) + 1;
  const points = values
    .map(
      (value, index) =>
        `${10 + (index * 280) / (values.length - 1)},${85 - ((value - min) / (max - min)) * 65}`,
    )
    .join(" ");
  return (
    <svg
      aria-label="Illustrative performance trend"
      role="img"
      className={large ? "trendLarge" : "trendSmall"}
      viewBox="0 0 300 100"
      preserveAspectRatio="none"
    >
      <title>Illustrative performance trend</title>
      <path
        d="M10 25H290M10 55H290M10 85H290"
        stroke="currentColor"
        strokeOpacity=".08"
      />
      <polygon
        points={`10,95 ${points} 290,95`}
        fill="currentColor"
        fillOpacity=".05"
      />
      <polyline
        points={points}
        fill="none"
        stroke="currentColor"
        strokeWidth="2"
        vectorEffect="non-scaling-stroke"
      />
    </svg>
  );
}
// Test deployments prefix symbols, so tUSDC and tWETH resolve to the same marks as USDC and WETH.
function tokenFile(symbol: string) {
  return tokenFiles[symbol] ?? tokenFiles[symbol.replace(/^t(?=[A-Z])/, "")];
}

export function AssetMark({ asset }: { asset: string }) {
  const tokens = asset.split(" / ");
  const files = tokens.map(tokenFile);
  // The mark is a fixed-width box built for overlapping coins. A symbol with no icon used to fall
  // back to text, which overflowed that box and collided with the pair name beside it.
  if (files.some((file) => !file)) return null;
  return (
    <span className="assetMark" aria-hidden="true">
      {files.map((file, index) => (
        <Image
          key={tokens[index]}
          className={index ? "assetSecondary" : undefined}
          src={`/brand/tokens/${file}.svg`}
          alt=""
          width={34}
          height={34}
        />
      ))}
    </span>
  );
}

export function TokenAmount({
  children,
  token,
}: {
  children: ReactNode;
  token: string;
}) {
  return (
    <span className="tokenAmount">
      {tokenFiles[token] ? (
        <Image
          aria-hidden="true"
          src={`/brand/tokens/${tokenFiles[token]}.svg`}
          alt=""
          width={18}
          height={18}
        />
      ) : null}
      <span>{children}</span>
    </span>
  );
}

export function TrancheMark({ tranche }: { tranche: "senior" | "junior" }) {
  return (
    <svg
      aria-hidden="true"
      className={`trancheMark ${tranche}`}
      viewBox="0 0 32 32"
    >
      <circle cx="16" cy="16" r="14" />
      {tranche === "senior" ? (
        <path d="m10 18 4 4 8-11" />
      ) : (
        <path d="M10 20 16 9l6 11m-9-5h6" />
      )}
    </svg>
  );
}

export function NetworkMark({ network }: { network: string }) {
  return (
    <span className="networkMark">
      {(network === "Ethereum" || network === "Base") && (
        <Image
          src={`/brand/tokens/${network === "Ethereum" ? "ethereum" : "base"}.svg`}
          alt=""
          width={13}
          height={13}
        />
      )}
      {network}
    </span>
  );
}
