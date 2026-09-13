import { z } from "zod";

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
