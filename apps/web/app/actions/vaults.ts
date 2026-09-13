"use server";

import { draftSchema } from "@/lib/local-data";
import { currentSession, requestOrigin } from "@/lib/server/auth";

export async function reviewVaultDraft(input: unknown) {
  try {
    await requestOrigin();
    const session = await currentSession();
    if (!session)
      return {
        ok: false as const,
        error: "Sign in with your wallet to review a vault draft.",
      };
    const parsed = draftSchema.safeParse(input);
    if (!parsed.success)
      return {
        ok: false as const,
        error: parsed.error.issues[0]?.message ?? "Check the vault terms.",
      };
    return {
      ok: true as const,
      draft: parsed.data,
      reviewedBy: session.address,
    };
  } catch {
    return { ok: false as const, error: "The review failed. Try again." };
  }
}
