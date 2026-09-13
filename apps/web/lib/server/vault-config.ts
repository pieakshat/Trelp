import { getAddress } from "viem";
import { z } from "zod";

const deploymentSchema = z.object({
  TRELP_CHAIN_ID: z.coerce.number().int().positive(),
  TRELP_VAULT_ADDRESS: z.string().regex(/^0x[0-9a-fA-F]{40}$/),
  TRELP_DEPLOYMENT_BLOCK: z.coerce.bigint().nonnegative(),
  TRELP_RPC_URL: z.url(),
  TRELP_VAULT_ID: z.string().trim().min(1).max(80).optional(),
});

export function parseVaultDeployment(env: Record<string, string | undefined>) {
  const keys = [
    "TRELP_CHAIN_ID",
    "TRELP_VAULT_ADDRESS",
    "TRELP_DEPLOYMENT_BLOCK",
    "TRELP_RPC_URL",
  ] as const;
  if (keys.every((key) => !env[key])) return null;
  const parsed = deploymentSchema.parse(env);
  return {
    deployment: {
      id: parsed.TRELP_VAULT_ID ?? "vault",
      address: getAddress(parsed.TRELP_VAULT_ADDRESS),
      chainId: parsed.TRELP_CHAIN_ID,
      deploymentBlock: parsed.TRELP_DEPLOYMENT_BLOCK,
    },
    rpcUrl: new URL(parsed.TRELP_RPC_URL).toString(),
  };
}

export function getVaultRuntimeConfig() {
  return parseVaultDeployment(process.env);
}
