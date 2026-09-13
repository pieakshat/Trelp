import assert from "node:assert/strict";
import { test } from "node:test";
import { preferencesSchema } from "../lib/local-data";

test("local preferences reject invalid records", () => {
  assert.equal(
    preferencesSchema.safeParse({
      hideBalances: true,
      compact: false,
      defaultTranche: "all",
    }).success,
    true,
  );
});
