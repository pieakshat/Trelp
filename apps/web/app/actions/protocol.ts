"use server";

import { createPublicClient, getAddress, http } from "viem";
import { z } from "zod";
import { trancheVaultAbi } from "@/lib/contracts";
import { getVaultRuntimeConfig } from "@/lib/server/vault-config";
import {
  readVaultSnapshot,
  type VaultReader,
} from "@/lib/server/vault-service";

const stateInput = z.object({
  account: z
    .string()
    .regex(/^0x[0-9a-fA-F]{40}$/)
    .optional(),
});

function clientAndConfig() {
  const config = getVaultRuntimeConfig();
  if (!config) return null;
  return {
    config,
    // The snapshot is ~30 reads; batching keeps a public RPC from rate limiting.
    client: createPublicClient({
      transport: http(config.rpcUrl, { batch: true }),
    }),
  };
}

async function assertConfiguredChain(
  runtime: NonNullable<ReturnType<typeof clientAndConfig>>,
) {
  const rpcChainId = await runtime.client.getChainId();
  if (rpcChainId !== runtime.config.deployment.chainId)
    throw new Error(
      `RPC is on chain ${rpcChainId}, expected ${runtime.config.deployment.chainId}.`,
    );
}

export async function getVaultState(input: unknown = {}) {
  try {
    const parsed = stateInput.parse(input);
    const runtime = clientAndConfig();
    if (!runtime)
      return {
        ok: false as const,
        code: "not_configured" as const,
        error: "Add the deployed vault and RPC settings to load live data.",
      };
    await assertConfiguredChain(runtime);
    const reader: VaultReader = {
      read: (request) =>
        runtime.client.readContract(
          request as Parameters<typeof runtime.client.readContract>[0],
        ) as Promise<never>,
    };
    const [snapshot, block] = await Promise.all([
      readVaultSnapshot(
        reader,
        runtime.config.deployment,
        parsed.account ? getAddress(parsed.account) : undefined,
      ),
      runtime.client.getBlock(),
    ]);
    return {
      ok: true as const,
      snapshot: { ...snapshot, blockTimestamp: block.timestamp },
    };
  } catch (error) {
    return {
      ok: false as const,
      code: "read_failed" as const,
      error:
        error instanceof Error
          ? `Live vault data is unavailable: ${error.message}`
          : "Live vault data is unavailable.",
    };
  }
}

type ContractEvent = {
  eventName: string;
  args: Record<string, unknown>;
  blockNumber: bigint;
  transactionHash: `0x${string}`;
  logIndex: number;
};

export async function getVaultEvents() {
  try {
    const runtime = clientAndConfig();
    if (!runtime)
      return {
        ok: false as const,
        code: "not_configured" as const,
        error: "Add the deployed vault and RPC settings to load activity.",
      };
    await assertConfiguredChain(runtime);
    const logs = (await runtime.client.getContractEvents({
      address: runtime.config.deployment.address,
      abi: trancheVaultAbi,
      fromBlock: runtime.config.deployment.deploymentBlock,
      toBlock: "latest",
    })) as ContractEvent[];
    const events = logs
      .map((log) => ({
        id: `${log.transactionHash}:${log.logIndex}`,
        name: log.eventName,
        args: Object.fromEntries(
          Object.entries(log.args).map(([key, value]) => [
            key,
            typeof value === "bigint" ? value.toString() : value,
          ]),
        ),
        blockNumber: log.blockNumber.toString(),
        transactionHash: log.transactionHash,
        logIndex: log.logIndex,
      }))
      .sort(
        (a, b) =>
          Number(BigInt(b.blockNumber) - BigInt(a.blockNumber)) ||
          b.logIndex - a.logIndex,
      );
    return {
      ok: true as const,
      chainId: runtime.config.deployment.chainId,
      events,
    };
  } catch (error) {
    return {
      ok: false as const,
      code: "read_failed" as const,
      error:
        error instanceof Error
          ? `Vault activity is unavailable: ${error.message}`
          : "Vault activity is unavailable.",
    };
  }
}
