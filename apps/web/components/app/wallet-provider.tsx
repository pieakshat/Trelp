"use client";

import {
  PrivyProvider,
  useActiveWallet,
  usePrivy,
  useWallets,
} from "@privy-io/react-auth";
import {
  createContext,
  type ReactNode,
  useCallback,
  useContext,
  useEffect,
  useRef,
  useState,
} from "react";
import { formatEther, getAddress, type Hash } from "viem";
import {
  type ConfirmedReceipt,
  type ContractTransaction,
  type EvmProvider,
  privyChain,
  privyChainId,
  sendPrivyTransaction,
  waitForConfirmedReceipt,
} from "@/lib/wallet-core";
import { useVaultStore } from "@/stores/vault-store";

export type { ConfirmedReceipt } from "@/lib/wallet-core";

type WalletContextValue = {
  connectedAddress: string | null;
  chainId: number | null;
  status: string;
  error: string;
  nativeBalance: string | null;
  balanceError: string;
  balanceLoading: boolean;
  walletName: string | null;
  refreshBalance: () => Promise<void>;
  sendTransaction: (request: ContractTransaction) => Promise<Hash>;
  waitForReceipt: (hash: Hash) => Promise<ConfirmedReceipt>;
  open: () => void;
  disconnect: () => Promise<void>;
};

const WalletContext = createContext<WalletContextValue | null>(null);
const networks = [
  { id: 1, name: "Ethereum" },
  { id: 8453, name: "Base" },
  { id: 11155111, name: "Sepolia" },
  { id: 31337, name: "Anvil" },
];

export function explorerUrl(
  value: string,
  chainId: number | null,
  kind: "address" | "tx" = "address",
) {
  const host =
    chainId === 1
      ? "etherscan.io"
      : chainId === 8453
        ? "basescan.org"
        : chainId === 11155111
          ? "sepolia.etherscan.io"
          : null;
  const valid = new RegExp(`^0x[0-9a-fA-F]{${kind === "tx" ? 64 : 40}}$`).test(
    value,
  );
  return host && valid ? `https://${host}/${kind}/${value}` : null;
}

export function nativeBalanceLabel(balance: string | null, hidden = false) {
  if (hidden) return "••••";
  if (balance === null) return "—";
  const [whole, fraction = ""] = balance.split(".");
  const decimals = fraction.slice(0, 6).replace(/0+$/, "");
  if (whole === "0" && !decimals && /[1-9]/.test(fraction))
    return "<0.000001 ETH";
  return `${whole}${decimals ? `.${decimals}` : ""} ETH`;
}

export function networkName(id: number | null) {
  return (
    networks.find((network) => network.id === id)?.name ??
    (id ? `Chain ${id}` : "Not connected")
  );
}

function walletError(error: unknown) {
  if (
    typeof error === "object" &&
    error &&
    "code" in error &&
    error.code === 4001
  )
    return "Request cancelled in your wallet. You can try again.";
  return error instanceof Error
    ? error.message
    : "The wallet request failed. Please try again.";
}

function MissingPrivyProvider({
  children,
  message = "Add NEXT_PUBLIC_PRIVY_APP_ID to enable transactions.",
}: {
  children: ReactNode;
  message?: string;
}) {
  const dialog = useRef<HTMLDialogElement>(null);
  const unavailable = async () => {
    throw new Error(message);
  };
  return (
    <WalletContext.Provider
      value={{
        connectedAddress: null,
        chainId: null,
        status: "unconfigured",
        error: message,
        nativeBalance: null,
        balanceError: "",
        balanceLoading: false,
        walletName: null,
        refreshBalance: async () => undefined,
        sendTransaction: unavailable,
        waitForReceipt: unavailable,
        open: () => dialog.current?.showModal(),
        disconnect: async () => undefined,
      }}
    >
      {children}
      <dialog
        className="appDialog walletDialog"
        ref={dialog}
        aria-labelledby="privy-config-title"
      >
        <div className="dialogHead">
          <h2 id="privy-config-title">Privy configuration required</h2>
          <button
            type="button"
            aria-label="Close wallet dialog"
            onClick={() => dialog.current?.close()}
          >
            ×
          </button>
        </div>
        <p>{message}</p>
      </dialog>
    </WalletContext.Provider>
  );
}

function PrivyWalletContext({
  children,
  deploymentChainId,
}: {
  children: ReactNode;
  deploymentChainId: number;
}) {
  const { ready, authenticated, login, logout } = usePrivy();
  const { ready: walletsReady } = useWallets();
  const { wallet: selectedWallet } = useActiveWallet();
  const refreshVault = useVaultStore((state) => state.refresh);
  const active = selectedWallet?.type === "ethereum" ? selectedWallet : null;
  const connectedAddress =
    authenticated && active && /^0x[0-9a-fA-F]{40}$/.test(active.address)
      ? getAddress(active.address)
      : null;
  const [chainId, setChainId] = useState<number | null>(null);
  const [status, setStatus] = useState("idle");
  const [error, setError] = useState("");
  const [balance, setBalance] = useState<string | null>(null);
  const [balanceError, setBalanceError] = useState("");
  const [balanceLoading, setBalanceLoading] = useState(false);
  const providers = useRef(new Map<Hash, EvmProvider>());
  const balanceRequest = useRef(0);

  const refreshBalance = useCallback(async () => {
    const current = ++balanceRequest.current;
    if (!active || !connectedAddress) {
      setBalance(null);
      setBalanceError("");
      return;
    }
    setBalanceLoading(true);
    setBalanceError("");
    try {
      const provider = (await active.getEthereumProvider()) as EvmProvider;
      const [value, network] = await Promise.all([
        provider.request({
          method: "eth_getBalance",
          params: [connectedAddress, "latest"],
        }),
        provider.request({ method: "eth_chainId" }),
      ]);
      if (
        typeof value !== "string" ||
        !/^0x[0-9a-f]{1,64}$/i.test(value) ||
        typeof network !== "string"
      )
        throw new Error("Privy returned an invalid wallet balance.");
      const nextChainId = Number.parseInt(network, 16);
      if (!Number.isSafeInteger(nextChainId))
        throw new Error("Privy returned an invalid network.");
      if (current !== balanceRequest.current) return;
      setChainId(nextChainId);
      setBalance(formatEther(BigInt(value)));
    } catch {
      if (current !== balanceRequest.current) return;
      setBalance(null);
      setBalanceError(
        "Balance unavailable. Check your wallet connection and retry.",
      );
    } finally {
      if (current === balanceRequest.current) setBalanceLoading(false);
    }
  }, [active, connectedAddress]);

  useEffect(() => {
    if (!active || !connectedAddress) {
      balanceRequest.current++;
      setChainId(null);
      setBalance(null);
      return;
    }
    try {
      setChainId(privyChainId(active.chainId));
    } catch {
      setChainId(null);
    }
    void refreshBalance();
  }, [active, connectedAddress, refreshBalance]);

  useEffect(() => {
    const timer = window.setInterval(refreshBalance, 30_000);
    window.addEventListener("focus", refreshBalance);
    return () => {
      window.clearInterval(timer);
      window.removeEventListener("focus", refreshBalance);
    };
  }, [refreshBalance]);

  async function sendTransaction(request: ContractTransaction) {
    if (
      !ready ||
      !walletsReady ||
      !authenticated ||
      !active ||
      !connectedAddress
    )
      throw new Error("Connect with Privy before continuing.");
    if (request.chainId !== deploymentChainId)
      throw new Error(
        `This vault is configured for chain ${deploymentChainId}.`,
      );
    setError("");
    setStatus("sending");
    try {
      if (privyChainId(active.chainId) !== request.chainId)
        await active.switchChain(request.chainId);
      const provider = (await active.getEthereumProvider()) as EvmProvider;
      const currentChain = await provider.request({ method: "eth_chainId" });
      if (
        typeof currentChain !== "string" ||
        Number.parseInt(currentChain, 16) !== request.chainId
      )
        throw new Error(`Switch your wallet to chain ${request.chainId}.`);
      const hash = await sendPrivyTransaction(
        provider,
        connectedAddress,
        request,
      );
      providers.current.set(hash, provider);
      setChainId(request.chainId);
      return hash;
    } catch (failure) {
      setError(walletError(failure));
      throw failure;
    } finally {
      setStatus("idle");
    }
  }

  async function waitForReceipt(hash: Hash) {
    if (!active || !connectedAddress)
      throw new Error("The Privy wallet disconnected before confirmation.");
    const provider =
      providers.current.get(hash) ??
      ((await active.getEthereumProvider()) as EvmProvider);
    try {
      return await waitForConfirmedReceipt(provider, hash, async () => {
        await Promise.all([refreshVault(connectedAddress), refreshBalance()]);
      });
    } finally {
      providers.current.delete(hash);
    }
  }

  async function disconnect() {
    setError("");
    setStatus("disconnecting");
    try {
      active?.disconnect();
      await logout();
      setChainId(null);
      setBalance(null);
    } catch (failure) {
      setError(walletError(failure));
    } finally {
      setStatus("idle");
    }
  }

  return (
    <WalletContext.Provider
      value={{
        connectedAddress,
        chainId,
        status: ready && walletsReady ? status : "initializing",
        error,
        nativeBalance: balance,
        balanceError,
        balanceLoading,
        walletName: active?.meta.name ?? null,
        refreshBalance,
        sendTransaction,
        waitForReceipt,
        open: () => {
          setError("");
          if (!authenticated || !active) login();
        },
        disconnect,
      }}
    >
      {children}
    </WalletContext.Provider>
  );
}

export function WalletProvider({
  children,
  chainId,
}: {
  children: ReactNode;
  chainId: number;
}) {
  const appId = process.env.NEXT_PUBLIC_PRIVY_APP_ID?.trim();
  if (!appId) return <MissingPrivyProvider>{children}</MissingPrivyProvider>;
  let chain: ReturnType<typeof privyChain>;
  try {
    chain = privyChain(chainId);
  } catch {
    return (
      <MissingPrivyProvider
        message={`Chain ${chainId || "—"} is not configured for Privy in this app.`}
      >
        {children}
      </MissingPrivyProvider>
    );
  }
  const clientId = process.env.NEXT_PUBLIC_PRIVY_CLIENT_ID?.trim();
  return (
    <PrivyProvider
      appId={appId}
      {...(clientId ? { clientId } : {})}
      config={{
        loginMethods: ["wallet"],
        defaultChain: chain,
        supportedChains: [chain],
        appearance: {
          accentColor: "#9e1c29",
          logo: "/brand/trelp-mark.svg",
          theme: "light",
          walletChainType: "ethereum-only",
        },
      }}
    >
      <PrivyWalletContext deploymentChainId={chainId}>
        {children}
      </PrivyWalletContext>
    </PrivyProvider>
  );
}

export function useWallet() {
  const value = useContext(WalletContext);
  if (!value) throw new Error("WalletProvider is required.");
  return value;
}

export function WalletButton() {
  const { connectedAddress, open, status } = useWallet();
  return (
    <button
      className="connectButton"
      type="button"
      onClick={open}
      aria-label={
        connectedAddress ? "Manage wallet connection" : "Connect wallet"
      }
    >
      {status === "sending" || status === "initializing"
        ? "Wallet pending…"
        : connectedAddress
          ? `${connectedAddress.slice(0, 6)}…${connectedAddress.slice(-4)}`
          : "Connect wallet"}
    </button>
  );
}
