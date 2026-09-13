import type { ReactNode } from "react";
import { AppShell } from "@/components/app/app-shell";
import { VaultDataProvider } from "@/components/app/vault-data-provider";
import { WalletProvider } from "@/components/app/wallet-provider";

export default function ApplicationLayout({
  children,
}: {
  children: ReactNode;
}) {
  const chainId = Number(process.env.TRELP_CHAIN_ID);
  return (
    <WalletProvider chainId={chainId}>
      <VaultDataProvider>
        <AppShell>{children}</AppShell>
      </VaultDataProvider>
    </WalletProvider>
  );
}
