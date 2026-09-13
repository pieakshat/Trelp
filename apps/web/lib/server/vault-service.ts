import type { Abi, Address } from "viem";
import { erc20Abi, positionVenueAbi, trancheVaultAbi } from "../contracts";
import type { VaultPhase } from "../vault-domain";

export type VaultDeployment = {
  id: string;
  address: Address;
  chainId: number;
  deploymentBlock: bigint;
};

type ReadInput = {
  address: Address;
  abi: Abi;
  functionName: string;
  args?: readonly unknown[];
};

export type VaultReader = {
  read: <T>(input: ReadInput) => Promise<T>;
};

type VaultConfigRead = readonly [
  bigint,
  bigint,
  bigint,
  bigint,
  bigint,
  bigint,
  bigint,
  bigint,
  bigint,
  readonly [bigint, bigint, bigint, bigint, bigint, bigint],
  bigint,
  bigint,
  bigint,
  bigint,
  bigint,
];

export type VaultSnapshot = Awaited<ReturnType<typeof readVaultSnapshot>>;

async function optional<T>(read: () => Promise<T>) {
  try {
    return await read();
  } catch {
    return null;
  }
}

export async function readVaultSnapshot(
  reader: VaultReader,
  deployment: VaultDeployment,
  account?: Address,
) {
  const vault = deployment.address;
  const readVault = <T>(functionName: string) =>
    reader.read<T>({ address: vault, abi: trancheVaultAbi, functionName });
  const [
    phaseValue,
    quote,
    risky,
    senior,
    junior,
    curator,
    positionVenue,
    oracle,
    aqua,
    bufferStrategy,
    bufferApp,
    bufferShipped,
    shippedQuote,
    nav,
    seniorPot,
    juniorPot,
    unwindCost,
    rebalanceCost,
    rebalanceCount,
    lastRebalanceAt,
    config,
  ] = await Promise.all([
    readVault<number>("phase"),
    readVault<Address>("quote"),
    readVault<Address>("risky"),
    readVault<Address>("senior"),
    readVault<Address>("junior"),
    readVault<Address>("curator"),
    readVault<Address>("positionVenue"),
    readVault<Address>("oracle"),
    readVault<Address>("aqua"),
    readVault<Address>("bufferStrategy"),
    readVault<Address>("bufferApp"),
    readVault<boolean>("bufferShipped"),
    readVault<bigint>("shippedQuote"),
    readVault<bigint>("nav"),
    readVault<bigint>("seniorPot"),
    readVault<bigint>("juniorPot"),
    readVault<bigint>("unwindCost"),
    readVault<bigint>("rebalanceCost"),
    readVault<number>("rebalanceCount"),
    readVault<bigint>("lastRebalanceAt"),
    readVault<VaultConfigRead>("config"),
  ]);
  if (![0, 1, 2, 3].includes(phaseValue))
    throw new Error("The vault returned an unknown phase.");
  const phase = phaseValue as VaultPhase;
  const tokenRead = <T>(
    address: Address,
    functionName: string,
    args?: readonly unknown[],
  ) =>
    reader.read<T>({
      address,
      abi: erc20Abi,
      functionName,
      ...(args ? { args } : {}),
    });
  const [quoteSymbol, riskySymbol, decimals, seniorSupply, juniorSupply] =
    await Promise.all([
      tokenRead<string>(quote, "symbol"),
      tokenRead<string>(risky, "symbol"),
      tokenRead<number>(quote, "decimals"),
      tokenRead<bigint>(senior, "totalSupply"),
      tokenRead<bigint>(junior, "totalSupply"),
    ]);
  const terms =
    phase === 0
      ? null
      : await readVault<
          readonly [bigint, bigint, bigint, bigint, bigint, bigint]
        >("terms").then(
          ([
            seniorPrincipal,
            juniorPrincipal,
            couponWad,
            feeSplitWad,
            start,
            duration,
          ]) => ({
            seniorPrincipal,
            juniorPrincipal,
            couponWad,
            feeSplitWad,
            start,
            duration,
          }),
        );
  const cancelled = phase === 3 && terms?.duration === 0n;
  const [seniorClaim, coverageWad, juniorShareWad] =
    phase === 0 || cancelled
      ? [null, null, null]
      : await Promise.all([
          readVault<bigint>("seniorClaim"),
          readVault<bigint>("coverageWad"),
          readVault<bigint>("juniorShareWad"),
        ]);
  const [seniorSettlementSupply, juniorSettlementSupply] =
    phase === 3
      ? await Promise.all([
          readVault<bigint>("seniorSupplyAtSettlement"),
          readVault<bigint>("juniorSupplyAtSettlement"),
        ])
      : [null, null];
  const accountState = account
    ? await Promise.all([
        tokenRead<bigint>(quote, "balanceOf", [account]),
        tokenRead<bigint>(quote, "allowance", [account, vault]),
        tokenRead<bigint>(senior, "balanceOf", [account]),
        tokenRead<bigint>(junior, "balanceOf", [account]),
      ]).then(([quoteBalance, allowance, seniorBalance, juniorBalance]) => ({
        address: account,
        quoteBalance,
        allowance,
        seniorBalance,
        juniorBalance,
      }))
    : null;
  const position =
    positionVenue === "0x0000000000000000000000000000000000000000"
      ? null
      : {
          address: positionVenue,
          value: await reader.read<bigint>({
            address: positionVenue,
            abi: positionVenueAbi,
            functionName: "valueInQuote",
          }),
          tickLower: await optional(() =>
            reader.read<number>({
              address: positionVenue,
              abi: positionVenueAbi,
              functionName: "tickLower",
            }),
          ),
          tickUpper: await optional(() =>
            reader.read<number>({
              address: positionVenue,
              abi: positionVenueAbi,
              functionName: "tickUpper",
            }),
          ),
          liquidity: await optional(() =>
            reader.read<bigint>({
              address: positionVenue,
              abi: positionVenueAbi,
              functionName: "liquidity",
            }),
          ),
        };

  return {
    deployment,
    phase,
    quote: { address: quote, symbol: quoteSymbol, decimals },
    risky: { address: risky, symbol: riskySymbol },
    senior: {
      address: senior,
      supply: seniorSettlementSupply ?? seniorSupply,
      liveSupply: seniorSupply,
    },
    junior: {
      address: junior,
      supply: juniorSettlementSupply ?? juniorSupply,
      liveSupply: juniorSupply,
    },
    terms,
    nav,
    seniorClaim,
    coverageWad,
    juniorShareWad,
    seniorPot,
    juniorPot,
    unwindCost,
    rebalanceCost,
    rebalanceCount,
    lastRebalanceAt,
    config: {
      minRebalanceCoverageWad: config[7],
      subscriptionEnd: config[10],
      rebalanceCooldown: config[14],
    },
    buffer: {
      strategy: bufferStrategy,
      app: bufferApp,
      shipped: bufferShipped,
      amount: shippedQuote,
    },
    contracts: { vault, curator, oracle, aqua },
    position,
    account: accountState,
  };
}
