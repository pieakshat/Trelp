"use client";

import { create } from "zustand";

export type VaultFilter = "all" | "junior" | "senior";

type VaultFilterState = {
  filter: VaultFilter;
  setFilter: (filter: VaultFilter) => void;
};

export const useVaultFilterStore = create<VaultFilterState>((set) => ({
  filter: "all",
  setFilter: (filter) => set({ filter }),
}));
