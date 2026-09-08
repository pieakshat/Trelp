// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/src/utils/SafeTransferLib.sol";

import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IUnlockCallback} from "@uniswap/v4-core/src/interfaces/callback/IUnlockCallback.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {RangeMath} from "../libraries/RangeMath.sol";

import {IPositionVenue} from "../interfaces/IPositionVenue.sol";
import {IQuoteOracle} from "../interfaces/IQuoteOracle.sol";

/// @notice Converts between the two pool currencies at or near spot.
/// @dev Abstracted so the venue does not hard-code a router: on a mainnet fork this is backed by
///      existing ETH/USDC liquidity, and by a mock in unit tests. The vault's pool is fresh and
///      empty at activation, so it cannot be used to acquire its own seed.
interface ISpotSwapper {
    function swapExactIn(address tokenIn, address tokenOut, uint256 amountIn, uint256 minOut)
        external
        returns (uint256 amountOut);
}

interface ITrancheVaultClaim {
    function seniorClaim() external view returns (uint256);
}

/// @title V4PositionVenue
/// @notice Holds the vault's Uniswap v4 position and enforces the range covenant.
///
/// @dev SEEDING. Subscription takes quote only, but a range straddling spot needs both currencies,
///      and our own pool is empty until we mint into it. So `deploy` converts part of the quote
///      through an external spot venue first, then mints. That conversion is a real cost and is
///      visible to the vault as the gap between capital deployed and position value.
///
///      RANGE COVENANT. The curator may move the range, but only to one whose value at its OWN
///      lower bound still covers the senior claim with margin. Below `tickLower` the position is
///      100% of the risky asset and its value falls linearly rather than by square root, so the
///      cushion disappears exactly where senior needs it -- which is why the covenant is written
///      against the floor rather than against spot. The vault enforces the policy half (coverage
///      floor, cooldown, cost accounting); only this contract knows the range.
contract V4PositionVenue is IPositionVenue, IUnlockCallback {
    using SafeTransferLib for ERC20;
    using StateLibrary for IPoolManager;
    using PoolIdLibrary for PoolKey;

    error NotVault();
    error NotPoolManager();
    error AlreadyDeployed();
    error NothingDeployed();
    error FloorCovenantBreached(uint256 floorValue, uint256 required);
    error InvalidRange(int24 tickLower, int24 tickUpper);

    event Deployed(uint256 quoteIn, uint256 riskyAcquired, uint128 liquidity);
    event RangeMoved(int24 tickLower, int24 tickUpper, uint128 liquidity, uint256 floorValue);
    event Unwound(uint256 quoteOut, uint256 riskyOut);

    enum Action {
        Mint,
        Burn
    }

    IPoolManager public immutable poolManager;
    address public immutable vault;
    ERC20 public immutable quote;
    ERC20 public immutable risky;
    IQuoteOracle public immutable oracle;
    ISpotSwapper public immutable swapper;

    /// @dev Nominal liquidity used only to read the range's composition ratio. Large enough that
    ///      neither leg truncates to zero at realistic prices; the ratio itself is scale-invariant.
    uint128 internal constant PROBE_LIQUIDITY = 1e24;

    /// @notice Extra coverage the range must preserve at its own floor, in WAD.
    uint256 public immutable floorMarginWad;

    PoolKey public poolKey;
    int24 public tickLower;
    int24 public tickUpper;
    uint128 public liquidity;

    modifier onlyVault() {
        if (msg.sender != vault) revert NotVault();
        _;
    }

    constructor(
        IPoolManager poolManager_,
        PoolKey memory poolKey_,
        address vault_,
        ERC20 quote_,
        ERC20 risky_,
        IQuoteOracle oracle_,
        ISpotSwapper swapper_,
        int24 tickLower_,
        int24 tickUpper_,
        uint256 floorMarginWad_
    ) {
        if (tickLower_ >= tickUpper_) revert InvalidRange(tickLower_, tickUpper_);
        poolManager = poolManager_;
        poolKey = poolKey_;
        vault = vault_;
        quote = quote_;
        risky = risky_;
        oracle = oracle_;
        swapper = swapper_;
        tickLower = tickLower_;
        tickUpper = tickUpper_;
        floorMarginWad = floorMarginWad_;
    }

    // ---------------------------------------------------------------- deploy

    /// @inheritdoc IPositionVenue
    function deploy(uint256 quoteAmount) external onlyVault {
        if (liquidity != 0) revert AlreadyDeployed();

        (uint160 sqrtPriceX96,,,) = poolManager.getSlot0(poolKey.toId());
        uint160 sqrtLower = TickMath.getSqrtPriceAtTick(tickLower);
        uint160 sqrtUpper = TickMath.getSqrtPriceAtTick(tickUpper);

        // Split the quote so the two legs land in the ratio the range wants at the current price,
        // then acquire the risky leg externally. Our own pool is empty and cannot fill this.
        uint256 quoteForRisky = _quoteShareForRiskyLeg(quoteAmount, sqrtPriceX96, sqrtLower, sqrtUpper);
        uint256 riskyAcquired;
        if (quoteForRisky != 0) {
            quote.safeApprove(address(swapper), quoteForRisky);
            riskyAcquired = swapper.swapExactIn(address(quote), address(risky), quoteForRisky, 0);
        }

        (uint256 amount0, uint256 amount1) = _sortAmounts(quoteAmount - quoteForRisky, riskyAcquired);
        uint128 target = RangeMath.getLiquidityForAmounts(
            sqrtPriceX96, sqrtLower, sqrtUpper, amount0, amount1
        );

        _modify(int256(uint256(target)));
        liquidity = target;
        emit Deployed(quoteAmount, riskyAcquired, target);
    }

    // ---------------------------------------------------------------- marking

    /// @inheritdoc IPositionVenue
    function valueInQuote() external view returns (uint256) {
        if (liquidity == 0) return _idleValue();
        (uint160 sqrtPriceX96,,,) = poolManager.getSlot0(poolKey.toId());
        (uint256 amount0, uint256 amount1) = RangeMath.amountsForLiquidity(
            sqrtPriceX96,
            TickMath.getSqrtPriceAtTick(tickLower),
            TickMath.getSqrtPriceAtTick(tickUpper),
            liquidity
        );
        return _valueOf(amount0, amount1) + _idleValue();
    }

    /// @notice What the position would be worth at the bound where it holds only the risky asset.
    /// @dev The covenant is written against this number because past that bound the position is
    ///      fully converted and loses value linearly, with no square-root cushion left.
    ///
    ///      Which bound that is depends on token ordering, not on intuition: a pool price is
    ///      currency1 per currency0, so the risky asset getting cheaper moves price DOWN when risky
    ///      is currency0 and UP when it is currency1. Reading the lower tick unconditionally would
    ///      measure the safe end of the range in half of all deployments and pass a covenant that
    ///      protects nothing.
    function floorValue() public view returns (uint256) {
        if (liquidity == 0) return 0;
        (uint256 amount0, uint256 amount1) = RangeMath.amountsAtRiskyBound(
            TickMath.getSqrtPriceAtTick(tickLower),
            TickMath.getSqrtPriceAtTick(tickUpper),
            liquidity,
            Currency.unwrap(poolKey.currency0) == address(risky)
        );
        return _valueOf(amount0, amount1);
    }

    // ---------------------------------------------------------------- range authority

    /// @inheritdoc IPositionVenue
    function rebalance(bytes calldata venueData) external onlyVault {
        if (liquidity == 0) revert NothingDeployed();
        (int24 newLower, int24 newUpper) = abi.decode(venueData, (int24, int24));
        if (newLower >= newUpper) revert InvalidRange(newLower, newUpper);

        _modify(-int256(uint256(liquidity)));

        tickLower = newLower;
        tickUpper = newUpper;

        (uint160 sqrtPriceX96,,,) = poolManager.getSlot0(poolKey.toId());
        (uint256 have0, uint256 have1) = _sortAmounts(quote.balanceOf(address(this)), risky.balanceOf(address(this)));
        uint128 target = RangeMath.getLiquidityForAmounts(
            sqrtPriceX96,
            TickMath.getSqrtPriceAtTick(newLower),
            TickMath.getSqrtPriceAtTick(newUpper),
            have0,
            have1
        );

        _modify(int256(uint256(target)));
        liquidity = target;

        uint256 floor = floorValue();
        uint256 required = (ITrancheVaultClaim(vault).seniorClaim() * (1e18 + floorMarginWad)) / 1e18;
        if (floor < required) revert FloorCovenantBreached(floor, required);

        emit RangeMoved(newLower, newUpper, target, floor);
    }

    // ---------------------------------------------------------------- unwind

    /// @inheritdoc IPositionVenue
    /// @dev Returns both currencies to the vault rather than selling the risky leg here. Settlement
    ///      liquidates by quoting over the unwind window; a market sell inside this call would be an
    ///      unpriced, unbounded action at a time everyone can predict.
    function unwind() external onlyVault returns (uint256 quoteReturned) {
        if (liquidity != 0) {
            _modify(-int256(uint256(liquidity)));
            liquidity = 0;
        }

        quoteReturned = quote.balanceOf(address(this));
        uint256 riskyOut = risky.balanceOf(address(this));
        if (quoteReturned != 0) quote.safeTransfer(vault, quoteReturned);
        if (riskyOut != 0) risky.safeTransfer(vault, riskyOut);

        emit Unwound(quoteReturned, riskyOut);
    }

    // ---------------------------------------------------------------- pool plumbing

    function _modify(int256 liquidityDelta) internal {
        poolManager.unlock(abi.encode(liquidityDelta));
    }

    function unlockCallback(bytes calldata data) external returns (bytes memory) {
        if (msg.sender != address(poolManager)) revert NotPoolManager();
        int256 liquidityDelta = abi.decode(data, (int256));

        (BalanceDelta delta,) = poolManager.modifyLiquidity(
            poolKey,
            IPoolManager.ModifyLiquidityParams({
                tickLower: tickLower,
                tickUpper: tickUpper,
                liquidityDelta: liquidityDelta,
                salt: bytes32(0)
            }),
            ""
        );

        _resolve(poolKey.currency0, delta.amount0());
        _resolve(poolKey.currency1, delta.amount1());
        return "";
    }

    /// @dev Negative delta means we owe the pool; positive means the pool owes us.
    function _resolve(Currency currency, int128 amount) internal {
        if (amount < 0) {
            uint256 owed = uint256(uint128(-amount));
            poolManager.sync(currency);
            ERC20(Currency.unwrap(currency)).safeTransfer(address(poolManager), owed);
            poolManager.settle();
        } else if (amount > 0) {
            poolManager.take(currency, address(this), uint256(uint128(amount)));
        }
    }

    // ---------------------------------------------------------------- helpers

    function _sortAmounts(uint256 quoteAmount, uint256 riskyAmount)
        internal
        view
        returns (uint256 amount0, uint256 amount1)
    {
        return Currency.unwrap(poolKey.currency0) == address(quote)
            ? (quoteAmount, riskyAmount)
            : (riskyAmount, quoteAmount);
    }

    function _valueOf(uint256 amount0, uint256 amount1) internal view returns (uint256) {
        (uint256 quoteAmount, uint256 riskyAmount) = Currency.unwrap(poolKey.currency0) == address(quote)
            ? (amount0, amount1)
            : (amount1, amount0);
        return quoteAmount + (riskyAmount == 0 ? 0 : oracle.valueInQuote(address(risky), riskyAmount));
    }

    function _idleValue() internal view returns (uint256) {
        return _valueOf(
            Currency.unwrap(poolKey.currency0) == address(quote)
                ? quote.balanceOf(address(this))
                : risky.balanceOf(address(this)),
            Currency.unwrap(poolKey.currency0) == address(quote)
                ? risky.balanceOf(address(this))
                : quote.balanceOf(address(this))
        );
    }

    /// @dev Fraction of the deposit that must become the risky leg for the range's ratio at spot.
    /// @dev Computed from the ratio the range wants, not from a liquidity probe. Probing with
    ///      quote-only amounts returns zero liquidity, because `getLiquidityForAmounts` takes the
    ///      MINIMUM of the two single-sided answers and the missing leg pins it to zero.
    ///      Evaluating a nominal liquidity and valuing both legs is scale-invariant and well
    ///      behaved everywhere inside the range.
    function _quoteShareForRiskyLeg(
        uint256 quoteAmount,
        uint160 sqrtPriceX96,
        uint160 sqrtLower,
        uint160 sqrtUpper
    ) internal view returns (uint256) {
        if (sqrtPriceX96 <= sqrtLower) {
            // Position would be entirely currency0 at this price.
            return Currency.unwrap(poolKey.currency0) == address(quote) ? 0 : quoteAmount;
        }
        if (sqrtPriceX96 >= sqrtUpper) {
            // Position would be entirely currency1.
            return Currency.unwrap(poolKey.currency0) == address(quote) ? quoteAmount : 0;
        }

        (uint256 probe0, uint256 probe1) = RangeMath.amountsForLiquidity(
            sqrtPriceX96, sqrtLower, sqrtUpper, PROBE_LIQUIDITY
        );
        (uint256 quoteLeg, uint256 riskyLeg) = Currency.unwrap(poolKey.currency0) == address(quote)
            ? (probe0, probe1)
            : (probe1, probe0);

        uint256 riskyLegValue = riskyLeg == 0 ? 0 : oracle.valueInQuote(address(risky), riskyLeg);
        uint256 total = quoteLeg + riskyLegValue;
        if (total == 0) return 0;
        return (quoteAmount * riskyLegValue) / total;
    }
}
