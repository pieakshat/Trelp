"use client";

import { create } from "zustand";
import { getVaultState } from "@/app/actions/protocol";

type Snapshot = Extract<
  Awaited<ReturnType<typeof getVaultState>>,
  { ok: true }
>["snapshot"];
export type LiveVaultSnapshot = Snapshot;

type VaultState = {
  snapshot: Snapshot | null;
  status: "idle" | "loading" | "ready" | "error" | "not_configured";
  error: string;
  refresh: (account?: `0x${string}`) => Promise<void>;
};

let request = 0;

export const useVaultStore = create<VaultState>((set) => ({
  snapshot: null,
  status: "idle",
  error: "",
  refresh: async (account) => {
    const current = ++request;
    set((state) => ({
      status: "loading",
      error: "",
      snapshot: state.snapshot,
    }));
    let result: Awaited<ReturnType<typeof getVaultState>>;
    try {
      result = await getVaultState(account ? { account } : {});
    } catch (failure) {
      if (current !== request) return;
      set({
        status: "error",
        error:
          failure instanceof Error
            ? failure.message
            : "Vault data is unavailable.",
      });
      return;
    }
    if (current !== request) return;
    if (result.ok) {
      set({ snapshot: result.snapshot, status: "ready", error: "" });
      return;
    }
    set({
      snapshot: null,
      status: result.code === "not_configured" ? "not_configured" : "error",
      error: result.error,
    });
  },
}));
