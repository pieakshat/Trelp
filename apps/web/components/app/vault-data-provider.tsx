"use client";

import { type ReactNode, useEffect } from "react";
import { useVaultStore } from "@/stores/vault-store";
import { useWallet } from "./wallet-provider";

export function VaultDataProvider({ children }: { children: ReactNode }) {
  const account = useWallet().connectedAddress;
  const refresh = useVaultStore((state) => state.refresh);
  useEffect(() => {
    const load = () =>
      void refresh(account ? (account as `0x${string}`) : undefined);
    load();
    window.addEventListener("focus", load);
    const timer = window.setInterval(load, 30_000);
    return () => {
      window.removeEventListener("focus", load);
      window.clearInterval(timer);
    };
  }, [account, refresh]);
  return children;
}
