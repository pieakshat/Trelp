import "server-only";
import { cookies, headers } from "next/headers";
import { AuthError, AuthService } from "./auth-core";

const runtime = globalThis as typeof globalThis & { trelpAuth?: AuthService };
runtime.trelpAuth ??= new AuthService();
export const auth = runtime.trelpAuth;
export const SESSION_COOKIE = "trelp-session";
export const CHALLENGE_COOKIE = "trelp-challenge";
export async function requestOrigin() {
  const h = await headers();
  const origin = h.get("origin");
  if (!origin || origin.length > 200)
    throw new AuthError("Open Trelp directly to continue.");
  const url = new URL(origin);
  const configured = process.env.NEXT_PUBLIC_APP_URL;
  const local =
    ["localhost", "127.0.0.1", "[::1]"].includes(url.hostname) &&
    url.protocol === "http:";
  if (configured ? origin !== new URL(configured).origin : !local)
    throw new AuthError("This sign-in origin is not allowed.");
  if (url.host !== h.get("host"))
    throw new AuthError("This request came from a different host.");
  return origin;
}
export function cookieOptions(origin: string, maxAge: number) {
  return {
    httpOnly: true,
    sameSite: "lax" as const,
    secure: origin.startsWith("https:"),
    path: "/",
    maxAge,
  };
}
export async function currentSession() {
  return auth.session((await cookies()).get(SESSION_COOKIE)?.value);
}
