import type { ReactNode } from "react";
import { AppShell } from "@/components/app/app-shell";
import { VaultDataProvider } from "@/components/app/vault-data-provider";
import { WalletProvider } from "@/components/app/wallet-provider";

export default function ApplicationLayout({
  children,
}: {
  children: ReactNode;
}) {
  return (
    <WalletProvider>
      <VaultDataProvider>
        <AppShell>{children}</AppShell>
      </VaultDataProvider>
    </WalletProvider>
  );
}
