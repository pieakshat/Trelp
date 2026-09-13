import { randomBytes } from "node:crypto";
import { type Address, getAddress, verifyMessage } from "viem";
import { createSiweMessage } from "viem/siwe";

export type Session = { address: Address; chainId: number; expiresAt: number };
type Challenge = {
  message: string;
  address: Address;
  chainId: number;
  origin: string;
  expiresAt: number;
};
export class AuthError extends Error {}

// ponytail: in-memory single-process sessions; replace with shared storage before scaling.
export class AuthService {
  private challenges = new Map<string, Challenge>();
  private sessions = new Map<string, Session>();
  private attempts = new Map<string, { count: number; until: number }>();
  constructor(private now: () => number = Date.now) {}
  private prune() {
    for (const [id, value] of this.challenges)
      if (value.expiresAt <= this.now()) this.challenges.delete(id);
    for (const [id, value] of this.sessions)
      if (value.expiresAt <= this.now()) this.sessions.delete(id);
    for (const [id, value] of this.attempts)
      if (value.until <= this.now()) this.attempts.delete(id);
  }
  challenge(addressInput: string, chainId: number, origin: string) {
    this.prune();
    const supported = [1, 8453, 11155111];
    if (process.env.NODE_ENV !== "production") supported.push(31337);
    if (!supported.includes(chainId))
      throw new AuthError("Switch your wallet to Ethereum, Base, or Sepolia.");
    const address = getAddress(addressInput);
    const key = address.toLowerCase();
    const attempts = this.attempts.get(key) ?? {
      count: 0,
      until: this.now() + 60000,
    };
    if (
      attempts.count >= 5 ||
      this.challenges.size >= 1000 ||
      this.sessions.size >= 10000
    )
      throw new AuthError(
        "Too many sign-in requests. Try again in one minute.",
      );
    this.attempts.set(key, { ...attempts, count: attempts.count + 1 });
    const token = randomBytes(32).toString("hex");
    const expiresAt = this.now() + 300000;
    const message = createSiweMessage({
      address,
      chainId,
      domain: new URL(origin).host,
      uri: origin,
      version: "1",
      nonce: randomBytes(16).toString("hex"),
      issuedAt: new Date(this.now()),
      expirationTime: new Date(expiresAt),
      statement:
        "Sign in to Trelp. This does not authorize transactions or access to funds.",
    });
    this.challenges.set(token, {
      message,
      address,
      chainId,
      origin,
      expiresAt,
    });
    return { token, message };
  }
  async verify(
    token: string,
    message: string,
    signature: `0x${string}`,
    origin: string,
  ) {
    const challenge = this.challenges.get(token);
    this.challenges.delete(token); // Consume before asynchronous verification, including failed attempts.
    if (
      !challenge ||
      challenge.expiresAt <= this.now() ||
      challenge.origin !== origin ||
      challenge.message !== message
    )
      throw new AuthError(
        "The sign-in request expired or changed. Connect your wallet again.",
      );
    let valid = false;
    try {
      valid = await verifyMessage({
        address: challenge.address,
        message,
        signature,
      });
    } catch {
      valid = false;
    }
    if (!valid)
      throw new AuthError("The signature does not match this wallet.");
    const session: Session = {
      address: challenge.address,
      chainId: challenge.chainId,
      expiresAt: this.now() + 8 * 60 * 60 * 1000,
    };
    const sessionToken = randomBytes(32).toString("hex");
    this.sessions.set(sessionToken, session);
    return { token: sessionToken, session };
  }
  session(token: string | undefined): Session | null {
    this.prune();
    return token ? (this.sessions.get(token) ?? null) : null;
  }
  revoke(token: string | undefined) {
    if (token) this.sessions.delete(token);
  }
  cancel(token: string | undefined) {
    if (token) this.challenges.delete(token);
  }
}
