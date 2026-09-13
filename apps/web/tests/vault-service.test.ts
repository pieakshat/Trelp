import assert from "node:assert/strict";
import { test } from "node:test";
import type { Address } from "viem";
import { parseVaultDeployment } from "../lib/server/vault-config";
import {
  readVaultSnapshot,
  type VaultReader,
} from "../lib/server/vault-service";

const address = (digit: string) => `0x${digit.repeat(40)}` as Address;

function reader(values: Record<string, unknown>) {
  const calls: string[] = [];
  const instance: VaultReader = {
    read: async ({ functionName }) => {
      calls.push(functionName);
      if (!(functionName in values))
        throw new Error(`Unexpected read: ${functionName}`);
      return values[functionName] as never;
    },
  };
  return { calls, reader: instance };
}

const common = {
  phase: 1,
  quote: address("1"),
  risky: address("2"),
  senior: address("3"),
  junior: address("4"),
  curator: address("5"),
  positionVenue: address("6"),
  oracle: address("7"),
  aqua: address("8"),
  bufferStrategy: address("9"),
  bufferApp: address("a"),
  bufferShipped: true,
  shippedQuote: 30_000_000n,
  nav: 102_000_000n,
  seniorPot: 0n,
  juniorPot: 0n,
  unwindCost: 0n,
  rebalanceCost: 1_000_000n,
  rebalanceCount: 2,
  lastRebalanceAt: 1_100_000n,
  config: [
    10_000_000_000_000_000n,
    700_000_000_000_000_000n,
    15_000_000_000_000_000n,
    50_000_000_000_000_000n,
    600_000_000_000_000_000n,
    0n,
    100_000_000_000_000_000n,
    200_000_000_000_000_000n,
    10_000_000_000_000_000n,
    [0n, 0n, 0n, 0n, 0n, 0n],
    1_000_000n,
    2_592_000n,
    86_400n,
    86_400n,
    21_600n,
  ],
  symbol: "USDC",
  decimals: 6,
  balanceOf: 8_000_000n,
  totalSupply: 100_000_000n,
  allowance: 3_000_000n,
  terms: [
    70_000_000n,
    30_000_000n,
    10_000_000_000_000_000n,
    400_000_000_000_000_000n,
    1_000_000n,
    2_592_000n,
  ],
  seniorClaim: 70_500_000n,
  coverageWad: 446_808_510_638_297_872n,
  juniorShareWad: 300_000_000_000_000_000n,
  valueInQuote: 70_000_000n,
  tickLower: -120,
  tickUpper: 120,
  liquidity: 99n,
};

test("active vault reads ABI state and connected-wallet balances", async () => {
  const fake = reader(common);
  const snapshot = await readVaultSnapshot(
    fake.reader,
    {
      id: "eth-usdc-30d",
      address: address("b"),
      chainId: 11155111,
      deploymentBlock: 123n,
    },
    address("c"),
  );

  assert.equal(snapshot.phase, 1);
  assert.equal(snapshot.nav, 102_000_000n);
  assert.equal(snapshot.terms?.juniorPrincipal, 30_000_000n);
  assert.equal(snapshot.account?.quoteBalance, 8_000_000n);
  assert.equal(snapshot.account?.allowance, 3_000_000n);
  assert.equal(snapshot.position?.tickLower, -120);
  assert.equal(snapshot.config.rebalanceCooldown, 21_600n);
  assert.ok(fake.calls.includes("coverageWad"));
});

test("subscription skips terms-derived calls that revert before activation", async () => {
  const fake = reader({ ...common, phase: 0 });
  const snapshot = await readVaultSnapshot(fake.reader, {
    id: "eth-usdc-30d",
    address: address("b"),
    chainId: 11155111,
    deploymentBlock: 123n,
  });

  assert.equal(snapshot.terms, null);
  assert.equal(snapshot.coverageWad, null);
  assert.equal(snapshot.account, null);
  assert.equal(fake.calls.includes("terms"), false);
  assert.equal(fake.calls.includes("coverageWad"), false);
});

test("settled vault uses frozen supplies and tolerates a cancelled epoch", async () => {
  const fake = reader({
    ...common,
    phase: 3,
    terms: [0n, 0n, 0n, 0n, 0n, 0n],
    seniorSupplyAtSettlement: 70_000_000n,
    juniorSupplyAtSettlement: 30_000_000n,
  });
  const snapshot = await readVaultSnapshot(fake.reader, {
    id: "cancelled",
    address: address("b"),
    chainId: 31337,
    deploymentBlock: 1n,
  });

  assert.equal(snapshot.senior.supply, 70_000_000n);
  assert.equal(snapshot.junior.supply, 30_000_000n);
  assert.equal(snapshot.coverageWad, null);
  assert.equal(fake.calls.includes("seniorClaim"), false);
});

test("deployment configuration rejects partial or malformed chain data", () => {
  assert.equal(parseVaultDeployment({}), null);
  assert.deepEqual(
    parseVaultDeployment({
      TRELP_CHAIN_ID: "11155111",
      TRELP_VAULT_ADDRESS: address("b"),
      TRELP_DEPLOYMENT_BLOCK: "123",
      TRELP_RPC_URL: "https://rpc.example",
    }),
    {
      deployment: {
        id: "vault",
        address: "0xbBbBBBBbbBBBbbbBbbBbbbbBBbBbbbbBbBbbBBbB",
        chainId: 11155111,
        deploymentBlock: 123n,
      },
      rpcUrl: "https://rpc.example/",
      logsRpcUrl: "https://rpc.example/",
    },
  );
  assert.equal(
    parseVaultDeployment({
      TRELP_CHAIN_ID: "11155111",
      TRELP_VAULT_ADDRESS: address("b"),
      TRELP_DEPLOYMENT_BLOCK: "123",
      TRELP_RPC_URL: "https://rpc.example",
      TRELP_LOGS_RPC_URL: "https://logs.example",
    })?.logsRpcUrl,
    "https://logs.example/",
  );
  assert.throws(() =>
    parseVaultDeployment({
      TRELP_CHAIN_ID: "11155111",
      TRELP_VAULT_ADDRESS: address("b"),
    }),
  );
});
