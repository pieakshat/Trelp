import { formatUnits, parseUnits } from "viem";

export type VaultPhase = 0 | 1 | 2 | 3;
export type DepositStep = {
  kind: "approve" | "deposit";
  amount: bigint;
};

export const phaseNames = [
  "Subscription",
  "Active",
  "Unwinding",
  "Settled",
] as const;

export function phaseCapabilities(phase: VaultPhase) {
  return {
    canDeposit: phase === 0,
    canRedeem: phase === 3,
    canReadTerms: phase !== 0,
  };
}

export function parseTokenAmount(value: string, decimals: number) {
  const amount = value.trim();
  if (!/^\d+(\.\d+)?$/.test(amount))
    throw new Error(
      "Enter a positive amount using numbers and a decimal point.",
    );
  const units = parseUnits(amount, decimals);
  if (units <= 0n) throw new Error("Enter an amount greater than zero.");
  return units;
}

export function formatTokenAmount(value: bigint, decimals: number) {
  return formatUnits(value, decimals);
}

export function compactTokenAmount(value: bigint, decimals: number) {
  const amount = Number(formatUnits(value, decimals));
  return Number.isFinite(amount)
    ? new Intl.NumberFormat("en-US", {
        notation: "compact",
        maximumFractionDigits: 2,
      }).format(amount)
    : formatUnits(value, decimals);
}

export function formatWadPercent(value: bigint) {
  const negative = value < 0n;
  const magnitude = negative ? -value : value;
  const wad = 1_000_000_000_000_000_000n;
  const hundredths = (magnitude * 10_000n + wad / 2n) / wad;
  const whole = hundredths / 100n;
  const fraction = (hundredths % 100n).toString().padStart(2, "0");
  return `${negative ? "-" : ""}${whole}.${fraction}%`;
}

export function claimableAssets(shares: bigint, pot: bigint, supply: bigint) {
  return shares === 0n || pot === 0n || supply === 0n
    ? 0n
    : (shares * pot) / supply;
}

export function depositPlan(amount: bigint, allowance: bigint): DepositStep[] {
  return allowance < amount
    ? [
        { kind: "approve", amount },
        { kind: "deposit", amount },
      ]
    : [{ kind: "deposit", amount }];
}

export function tranchePools(
  phase: VaultPhase,
  nav: bigint,
  seniorClaim: bigint,
  seniorPot: bigint,
  juniorPot: bigint,
) {
  if (phase === 3) return { senior: seniorPot, junior: juniorPot };
  const senior = nav < seniorClaim ? nav : seniorClaim;
  return { senior, junior: nav - senior };
}
