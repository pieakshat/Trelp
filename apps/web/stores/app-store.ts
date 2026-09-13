"use client";

import { create } from "zustand";
import { createJSONStorage, persist } from "zustand/middleware";
import {
  type Draft,
  type DraftInput,
  draftSchema,
  type Preferences,
  preferencesSchema,
} from "@/lib/local-data";

type AppState = {
  drafts: Draft[];
  preferences: Preferences;
  saveDraft: (input: DraftInput) => string;
  removeDraft: (id: string) => void;
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
      drafts: [],
      preferences: defaults,
      saveDraft: (input) => {
        const parsed = draftSchema.parse(input);
        const id = crypto.randomUUID();
        set((state) => ({
          drafts: [
            { ...parsed, id, createdAt: new Date().toISOString() },
            ...state.drafts,
          ].slice(0, 100),
        }));
        return id;
      },
      removeDraft: (id) =>
        set((state) => ({
          drafts: state.drafts.filter((draft) => draft.id !== id),
        })),
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
      partialize: ({ drafts, preferences }) => ({ drafts, preferences }),
    },
  ),
);
