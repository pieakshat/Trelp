import assert from "node:assert/strict";
import { test } from "node:test";
import { buildCapitalHistory, buildRangeBars } from "../lib/chart-data";

test("capital history reconstructs tranche balances from ordered ABI events", () => {
  const points = buildCapitalHistory([
    {
      name: "Redeemed",
      blockNumber: "5",
      args: { assets: "20", isSenior: false },
    },
    {
      name: "Deposited",
      blockNumber: "2",
      args: { assets: "100", isSenior: true },
    },
    {
      name: "Deposited",
      blockNumber: "3",
      args: { assets: "40", isSenior: false },
    },
    {
      name: "Activated",
      blockNumber: "4",
      args: { juniorPrincipal: "50", seniorPrincipal: "110" },
    },
  ]);

  assert.deepEqual(points, [
    { block: 2, junior: 0n, senior: 100n },
    { block: 3, junior: 40n, senior: 100n },
    { block: 4, junior: 50n, senior: 110n },
    { block: 5, junior: 30n, senior: 110n },
  ]);
});

test("range bars keep reported ticks exact and distinguish the active range", () => {
  const bars = buildRangeBars(-120, 120, 9);

  assert.equal(bars.length, 9);
  assert.equal(bars[0]?.tick, -180);
  assert.equal(bars[2]?.tick, -90);
  assert.equal(bars[6]?.tick, 90);
  assert.equal(bars[8]?.tick, 180);
  assert.deepEqual(
    bars.map((bar) => bar.inRange),
    [false, false, true, true, true, true, true, false, false],
  );
});
