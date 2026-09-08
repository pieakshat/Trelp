// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {LPFeeLibrary} from "@uniswap/v4-core/src/libraries/LPFeeLibrary.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "@uniswap/v4-core/src/types/BeforeSwapDelta.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";

import {IVaultPolicy} from "../interfaces/IVaultPolicy.sol";
import {RiskPolicy} from "../libraries/RiskPolicy.sol";

/// @title TrancheHook
/// @notice Enforces the vault's solvency policy at the pool boundary.
///
/// @dev The pricing curve lives in `RiskPolicy` and is shared with the Aqua venue, so this hook
///      only applies it, in three places:
///
///      1. `beforeAddLiquidity` gates the pool to the vault's venue. Outside liquidity would dilute
///         senior's claim on fee income, so sole-LP is structural rather than conventional.
///      2. `beforeSwap` overrides the LP fee from the policy's spread, giving up fee income to cut
///         adverse selection as coverage thins.
///      3. `beforeSwap` refuses swaps that would push more risky inventory onto the vault once the
///         policy stops bidding.
///
///      The third is a hard stop, not a price signal, because a v4 dynamic fee is symmetric and
///      cannot skew. The alternative — re-minting the range above spot — pins the pool price: with
///      no depth below it cannot trade down, the quote goes stale against the market, and whoever
///      trades first on re-arming collects the accumulated gap. A directional refusal keeps quoting
///      the side that reduces risk and declines the side that increases it.
///
///      Required address flags: BEFORE_ADD_LIQUIDITY_FLAG | BEFORE_SWAP_FLAG == 0x880. The pool
///      must also be initialised with `LPFeeLibrary.DYNAMIC_FEE_FLAG` or the override is ignored.
contract TrancheHook is IHooks {
    using LPFeeLibrary for uint24;

    error NotPoolManager();
    error HookNotImplemented();
    error LiquidityGated(address sender);
    error BiddingHalted();
    error InvalidHookAddress(uint160 actual, uint160 expected);
    error NotAdmin();
    error VenueAlreadySet();
    error PoolAssetsMismatch();
    error WrongHook();

    event FeeOverridden(uint24 feePips, bool bidAllowed);

    /// @dev 1e18 spread -> 1e6 pips, so a WAD spread divides down by 1e12.
    uint256 internal constant WAD_TO_PIPS = 1e12;

    /// @dev `LPFeeLibrary.MAX_LP_FEE` is 100%, which is a denial of service dressed as a price.
    ///      10% is already far outside normal flow.
    uint24 internal constant MAX_OVERRIDE_PIPS = 100_000;

    uint160 internal constant REQUIRED_FLAGS = Hooks.BEFORE_ADD_LIQUIDITY_FLAG | Hooks.BEFORE_SWAP_FLAG;

    IPoolManager public immutable poolManager;
    IVaultPolicy public immutable vault;
    address public immutable admin;

    /// @dev Not immutable: the venue needs a PoolKey naming this hook, so the hook exists first.
    ///      Settable once; the mined address commits to everything else.
    address public venue;

    /// @dev Derived from the pool key at wiring time, never supplied. It decides which swap
    ///      direction the halt applies to, so a wrong value would refuse the de-risking side and
    ///      permit the risk-increasing one — silently, and exactly backwards.
    bool public riskyIsCurrency0;

    modifier onlyPoolManager() {
        if (msg.sender != address(poolManager)) revert NotPoolManager();
        _;
    }

    constructor(IPoolManager poolManager_, IVaultPolicy vault_, address admin_) {
        uint160 flags = uint160(address(this)) & Hooks.ALL_HOOK_MASK;
        if (flags != REQUIRED_FLAGS) revert InvalidHookAddress(flags, REQUIRED_FLAGS);

        poolManager = poolManager_;
        vault = vault_;
        admin = admin_;
    }

    /// @notice Name the venue permitted to provide liquidity, and learn the pool's asset ordering.
    /// @dev One-time. The ordering is read off the key and checked against the vault's own assets,
    ///      so the directional halt cannot be inverted by a bad deployment argument.
    function setVenue(address venue_, PoolKey calldata key) external {
        if (msg.sender != admin) revert NotAdmin();
        if (venue != address(0)) revert VenueAlreadySet();
        if (address(key.hooks) != address(this)) revert WrongHook();

        address c0 = Currency.unwrap(key.currency0);
        address c1 = Currency.unwrap(key.currency1);
        address q = vault.quote();
        address r = vault.risky();
        if (!((c0 == q && c1 == r) || (c0 == r && c1 == q))) revert PoolAssetsMismatch();

        venue = venue_;
        riskyIsCurrency0 = (c0 == r);
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
