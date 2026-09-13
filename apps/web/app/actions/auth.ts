"use server";

import { cookies } from "next/headers";
import { z } from "zod";
import {
  auth,
  CHALLENGE_COOKIE,
  cookieOptions,
  currentSession,
  requestOrigin,
  SESSION_COOKIE,
} from "@/lib/server/auth";
import { AuthError } from "@/lib/server/auth-core";

const requestSchema = z.object({
  address: z.string().regex(/^0x[0-9a-fA-F]{40}$/),
  chainId: z.number().int(),
});
const signatureSchema = z.object({
  message: z.string().min(1).max(2048),
  signature: z.string().regex(/^0x[0-9a-fA-F]{130}$/),
});
function errorMessage(error: unknown) {
  return error instanceof AuthError
    ? error.message
    : "Sign-in failed. Please reconnect your wallet.";
}
export async function requestSignIn(input: unknown) {
  try {
    const origin = await requestOrigin();
    const parsed = requestSchema.safeParse(input);
    if (!parsed.success)
      return { ok: false as const, error: "Select a valid Ethereum wallet." };
    const jar = await cookies();
    auth.cancel(jar.get(CHALLENGE_COOKIE)?.value);
    const challenge = auth.challenge(
      parsed.data.address,
      parsed.data.chainId,
      origin,
    );
    jar.set(CHALLENGE_COOKIE, challenge.token, cookieOptions(origin, 300));
    return { ok: true as const, message: challenge.message };
  } catch (error) {
    return { ok: false as const, error: errorMessage(error) };
  }
}
export async function completeSignIn(input: unknown) {
  try {
    const origin = await requestOrigin();
    const parsed = signatureSchema.safeParse(input);
    if (!parsed.success)
      return {
        ok: false as const,
        error: "The wallet returned an invalid signature.",
      };
    const jar = await cookies();
    const challenge = jar.get(CHALLENGE_COOKIE)?.value;
    jar.delete(CHALLENGE_COOKIE);
    const result = await auth.verify(
      challenge ?? "",
      parsed.data.message,
      parsed.data.signature as `0x${string}`,
      origin,
    );
    auth.revoke(jar.get(SESSION_COOKIE)?.value);
    jar.set(SESSION_COOKIE, result.token, cookieOptions(origin, 8 * 60 * 60));
    return { ok: true as const, session: result.session };
  } catch (error) {
    return { ok: false as const, error: errorMessage(error) };
  }
}
export async function signOut() {
  try {
    await requestOrigin();
    const jar = await cookies();
    auth.revoke(jar.get(SESSION_COOKIE)?.value);
    auth.cancel(jar.get(CHALLENGE_COOKIE)?.value);
    jar.delete(SESSION_COOKIE);
    jar.delete(CHALLENGE_COOKIE);
    return { ok: true as const };
  } catch {
    return { ok: false as const, error: "Could not sign out. Try again." };
  }
}
export async function getSession() {
  return currentSession();
}
