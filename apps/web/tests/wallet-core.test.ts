import assert from "node:assert/strict";
import { test } from "node:test";

const account = "0x1111111111111111111111111111111111111111";
const hash =
  "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";

test("contract writes use the selected Privy wallet as the sender", async () => {
  let subject: Record<string, unknown> = {};
  try {
    subject = (await import("../lib/wallet-core")) as Record<string, unknown>;
  } catch {
    /* The first red run proves the Privy boundary does not exist yet. */
  }
  assert.equal(typeof subject.sendPrivyTransaction, "function");
  const calls: unknown[] = [];
  const result = await (
    subject.sendPrivyTransaction as (
      provider: {
        request: (input: {
          method: string;
          params?: unknown[];
        }) => Promise<unknown>;
      },
      address: string,
      request: { chainId: number; to: string; data: string },
    ) => Promise<string>
  )(
    {
      request: async (input) => {
        calls.push(input);
        return input.method === "eth_accounts" ? [account] : hash;
      },
    },
    account,
    { chainId: 1, to: account, data: "0x1234" },
  );

  assert.equal(result, hash);
  assert.deepEqual(calls, [
    { method: "eth_accounts" },
    {
      method: "eth_sendTransaction",
      params: [{ from: account, to: account, data: "0x1234" }],
    },
  ]);
});

test("contract writes stop when the Privy wallet account changes", async () => {
  const { sendPrivyTransaction } = await import("../lib/wallet-core");
  await assert.rejects(
    sendPrivyTransaction(
      { request: async () => ["0x2222222222222222222222222222222222222222"] },
      account,
      { chainId: 1, to: account, data: "0x1234" },
    ),
    /account changed/i,
  );
});

test("confirmed Privy receipts refresh every account-dependent read", async () => {
  let subject: Record<string, unknown> = {};
  try {
    subject = (await import("../lib/wallet-core")) as Record<string, unknown>;
  } catch {
    /* The first red run proves the confirmation boundary is missing. */
  }
  assert.equal(typeof subject.waitForConfirmedReceipt, "function");
  const refreshed: string[] = [];
  const receipt = await (
    subject.waitForConfirmedReceipt as (
      provider: {
        request: (input: { method: string }) => Promise<unknown>;
      },
      transactionHash: string,
      refresh: () => Promise<void>,
    ) => Promise<{ hash: string; blockNumber: bigint; gasUsed: bigint }>
  )(
    {
      request: async ({ method }) => {
        assert.equal(method, "eth_getTransactionReceipt");
        return {
          status: "0x1",
          blockNumber: "0x2a",
          gasUsed: "0x5208",
          effectiveGasPrice: "0x3b9aca00",
        };
      },
    },
    hash,
    async () => {
      refreshed.push("vault", "wallet");
    },
  );

  assert.deepEqual(refreshed, ["vault", "wallet"]);
  assert.deepEqual(receipt, {
    hash,
    blockNumber: 42n,
    gasUsed: 21_000n,
    fee: 21_000_000_000_000n,
  });
});

test("a failed read refresh does not turn a confirmed write into a failure", async () => {
  const { waitForConfirmedReceipt } = await import("../lib/wallet-core");
  const receipt = await waitForConfirmedReceipt(
    {
      request: async () => ({
        status: "0x1",
        blockNumber: "0x2a",
        gasUsed: "0x5208",
      }),
    },
    hash,
    async () => {
      throw new Error("transport unavailable");
    },
  );
  assert.equal(receipt.hash, hash);
});

test("Privy accepts only deployment networks configured by the app", async () => {
  const { privyChain } = await import("../lib/wallet-core");
  for (const chainId of [1, 8453, 11155111, 31337])
    assert.equal(privyChain(chainId).id, chainId);
  assert.throws(() => privyChain(137));
});
