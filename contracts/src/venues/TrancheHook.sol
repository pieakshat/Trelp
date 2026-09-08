// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {LPFeeLibrary} from "v4-core/src/libraries/LPFeeLibrary.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "v4-core/src/types/BeforeSwapDelta.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";

import {RiskPolicy} from "../libraries/RiskPolicy.sol";

interface ITrancheVaultPolicy {
    function riskQuote() external view returns (RiskPolicy.Quote memory);
}

/// @title TrancheHook
/// @notice Enforces the vault's solvency policy at the pool boundary.
///
/// @dev Three jobs, deliberately no more. The original plan put a three-stage breaker in the hook;
///      the pricing curve now lives in `RiskPolicy` and is shared with the Aqua venue, so all this
///      contract does is apply it:
///
///      1. `beforeAddLiquidity` gates the pool to the vault's venue. Outside liquidity would dilute
///         senior's claim on fee income, so the vault is the sole LP by construction rather than by
///         convention.
///      2. `beforeSwap` overrides the LP fee from the policy's spread. As coverage thins the pool
///         gives up fee income to cut adverse selection.
///      3. `beforeSwap` refuses swaps that would push more of the risky asset onto the vault once
///         the policy stops bidding.
///
///      That third job is worth spelling out. A v4 dynamic fee is symmetric and cannot skew, which
///      is why the original plan reached for burning and re-minting the range above spot. That hack
///      pins the pool price -- with no depth below, the pool simply cannot trade down, the quote
///      goes stale against the outside market, and whoever trades first when it is re-armed
///      collects the whole accumulated gap. A directional refusal achieves the same intent ("buyers
///      may buy from us, nobody may sell to us") with no position churn and no stale quote: the
///      pool keeps quoting the side that reduces our risk and declines the side that increases it.
///      It is a hard stop rather than a price signal, and it is honest about being one.
///
///      REQUIRED ADDRESS FLAGS: BEFORE_ADD_LIQUIDITY_FLAG | BEFORE_SWAP_FLAG == 0x880.
///      The pool must also be initialised with `LPFeeLibrary.DYNAMIC_FEE_FLAG` or the fee override
///      is ignored.
contract TrancheHook is IHooks {
    using LPFeeLibrary for uint24;

    error NotPoolManager();
    error HookNotImplemented();
    error LiquidityGated(address sender);
    error BiddingHalted();
    error InvalidHookAddress(uint160 actual, uint160 expected);

    event FeeOverridden(uint24 feePips, bool bidAllowed);

    /// @dev 1e18 spread -> 1e6 pips, so a WAD spread divides down by 1e12.
    uint256 internal constant WAD_TO_PIPS = 1e12;

    /// @dev Ceiling on the overridden fee. `LPFeeLibrary.MAX_LP_FEE` is 100%, which would be a
    ///      denial of service dressed up as a price; 10% is already far outside normal flow.
    uint24 internal constant MAX_OVERRIDE_PIPS = 100_000;

    uint160 internal constant REQUIRED_FLAGS = Hooks.BEFORE_ADD_LIQUIDITY_FLAG | Hooks.BEFORE_SWAP_FLAG;

    IPoolManager public immutable poolManager;
    ITrancheVaultPolicy public immutable vault;
    address public immutable venue;
    bool public immutable riskyIsCurrency0;

    modifier onlyPoolManager() {
        if (msg.sender != address(poolManager)) revert NotPoolManager();
        _;
    }

    constructor(IPoolManager poolManager_, ITrancheVaultPolicy vault_, address venue_, bool riskyIsCurrency0_) {
        uint160 flags = uint160(address(this)) & Hooks.ALL_HOOK_MASK;
        if (flags != REQUIRED_FLAGS) revert InvalidHookAddress(flags, REQUIRED_FLAGS);

        poolManager = poolManager_;
        vault = vault_;
        venue = venue_;
        riskyIsCurrency0 = riskyIsCurrency0_;
    }

    // ---------------------------------------------------------------- active hooks

    /// @notice Only the vault's venue may provide liquidity to this pool.
    function beforeAddLiquidity(
        address sender,
        PoolKey calldata,
        IPoolManager.ModifyLiquidityParams calldata,
        bytes calldata
    ) external view onlyPoolManager returns (bytes4) {
        if (sender != venue) revert LiquidityGated(sender);
        return IHooks.beforeAddLiquidity.selector;
    }

    /// @notice Price the swap off the vault's current solvency, and refuse the risk-increasing
    ///         direction once the policy has stopped bidding.
    function beforeSwap(
        address,
        PoolKey calldata,
        IPoolManager.SwapParams calldata params,
        bytes calldata
    ) external onlyPoolManager returns (bytes4, BeforeSwapDelta, uint24) {
        RiskPolicy.Quote memory q = vault.riskQuote();

        // zeroForOne: the taker gives currency0 and takes currency1, so the pool ACQUIRES
        // currency0. The pool takes on more risky inventory exactly when the currency it acquires
        // is the risky one.
        bool poolAcquiresRisky = (params.zeroForOne == riskyIsCurrency0);
        if (poolAcquiresRisky && !q.bidAllowed) revert BiddingHalted();

        uint24 feePips = _feePips(q.spreadWad);
        emit FeeOverridden(feePips, q.bidAllowed);

        return (
            IHooks.beforeSwap.selector,
            BeforeSwapDeltaLibrary.ZERO_DELTA,
            feePips | LPFeeLibrary.OVERRIDE_FEE_FLAG
        );
    }

    function _feePips(uint256 spreadWad) internal pure returns (uint24) {
        uint256 pips = spreadWad / WAD_TO_PIPS;
        return pips > MAX_OVERRIDE_PIPS ? MAX_OVERRIDE_PIPS : uint24(pips);
    }

    // ---------------------------------------------------------------- unused hooks

    function beforeInitialize(address, PoolKey calldata, uint160) external pure returns (bytes4) {
        revert HookNotImplemented();
    }

    function afterInitialize(address, PoolKey calldata, uint160, int24) external pure returns (bytes4) {
        revert HookNotImplemented();
    }

    function afterAddLiquidity(
        address,
        PoolKey calldata,
        IPoolManager.ModifyLiquidityParams calldata,
        BalanceDelta,
        BalanceDelta,
        bytes calldata
    ) external pure returns (bytes4, BalanceDelta) {
        revert HookNotImplemented();
    }

    function beforeRemoveLiquidity(
        address,
        PoolKey calldata,
        IPoolManager.ModifyLiquidityParams calldata,
        bytes calldata
    ) external pure returns (bytes4) {
        revert HookNotImplemented();
    }

    function afterRemoveLiquidity(
        address,
        PoolKey calldata,
        IPoolManager.ModifyLiquidityParams calldata,
        BalanceDelta,
        BalanceDelta,
        bytes calldata
    ) external pure returns (bytes4, BalanceDelta) {
        revert HookNotImplemented();
    }

    function afterSwap(address, PoolKey calldata, IPoolManager.SwapParams calldata, BalanceDelta, bytes calldata)
        external
        pure
        returns (bytes4, int128)
    {
        revert HookNotImplemented();
    }

    function beforeDonate(address, PoolKey calldata, uint256, uint256, bytes calldata)
        external
        pure
        returns (bytes4)
    {
        revert HookNotImplemented();
    }

    function afterDonate(address, PoolKey calldata, uint256, uint256, bytes calldata)
        external
        pure
        returns (bytes4)
    {
        revert HookNotImplemented();
    }
}
