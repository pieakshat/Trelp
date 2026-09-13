import { z } from "zod";

export const draftSchema = z.object({
  name: z.string().trim().min(3, "Use at least 3 characters.").max(60),
  asset: z.enum(["ETH / USDC", "WBTC / USDC", "USDC / USDT"]),
  network: z.enum(["Ethereum", "Base"]),
  duration: z.coerce
    .number()
    .pipe(z.union([z.literal(14), z.literal(30), z.literal(90)])),
  buffer: z.coerce.number().int().min(10).max(50),
  capacity: z.coerce.number().int().min(10_000).max(10_000_000),
  riskAccepted: z.literal(true, {
    error: "Accept the risk notice to continue.",
  }),
});
export type DraftInput = z.infer<typeof draftSchema>;
export type Draft = DraftInput & { id: string; createdAt: string };

export const preferencesSchema = z.object({
  compact: z.boolean(),
  hideBalances: z.boolean(),
  defaultTranche: z.enum(["all", "senior", "junior"]),
});
export type Preferences = z.infer<typeof preferencesSchema>;

export function money(value: number, hidden = false) {
  return hidden
    ? "••••"
    : new Intl.NumberFormat("en-US", {
        style: "currency",
        currency: "USD",
        maximumFractionDigits: 2,
      }).format(value);
}

export function dateLabel(date: string | number | bigint) {
  const value = typeof date === "bigint" ? Number(date) * 1000 : date;
  return new Intl.DateTimeFormat("en-US", {
    month: "short",
    day: "numeric",
    year: "numeric",
    timeZone: "UTC",
  }).format(new Date(value));
}
