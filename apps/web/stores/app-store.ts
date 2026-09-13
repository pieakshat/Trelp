"use client";

import { create } from "zustand";
import { createJSONStorage, persist } from "zustand/middleware";
import { type Preferences, preferencesSchema } from "@/lib/local-data";

type AppState = {
  preferences: Preferences;
  setPreferences: (value: Preferences) => void;
};

const defaults: Preferences = {
  compact: false,
  hideBalances: false,
  defaultTranche: "all",
};
const storageWarning = () =>
  window.dispatchEvent(new Event("trelp-storage-error"));

export const useAppStore = create<AppState>()(
  persist(
    (set) => ({
      preferences: defaults,
      setPreferences: (value) =>
        set({ preferences: preferencesSchema.parse(value) }),
    }),
    {
      name: "trelp-local-v2",
      version: 2,
      skipHydration: true,
      storage: createJSONStorage(() => ({
        getItem: (name) => {
          try {
            return localStorage.getItem(name);
          } catch {
            storageWarning();
            return null;
          }
        },
        setItem: (name, value) => {
          try {
            localStorage.setItem(name, value);
          } catch {
            storageWarning();
          }
        },
        removeItem: (name) => {
          try {
            localStorage.removeItem(name);
          } catch {
            storageWarning();
          }
        },
      })),
      partialize: ({ preferences }) => ({ preferences }),
    },
  ),
);
