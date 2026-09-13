import assert from "node:assert/strict";
import { test } from "node:test";
import { generatePrivateKey, privateKeyToAccount } from "viem/accounts";
import { draftSchema, preferencesSchema } from "../lib/local-data";
import { AuthService } from "../lib/server/auth-core";

test("local curator drafts and preferences reject invalid records", () => {
  assert.equal(
    draftSchema.safeParse({
      name: "ETH Income",
      asset: "ETH / USDC",
      network: "Base",
      duration: 30,
      buffer: 30,
      capacity: 100_000,
      riskAccepted: true,
    }).success,
    true,
  );
  assert.equal(
    preferencesSchema.safeParse({
      hideBalances: true,
      compact: false,
      defaultTranche: "all",
    }).success,
    true,
  );
  assert.equal(draftSchema.safeParse({ name: "Bad" }).success, false);
});

test("wallet authentication verifies the signer and consumes challenges once", async () => {
  let clock = Date.now();
  const auth = new AuthService(() => clock);
  const account = privateKeyToAccount(generatePrivateKey());
  const origin = "http://localhost:3000";
  const challenge = auth.challenge(account.address, 1, origin);
  const signature = await account.signMessage({ message: challenge.message });
  const result = await auth.verify(
    challenge.token,
    challenge.message,
    signature,
    origin,
  );
  assert.equal(auth.session(result.token)?.address, account.address);
  await assert.rejects(() =>
    auth.verify(challenge.token, challenge.message, signature, origin),
  );
  auth.revoke(result.token);
  assert.equal(auth.session(result.token), null);
  const expired = auth.challenge(account.address, 1, origin);
  clock += 300_001;
  await assert.rejects(() =>
    auth.verify(expired.token, expired.message, signature, origin),
  );
  assert.throws(() => auth.challenge(account.address, 137, origin));
});
