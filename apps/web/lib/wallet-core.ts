import type { PrivyClientConfig } from "@privy-io/react-auth";
import type { Hash } from "viem";
import { anvil, base, baseSepolia, mainnet, sepolia } from "viem/chains";

export type WalletProviderRequest = {
  method: string;
  params?: unknown[];
};

export type EvmProvider = {
  request: (input: WalletProviderRequest) => Promise<unknown>;
};

export type ContractTransaction = {
  chainId: number;
  to: `0x${string}`;
  data: `0x${string}`;
};

export type ConfirmedReceipt = {
  hash: Hash;
  blockNumber: bigint;
  gasUsed: bigint;
  fee: bigint | null;
};

const chains = [mainnet, base, baseSepolia, sepolia, anvil] as const;
type PrivyChain = NonNullable<PrivyClientConfig["defaultChain"]>;

export function privyChain(chainId: number): PrivyChain {
  const chain = chains.find(({ id }) => id === chainId);
  if (!chain)
    throw new Error(`Privy is not configured for chain ${chainId || "—"}.`);
  return {
    id: chain.id,
    name: chain.name,
    nativeCurrency: chain.nativeCurrency,
    rpcUrls: chain.rpcUrls,
    ...(chain.blockExplorers ? { blockExplorers: chain.blockExplorers } : {}),
    ...(chain.testnet === undefined ? {} : { testnet: chain.testnet }),
  };
}

export function privyChainId(value: string) {
  const match = /^eip155:(\d+)$/.exec(value);
  if (!match) throw new Error("Privy returned an invalid network.");
  const chainId = Number(match[1]);
  if (!Number.isSafeInteger(chainId))
    throw new Error("Privy returned an invalid network.");
  return chainId;
}

export async function sendPrivyTransaction(
  provider: EvmProvider,
  address: string,
  request: ContractTransaction,
) {
  const accounts = await provider.request({ method: "eth_accounts" });
  if (
    !Array.isArray(accounts) ||
    typeof accounts[0] !== "string" ||
    accounts[0].toLowerCase() !== address.toLowerCase()
  )
    throw new Error("The Privy wallet account changed. Review and try again.");
  const hash = await provider.request({
    method: "eth_sendTransaction",
    params: [{ from: address, to: request.to, data: request.data }],
  });
  if (typeof hash !== "string" || !/^0x[0-9a-fA-F]{64}$/.test(hash))
    throw new Error("Privy returned an invalid transaction hash.");
  return hash as Hash;
}

export async function waitForConfirmedReceipt(
  provider: EvmProvider,
  hash: Hash,
  refresh: () => Promise<void>,
): Promise<ConfirmedReceipt> {
  for (let attempt = 0; attempt < 120; attempt++) {
    const receipt = await provider.request({
      method: "eth_getTransactionReceipt",
      params: [hash],
    });
    if (receipt && typeof receipt === "object" && "status" in receipt) {
      const result = receipt as Record<string, unknown>;
      if (result.status === "0x0")
        throw new Error("The transaction reverted on-chain.");
      if (result.status !== "0x1")
        throw new Error("Privy returned an invalid receipt.");
      if (
        typeof result.blockNumber !== "string" ||
        !/^0x[0-9a-f]+$/i.test(result.blockNumber) ||
        typeof result.gasUsed !== "string" ||
        !/^0x[0-9a-f]+$/i.test(result.gasUsed)
      )
        throw new Error("Privy returned an invalid receipt.");
      const gasUsed = BigInt(result.gasUsed);
      const gasPrice =
        typeof result.effectiveGasPrice === "string" &&
        /^0x[0-9a-f]+$/i.test(result.effectiveGasPrice)
          ? BigInt(result.effectiveGasPrice)
          : null;
      const confirmed = {
        hash,
        blockNumber: BigInt(result.blockNumber),
        gasUsed,
        fee: gasPrice === null ? null : gasUsed * gasPrice,
      };
      try {
        await refresh();
      } catch {
        // The receipt is authoritative; a failed read refresh must not relabel the write.
      }
      return confirmed;
    }
    await new Promise((resolve) => setTimeout(resolve, 1_000));
  }
  throw new Error("The transaction is still pending. Check your wallet.");
}
