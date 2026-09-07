"use client";

import { create } from "zustand";

type AppShellState = {
  collapsed: boolean;
  mobileOpen: boolean;
  closeMobile: () => void;
  toggleCollapsed: () => void;
  toggleMobile: () => void;
};

export const useAppShellStore = create<AppShellState>((set) => ({
  collapsed: false,
  mobileOpen: false,
  closeMobile: () => set({ mobileOpen: false }),
  toggleCollapsed: () => set((state) => ({ collapsed: !state.collapsed })),
  toggleMobile: () => set((state) => ({ mobileOpen: !state.mobileOpen })),
}));
