import assert from "node:assert/strict";
import { test } from "node:test";
import {
  claimableAssets,
  compactTokenAmount,
  curatorCapabilities,
  depositPlan,
  formatTokenAmount,
  formatWadPercent,
  parseTokenAmount,
  phaseCapabilities,
  tranchePools,
} from "../lib/vault-domain";

test("curator writes stay locked until role and active-vault conditions match", () => {
  const base = {
    phase: 1 as const,
    isCurator: true,
    bufferShipped: true,
    coverageWad: 300_000_000_000_000_000n,
    minRebalanceCoverageWad: 200_000_000_000_000_000n,
    lastRebalanceAt: 100n,
    rebalanceCooldown: 50n,
    blockTimestamp: 150n,
  };
  assert.deepEqual(curatorCapabilities(base), {
    canCallBuffer: true,
    canRebalance: true,
  });
  assert.equal(curatorCapabilities({ ...base, phase: 0 }).canRebalance, false);
  assert.equal(
    curatorCapabilities({ ...base, isCurator: false }).canCallBuffer,
    false,
  );
  assert.equal(
    curatorCapabilities({ ...base, blockTimestamp: 149n }).canRebalance,
    false,
  );
  assert.equal(
    curatorCapabilities({
      ...base,
      coverageWad: 199_999_999_999_999_999n,
    }).canRebalance,
    false,
  );
});

test("dashboard token amounts use compact readable units", () => {
  assert.equal(compactTokenAmount(1_000_000_000_000n, 6), "1M");
  assert.equal(compactTokenAmount(700_000_000_000n, 6), "700K");
  assert.equal(compactTokenAmount(1_250_000_000_000n, 6), "1.25M");
  assert.equal(compactTokenAmount(0n, 6), "0");
  assert.equal(compactTokenAmount(1n, 6), "0.000001");
});

test("token amounts remain exact in quote base units", () => {
  assert.equal(parseTokenAmount("1.000001", 6), 1_000_001n);
  assert.equal(formatTokenAmount(1_000_001n, 6), "1.000001");
  assert.equal(
    formatTokenAmount(parseTokenAmount("1.000000000000000001", 18), 18),
    "1.000000000000000001",
  );
  for (const value of ["", "0", "-1", "1e6", "1,000", "0.0000001"])
    assert.throws(() => parseTokenAmount(value, 6));
});

test("signed coverage and settlement payouts preserve contract semantics", () => {
  assert.equal(formatWadPercent(0n), "0.00%");
  assert.equal(formatWadPercent(1_000_000_000_000_000_000n), "100.00%");
  assert.equal(formatWadPercent(-125_000_000_000_000_000n), "-12.50%");
  assert.equal(formatWadPercent(428_571_428_571_428_571n), "42.86%");
  assert.equal(claimableAssets(250n, 900n, 1_000n), 225n);
  assert.equal(claimableAssets(0n, 900n, 1_000n), 0n);
  assert.equal(claimableAssets(250n, 0n, 1_000n), 0n);
});

test("phase capabilities prevent invalid reads and writes", () => {
  assert.deepEqual(phaseCapabilities(0), {
    canDeposit: true,
    canRedeem: false,
    canReadTerms: false,
  });
  assert.deepEqual(phaseCapabilities(1), {
    canDeposit: false,
    canRedeem: false,
    canReadTerms: true,
  });
  assert.deepEqual(phaseCapabilities(2), {
    canDeposit: false,
    canRedeem: false,
    canReadTerms: true,
  });
  assert.deepEqual(phaseCapabilities(3), {
    canDeposit: false,
    canRedeem: true,
    canReadTerms: true,
  });
});

test("deposit planning requests only the approval the vault needs", () => {
  assert.deepEqual(depositPlan(5_000_000n, 2_000_000n), [
    { kind: "approve", amount: 5_000_000n },
    { kind: "deposit", amount: 5_000_000n },
  ]);
  assert.deepEqual(depositPlan(5_000_000n, 5_000_000n), [
    { kind: "deposit", amount: 5_000_000n },
  ]);
});

test("live and settled tranche pools follow the payment waterfall", () => {
  assert.deepEqual(tranchePools(0, 100n, 100n, 0n, 0n), {
    senior: 100n,
    junior: 0n,
  });
  assert.deepEqual(tranchePools(1, 102n, 70n, 0n, 0n), {
    senior: 70n,
    junior: 32n,
  });
  assert.deepEqual(tranchePools(1, 50n, 70n, 0n, 0n), {
    senior: 50n,
    junior: 0n,
  });
  assert.deepEqual(tranchePools(2, 50n, 70n, 0n, 0n), {
    senior: 50n,
    junior: 0n,
  });
  assert.deepEqual(tranchePools(3, 90n, 70n, 68n, 22n), {
    senior: 68n,
    junior: 22n,
  });
});
