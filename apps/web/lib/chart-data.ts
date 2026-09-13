type VaultChartEvent = {
  name: string;
  blockNumber: string;
  args: Record<string, unknown>;
  logIndex?: number;
};

export type CapitalPoint = {
  block: number;
  senior: bigint;
  junior: bigint;
};

function amount(value: unknown) {
  return typeof value === "string" && /^\d+$/.test(value)
    ? BigInt(value)
    : null;
}

export function buildCapitalHistory(events: readonly VaultChartEvent[]) {
  let senior = 0n;
  let junior = 0n;
  const points: CapitalPoint[] = [];
  const ordered = [...events].sort(
    (a, b) =>
      Number(BigInt(a.blockNumber) - BigInt(b.blockNumber)) ||
      (a.logIndex ?? 0) - (b.logIndex ?? 0),
  );

  for (const event of ordered) {
    const assets = amount(event.args.assets);
    if (event.name === "Deposited" && assets !== null) {
      if (event.args.isSenior === true) senior += assets;
      if (event.args.isSenior === false) junior += assets;
    } else if (event.name === "Redeemed" && assets !== null) {
      if (event.args.isSenior === true)
        senior = assets > senior ? 0n : senior - assets;
      if (event.args.isSenior === false)
        junior = assets > junior ? 0n : junior - assets;
    } else if (event.name === "Activated") {
      senior = amount(event.args.seniorPrincipal) ?? senior;
      junior = amount(event.args.juniorPrincipal) ?? junior;
    } else if (event.name === "Settled") {
      senior = amount(event.args.seniorPot) ?? senior;
      junior = amount(event.args.juniorPot) ?? junior;
    } else {
      continue;
    }
    const point = { block: Number(BigInt(event.blockNumber)), junior, senior };
    if (points.at(-1)?.block === point.block) points[points.length - 1] = point;
    else points.push(point);
  }
  return points;
}

export function buildRangeBars(lower: number, upper: number, count = 25) {
  const start = Math.min(lower, upper);
  const end = Math.max(lower, upper);
  const spread = Math.max(1, end - start);
  const domainStart = start - spread / 4;
  const domainEnd = end + spread / 4;
  const steps = Math.max(2, count) - 1;
  return Array.from({ length: steps + 1 }, (_, index) => {
    const tick = Math.round(
      domainStart + ((domainEnd - domainStart) * index) / steps,
    );
    return { tick, inRange: tick >= start && tick <= end };
  });
}
