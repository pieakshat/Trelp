"use client";

import Image from "next/image";
import {
  createContext,
  type ReactNode,
  useCallback,
  useContext,
  useEffect,
  useRef,
  useState,
} from "react";
import { formatEther, getAddress, type Hash, stringToHex } from "viem";
import {
  completeSignIn,
  getSession,
  requestSignIn,
  signOut,
} from "@/app/actions/auth";
import type { Session } from "@/lib/server/auth-core";
import { useAppStore } from "@/stores/app-store";

type Provider = {
  request: (input: { method: string; params?: unknown[] }) => Promise<unknown>;
  on?: (event: string, listener: (...args: unknown[]) => void) => void;
  removeListener?: (
    event: string,
    listener: (...args: unknown[]) => void,
  ) => void;
};
type Wallet = { id: string; name: string; icon?: string; provider: Provider };
export type ConfirmedReceipt = {
  hash: Hash;
  blockNumber: bigint;
  gasUsed: bigint;
  fee: bigint | null;
};
const devWalletAddress = process.env.NEXT_PUBLIC_TRELP_DEV_WALLET_ADDRESS;
const devRpcUrl = process.env.NEXT_PUBLIC_TRELP_DEV_RPC_URL;

function devnetWallet(): Wallet | null {
  let rpcHost = "";
  try {
    rpcHost = new URL(devRpcUrl ?? "").hostname;
  } catch {
    return null;
  }
  if (
    process.env.NODE_ENV === "production" ||
    !devRpcUrl ||
    !devWalletAddress ||
    !/^0x[0-9a-fA-F]{40}$/.test(devWalletAddress) ||
    !["127.0.0.1", "localhost"].includes(rpcHost)
  )
    return null;
  let id = 0;
  return {
    id: "trelp-anvil",
    name: "Anvil test wallet",
    provider: {
      async request({ method, params = [] }) {
        if (method === "eth_requestAccounts" || method === "eth_accounts")
          return [devWalletAddress];
        if (method === "wallet_switchEthereumChain") return null;
        const response = await fetch(devRpcUrl, {
          body: JSON.stringify({
            id: ++id,
            jsonrpc: "2.0",
            method,
            params,
          }),
          headers: { "content-type": "application/json" },
          method: "POST",
        });
        const payload = (await response.json()) as {
          error?: { message?: string };
          result?: unknown;
        };
        if (payload.error)
          throw new Error(payload.error.message ?? "Devnet wallet RPC failed.");
        return payload.result;
      },
    },
  };
}

type WalletContextValue = {
  session: Session | null;
  connectedAddress: string | null;
  chainId: number | null;
  status: string;
  error: string;
  nativeBalance: string | null;
  balanceError: string;
  balanceLoading: boolean;
  walletName: string | null;
  refreshBalance: () => Promise<void>;
  sendTransaction: (request: {
    chainId: number;
    to: `0x${string}`;
    data: `0x${string}`;
  }) => Promise<Hash>;
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
    networks.find((n) => n.id === id)?.name ??
    (id ? `Chain ${id}` : "Not connected")
  );
}
function addressOf(value: unknown) {
  if (
    !Array.isArray(value) ||
    typeof value[0] !== "string" ||
    !/^0x[0-9a-fA-F]{40}$/.test(value[0])
  )
    return null;
  return getAddress(value[0]);
}
function chainOf(value: unknown) {
  if (typeof value !== "string" || !/^0x[0-9a-f]+$/i.test(value))
    throw new Error("The wallet returned an invalid network.");
  const id = Number.parseInt(value, 16);
  if (!Number.isSafeInteger(id))
    throw new Error("The wallet returned an invalid network.");
  return id;
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
export function WalletProvider({ children }: { children: ReactNode }) {
  const hideBalances = useAppStore((state) => state.preferences.hideBalances);
  const [wallets, setWallets] = useState<Wallet[]>([]);
  const [active, setActive] = useState<Wallet | null>(null);
  const [session, setSession] = useState<Session | null>(null);
  const [connectedAddress, setAddress] = useState<string | null>(null);
  const [chainId, setChainId] = useState<number | null>(null);
  const [status, setStatus] = useState("idle");
  const [error, setError] = useState("");
  const [copied, setCopied] = useState("");
  const [balance, setBalance] = useState<{
    key: string;
    amount: string | null;
    error: string;
    loading: boolean;
  }>({ key: "", amount: null, error: "", loading: false });
  const balanceRequest = useRef(0);
  const balanceKey = `${connectedAddress ?? ""}:${chainId ?? ""}`;
  const refreshBalance = useCallback(async () => {
    const request = ++balanceRequest.current;
    if (
      !active ||
      !connectedAddress ||
      !networks.some((n) => n.id === chainId)
    ) {
      setBalance({ key: "", amount: null, error: "", loading: false });
      return;
    }
    const key = `${connectedAddress}:${chainId}`;
    setBalance((current) => ({
      key,
      amount: current.key === key ? current.amount : null,
      error: "",
      loading: true,
    }));
    try {
      const [value, network] = await Promise.all([
        active.provider.request({
          method: "eth_getBalance",
          params: [connectedAddress, "latest"],
        }),
        active.provider.request({ method: "eth_chainId" }),
      ]);
      if (chainOf(network) !== chainId)
        throw new Error("Wallet network changed. Refresh your balance.");
      if (typeof value !== "string" || !/^0x[0-9a-f]{1,64}$/i.test(value))
        throw new Error("Your wallet returned an invalid balance.");
      if (request === balanceRequest.current)
        setBalance({
          key,
          amount: formatEther(BigInt(value)),
          error: "",
          loading: false,
        });
    } catch {
      if (request === balanceRequest.current)
        setBalance({
          key,
          amount: null,
          error: "Balance unavailable. Check your wallet connection and retry.",
          loading: false,
        });
    }
  }, [active, connectedAddress, chainId]);
  useEffect(() => {
    void refreshBalance();
    window.addEventListener("focus", refreshBalance);
    const timer = window.setInterval(refreshBalance, 30000);
    return () => {
      balanceRequest.current++;
      window.removeEventListener("focus", refreshBalance);
      window.clearInterval(timer);
    };
  }, [refreshBalance]);
  const nativeBalance = balance.key === balanceKey ? balance.amount : null;
  const balanceError = balance.key === balanceKey ? balance.error : "";
  const balanceLoading = balance.key === balanceKey && balance.loading;
  const dialog = useRef<HTMLDialogElement>(null);
  const operation = useRef(0);
  const busy = useRef(false);
  const invalidated = useRef(false);
  const revocation = useRef<Promise<void> | null>(null);
  const revokeSession = useCallback(() => {
    invalidated.current = true;
    setSession(null);
    if (!revocation.current) {
      revocation.current = signOut()
        .then((result) => {
          if (!result.ok) throw new Error(result.error);
          invalidated.current = false;
        })
        .catch(() => {
          throw new Error(
            "Could not end the old session. Retry disconnect before signing in.",
          );
        })
        .finally(() => {
          revocation.current = null;
        });
    }
    return revocation.current;
  }, []);
  useEffect(() => {
    let mounted = true;
    function announce(event: Event) {
      const value = (event as CustomEvent).detail;
      if (
        !value ||
        typeof value.info?.uuid !== "string" ||
        typeof value.info?.name !== "string" ||
        typeof value.provider?.request !== "function"
      )
        return;
      setWallets((current) => [
        ...current.filter((w) => w.provider !== value.provider).slice(0, 19),
        {
          id: value.info.uuid.slice(0, 80),
          name: value.info.name.slice(0, 60),
          icon:
            typeof value.info.icon === "string" &&
            value.info.icon.length <= 100000 &&
            /^data:image\/(png|webp|svg\+xml)[;,]/i.test(value.info.icon)
              ? value.info.icon
              : undefined,
          provider: value.provider,
        },
      ]);
    }
    window.addEventListener("eip6963:announceProvider", announce);
    window.dispatchEvent(new Event("eip6963:requestProvider"));
    const injected = (window as Window & { ethereum?: Provider }).ethereum;
    if (injected?.request)
      setWallets((current) =>
        current.some((w) => w.provider === injected)
          ? current
          : [
              ...current,
              { id: "injected", name: "Browser wallet", provider: injected },
            ],
      );
    const localWallet = devnetWallet();
    if (localWallet) {
      setWallets((current) => [
        localWallet,
        ...current.filter((wallet) => wallet.id !== localWallet.id),
      ]);
      setActive(localWallet);
      setAddress(getAddress(devWalletAddress ?? ""));
      setChainId(31337);
    }
    async function refresh() {
      try {
        if (busy.current) return;
        if (invalidated.current) {
          await revokeSession();
          if (mounted) setError("");
          return;
        }
        const version = operation.current;
        const value = await getSession();
        if (
          mounted &&
          !busy.current &&
          !invalidated.current &&
          version === operation.current
        )
          setSession(value);
      } catch {
        /* An unavailable server does not manufacture a session. */
      }
    }
    void refresh();
    window.addEventListener("focus", refresh);
    const timer = window.setInterval(refresh, 60000);
    return () => {
      mounted = false;
      window.removeEventListener("eip6963:announceProvider", announce);
      window.removeEventListener("focus", refresh);
      window.clearInterval(timer);
    };
  }, [revokeSession]);
  useEffect(() => {
    if (active || !session) return;
    let live = true;
    const version = operation.current;
    void (async () => {
      for (const wallet of wallets) {
        try {
          const address = addressOf(
            await wallet.provider.request({ method: "eth_accounts" }),
          );
          const chain = chainOf(
            await wallet.provider.request({ method: "eth_chainId" }),
          );
          if (
            live &&
            version === operation.current &&
            address === session.address &&
            chain === session.chainId
          ) {
            setActive(wallet);
            setAddress(address);
            setChainId(chain);
            return;
          }
        } catch {
          /* A locked wallet can be reconnected manually. */
        }
      }
    })();
    return () => {
      live = false;
    };
  }, [active, session, wallets]);
  useEffect(() => {
    if (!active) return;
    const provider = active.provider;
    function changed() {
      const version = ++operation.current;
      void revokeSession().catch((e) => setError(walletError(e)));
      void Promise.all([
        provider.request({ method: "eth_accounts" }),
        provider.request({ method: "eth_chainId" }),
      ])
        .then(([accounts, chain]) => {
          if (version === operation.current) {
            setAddress(addressOf(accounts));
            setChainId(chainOf(chain));
          }
        })
        .catch(() => {
          if (version === operation.current) {
            setAddress(null);
            setChainId(null);
          }
        });
    }
    function disconnected() {
      operation.current++;
      setActive(null);
      setAddress(null);
      setChainId(null);
      void revokeSession().catch((e) => setError(walletError(e)));
    }
    active.provider.on?.("accountsChanged", changed);
    active.provider.on?.("chainChanged", changed);
    active.provider.on?.("disconnect", disconnected);
    return () => {
      active.provider.removeListener?.("accountsChanged", changed);
      active.provider.removeListener?.("chainChanged", changed);
      active.provider.removeListener?.("disconnect", disconnected);
    };
  }, [active, revokeSession]);
  async function connect(wallet: Wallet) {
    if (busy.current) return;
    busy.current = true;
    setStatus("connecting");
    setError("");
    const current = ++operation.current;
    try {
      const accounts = await wallet.provider.request({
        method: "eth_requestAccounts",
      });
      const address = addressOf(accounts);
      if (!address)
        throw new Error(
          "No account was selected. Unlock your wallet and try again.",
        );
      const chain = chainOf(
        await wallet.provider.request({ method: "eth_chainId" }),
      );
      if (current !== operation.current)
        throw new Error("Your wallet changed. Connect it again.");
      if (
        invalidated.current ||
        (session &&
          (session.address.toLowerCase() !== address.toLowerCase() ||
            session.chainId !== chain))
      ) {
        await revokeSession();
      }
      if (current !== operation.current)
        throw new Error("Your wallet changed. Connect it again.");
      setActive(wallet);
      setAddress(address);
      setChainId(chain);
    } catch (e) {
      setError(walletError(e));
    } finally {
      busy.current = false;
      setStatus("idle");
    }
  }
  async function authenticate() {
    if (!active || busy.current) return;
    busy.current = true;
    setStatus("signing");
    setError("");
    const current = ++operation.current;
    try {
      if (invalidated.current) await revokeSession();
      const address = addressOf(
        await active.provider.request({ method: "eth_accounts" }),
      );
      const chain = chainOf(
        await active.provider.request({ method: "eth_chainId" }),
      );
      if (
        current !== operation.current ||
        !address ||
        address !== connectedAddress ||
        chain !== chainId
      )
        throw new Error("Your wallet changed. Reconnect before signing in.");
      const challenge = await requestSignIn({ address, chainId: chain });
      if (!challenge.ok) throw new Error(challenge.error);
      const signature = await active.provider.request({
        method: "personal_sign",
        params: [stringToHex(challenge.message), address],
      });
      if (current !== operation.current)
        throw new Error("Your wallet changed during sign-in. Try again.");
      const result = await completeSignIn({
        message: challenge.message,
        signature,
      });
      if (current !== operation.current) {
        await revokeSession();
        throw new Error("Your wallet changed during sign-in. Try again.");
      }
      if (!result.ok) throw new Error(result.error);
      setSession(result.session);
      dialog.current?.close();
    } catch (e) {
      setError(walletError(e));
    } finally {
      busy.current = false;
      setStatus("idle");
    }
  }
  async function disconnect() {
    if (busy.current) return;
    busy.current = true;
    setStatus("disconnecting");
    setError("");
    operation.current++;
    try {
      await revokeSession();
      setActive(null);
      setAddress(null);
      setChainId(null);
      dialog.current?.close();
    } catch (e) {
      setError(walletError(e));
    } finally {
      busy.current = false;
      setStatus("idle");
    }
  }
  async function switchNetwork(id: number) {
    if (!active || busy.current) return;
    busy.current = true;
    operation.current++;
    setStatus("switching");
    setError("");
    try {
      await active.provider.request({
        method: "wallet_switchEthereumChain",
        params: [{ chainId: `0x${id.toString(16)}` }],
      });
      const nextChain = chainOf(
        await active.provider.request({ method: "eth_chainId" }),
      );
      setChainId(nextChain);
      if (nextChain !== chainId) await revokeSession();
    } catch (e) {
      setError(walletError(e));
    } finally {
      busy.current = false;
      setStatus("idle");
    }
  }
  async function sendTransaction(request: {
    chainId: number;
    to: `0x${string}`;
    data: `0x${string}`;
  }) {
    if (!active || !connectedAddress)
      throw new Error("Connect your wallet before continuing.");
    const currentChain = chainOf(
      await active.provider.request({ method: "eth_chainId" }),
    );
    if (currentChain !== request.chainId) {
      setChainId(currentChain);
      throw new Error(`Switch your wallet to chain ${request.chainId}.`);
    }
    const hash = await active.provider.request({
      method: "eth_sendTransaction",
      params: [
        {
          from: connectedAddress,
          to: request.to,
          data: request.data,
        },
      ],
    });
    if (typeof hash !== "string" || !/^0x[0-9a-fA-F]{64}$/.test(hash))
      throw new Error("The wallet returned an invalid transaction hash.");
    return hash as Hash;
  }
  async function waitForReceipt(hash: Hash) {
    if (!active)
      throw new Error("The wallet disconnected before confirmation.");
    for (let attempt = 0; attempt < 120; attempt++) {
      const receipt = await active.provider.request({
        method: "eth_getTransactionReceipt",
        params: [hash],
      });
      if (receipt && typeof receipt === "object" && "status" in receipt) {
        const result = receipt as Record<string, unknown>;
        if (result.status === "0x0")
          throw new Error("The transaction reverted on-chain.");
        if (result.status !== "0x1")
          throw new Error("The wallet returned an invalid receipt.");
        if (
          typeof result.blockNumber !== "string" ||
          !/^0x[0-9a-f]+$/i.test(result.blockNumber) ||
          typeof result.gasUsed !== "string" ||
          !/^0x[0-9a-f]+$/i.test(result.gasUsed)
        )
          throw new Error("The wallet returned an invalid receipt.");
        const gasUsed = BigInt(result.gasUsed);
        const gasPrice =
          typeof result.effectiveGasPrice === "string" &&
          /^0x[0-9a-f]+$/i.test(result.effectiveGasPrice)
            ? BigInt(result.effectiveGasPrice)
            : null;
        return {
          hash,
          blockNumber: BigInt(result.blockNumber),
          gasUsed,
          fee: gasPrice === null ? null : gasUsed * gasPrice,
        };
      }
      await new Promise((resolve) => window.setTimeout(resolve, 1_000));
    }
    throw new Error("The transaction is still pending. Check your wallet.");
  }
  const pending = status !== "idle";
  return (
    <WalletContext.Provider
      value={{
        session,
        connectedAddress,
        chainId,
        status,
        error,
        nativeBalance,
        balanceError,
        balanceLoading,
        walletName: active?.name ?? null,
        refreshBalance,
        sendTransaction,
        waitForReceipt,
        open: () => {
          setError("");
          dialog.current?.showModal();
        },
        disconnect,
      }}
    >
      {children}
      <dialog
        className="appDialog walletDialog"
        ref={dialog}
        aria-labelledby="wallet-title"
      >
        <div className="dialogHead">
          <h2 id="wallet-title">
            {session ? "Your wallet session" : "Connect your wallet"}
          </h2>
          <button
            type="button"
            aria-label="Close wallet dialog"
            onClick={() => dialog.current?.close()}
          >
            ×
          </button>
        </div>
        <p className="muted">
          Your wallet. Your keys. Connect an installed wallet and sign a message
          to verify ownership.
        </p>
        {(connectedAddress || session) && (
          <div className="walletAccount">
            <div className="walletIdentity">
              <span className="walletAvatar" aria-hidden="true">
                ↗
              </span>
              <div>
                <strong>{active?.name ?? "Wallet session"}</strong>
                <code>{connectedAddress ?? session?.address}</code>
              </div>
            </div>
            <span>
              {networkName(chainId ?? session?.chainId ?? null)} ·{" "}
              {session ? "Signed in" : "Connected, not signed in"}
            </span>
            {connectedAddress && networks.some((n) => n.id === chainId) && (
              <section
                className="walletLiveBalance"
                aria-label="Wallet native balance"
              >
                <span>Native balance · on-chain</span>
                <strong>
                  {balanceLoading && nativeBalance === null
                    ? "Loading…"
                    : nativeBalanceLabel(nativeBalance, hideBalances)}
                </strong>
                <button
                  type="button"
                  className="textButton"
                  onClick={() => void refreshBalance()}
                  disabled={balanceLoading}
                >
                  {balanceLoading ? "Refreshing…" : "Refresh balance"}
                </button>
                {balanceError && (
                  <p className="uiError" role="status">
                    {balanceError}
                  </p>
                )}
              </section>
            )}
            {connectedAddress && (
              <div className="walletAccountActions">
                <button
                  type="button"
                  className="textButton"
                  onClick={async () => {
                    try {
                      await navigator.clipboard.writeText(connectedAddress);
                      setCopied(connectedAddress);
                    } catch {
                      setError(
                        "Could not copy. Select the address above to copy it.",
                      );
                    }
                  }}
                >
                  {copied === connectedAddress
                    ? "Address copied"
                    : "Copy address"}
                </button>
                {explorerUrl(connectedAddress, chainId) && (
                  <a
                    href={explorerUrl(connectedAddress, chainId) ?? undefined}
                    target="_blank"
                    rel="noreferrer"
                    className="textButton"
                  >
                    View on explorer ↗
                  </a>
                )}
              </div>
            )}
          </div>
        )}
        {!active && (
          <div className="walletOptions">
            {wallets.map((wallet) => (
              <button
                className="uiButton secondary"
                type="button"
                disabled={pending}
                onClick={() => void connect(wallet)}
                key={wallet.id}
              >
                <span className="walletOptionName">
                  {wallet.icon ? (
                    <Image
                      src={wallet.icon}
                      alt=""
                      width={32}
                      height={32}
                      unoptimized
                    />
                  ) : (
                    <span className="walletOptionIcon" aria-hidden="true">
                      ↗
                    </span>
                  )}
                  {wallet.name}
                </span>
                <span className="badge">Installed</span>
              </button>
            ))}
          </div>
        )}
        {!wallets.length && (
          <div className="uiNotice">
            <strong>No wallet detected</strong>
            <p>
              Open this page in your wallet’s browser, or install a browser
              wallet and reload. Only wallets installed on your device can
              connect here.
            </p>
            <div className="walletInstallLinks">
              <a
                href="https://metamask.io/download/"
                className="walletInstallLink"
                target="_blank"
                rel="noreferrer"
              >
                <Image
                  src="/brand/tokens/metamask.svg"
                  alt=""
                  width={20}
                  height={20}
                />{" "}
                Get MetaMask ↗
              </a>
              <a
                className="walletInstallLink"
                href="https://rabby.io/"
                target="_blank"
                rel="noreferrer"
              >
                Get Rabby ↗
              </a>
            </div>
          </div>
        )}
        {active && (
          <>
            <label className="field">
              Wallet network
              <select
                disabled={pending}
                value={chainId ?? ""}
                onChange={(e) => void switchNetwork(Number(e.target.value))}
              >
                {!networks.some((n) => n.id === chainId) && (
                  <option value={chainId ?? ""}>Unsupported network</option>
                )}
                {networks.map((n) => (
                  <option value={n.id} key={n.id}>
                    {n.name}
                  </option>
                ))}
              </select>
            </label>
            {!session && (
              <button
                className="uiButton fullWidth"
                type="button"
                disabled={
                  pending ||
                  !connectedAddress ||
                  !networks.some((n) => n.id === chainId)
                }
                onClick={() => void authenticate()}
              >
                {status === "signing"
                  ? "Check your wallet…"
                  : "Sign in with Ethereum"}
              </button>
            )}
          </>
        )}
        {pending && (
          <p role="status" className="muted">
            {status === "connecting"
              ? "Choose an account in your wallet…"
              : status === "switching"
                ? "Confirm the network in your wallet…"
                : status === "disconnecting"
                  ? "Ending your session…"
                  : "Waiting for your signature…"}
          </p>
        )}
        {error && (
          <p className="uiError" role="alert">
            {error}
          </p>
        )}
        {(active || session) && (
          <button
            className="textButton danger"
            type="button"
            disabled={pending}
            onClick={() => void disconnect()}
          >
            Disconnect and sign out
          </button>
        )}
        <p className="footnote">
          Your balance comes directly from your wallet’s network. Signing in
          costs no gas and grants no permission to spend. Sample vault positions
          are separate from your wallet assets.
        </p>
      </dialog>
    </WalletContext.Provider>
  );
}
export function useWallet() {
  const value = useContext(WalletContext);
  if (!value) throw new Error("WalletProvider is required.");
  return value;
}
export function WalletButton() {
  const { session, connectedAddress, open, status } = useWallet();
  const address = session?.address ?? connectedAddress;
  return (
    <button
      className="connectButton"
      type="button"
      onClick={open}
      aria-label={address ? "Manage wallet connection" : "Connect wallet"}
    >
      {status !== "idle"
        ? "Wallet pending…"
        : address
          ? `${address.slice(0, 6)}…${address.slice(-4)}`
          : "Connect wallet"}
    </button>
  );
}
