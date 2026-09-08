// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ERC20} from "solmate/src/tokens/ERC20.sol";

import {IAquaRegistry} from "../../src/interfaces/IAquaRegistry.sol";
import {IBufferStrategy} from "../../src/interfaces/IBufferStrategy.sol";
import {IPositionVenue} from "../../src/interfaces/IPositionVenue.sol";
import {IQuoteOracle} from "../../src/interfaces/IQuoteOracle.sol";
import {ISpotSwapper} from "../../src/interfaces/ISpotSwapper.sol";
import {IUniswapV3PoolObserver} from "../../src/oracles/UniswapV3TwapOracle.sol";

contract MockERC20 is ERC20 {
    constructor(string memory n, string memory s, uint8 d) ERC20(n, s, d) {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external {
        _burn(from, amount);
    }
}

/// @dev Assumes the priced token has 18 decimals: the `1e18` divisor below is that token's scale,
///      not a WAD. Fine for the WETH-like fixtures here, wrong for anything else — not a template
///      for a real oracle, which must read the token's own decimals.
contract MockOracle is IQuoteOracle {
    /// @dev quote base units per 1e18 of the priced token
    mapping(address => uint256) public priceWad;

    function setPrice(address token, uint256 p) external {
        priceWad[token] = p;
    }

    function valueInQuote(address token, uint256 amount) external view returns (uint256) {
        return (amount * priceWad[token]) / 1e18;
    }
}

/// @dev Stands in for the Uniswap v4 leg. `setValue` marks the position and moves real quote so the
///      mock's balance always matches its reported value, which keeps unwind honest.
contract MockPositionVenue is IPositionVenue {
    MockERC20 public immutable quote;
    address public immutable vault;
    uint256 internal _value;
    uint256 internal _rebalanceLoss;
    uint256 public rebalanceCalls;

    constructor(MockERC20 quote_, address vault_) {
        quote = quote_;
        vault = vault_;
    }

    function deploy(uint256 quoteAmount) external {
        _value += quoteAmount;
    }

    function setValue(uint256 v) external {
        uint256 bal = quote.balanceOf(address(this));
        if (v > bal) quote.mint(address(this), v - bal);
        else if (v < bal) quote.burn(address(this), bal - v);
        _value = v;
    }

    function setRebalanceLoss(uint256 loss) external {
        _rebalanceLoss = loss;
    }

    /// @dev A real venue enforces the floor-value covenant here; the mock only models the cost.
    function rebalance(bytes calldata) external {
        rebalanceCalls += 1;
        if (_rebalanceLoss != 0) {
            quote.burn(address(this), _rebalanceLoss);
            _value -= _rebalanceLoss;
        }
    }

    function valueInQuote() external view returns (uint256) {
        return _value;
    }

    function unwind() external returns (uint256 quoteReturned) {
        quoteReturned = quote.balanceOf(address(this));
        quote.transfer(vault, quoteReturned);
        _value = 0;
    }
}

/// @dev Stands in for Aqua in unit tests. Deliberately moves NO tokens on `ship`, matching the
///      real registry's virtual-balance model: capital stays in the maker's wallet.
contract MockAqua is IAquaRegistry {
    mapping(bytes32 => bool) public active;
    mapping(bytes32 => mapping(address => uint256)) public balances;

    function ship(address, bytes calldata strategy, address[] calldata tokens, uint256[] calldata amounts)
        external
        returns (bytes32 strategyHash)
    {
        strategyHash = keccak256(strategy);
        require(!active[strategyHash], "StrategiesMustBeImmutable");
        active[strategyHash] = true;
        for (uint256 i; i < tokens.length; ++i) balances[strategyHash][tokens[i]] = amounts[i];
    }

    function dock(address, bytes32 strategyHash, address[] calldata tokens) external {
        require(active[strategyHash], "not active");
        active[strategyHash] = false;
        for (uint256 i; i < tokens.length; ++i) balances[strategyHash][tokens[i]] = 0;
    }

    function rawBalances(address, address, bytes32 strategyHash, address token)
        external
        view
        returns (uint248, uint8)
    {
        return (uint248(balances[strategyHash][token]), active[strategyHash] ? 2 : 0);
    }
}

/// @dev Returns a well-formed but inert strategy. The real one builds SwapVM bytecode and lives
///      under `src/aqua/` with the Degensoft licence.
contract MockBufferStrategy is IBufferStrategy {
    address public immutable app;
    address public immutable quote;
    address public immutable risky;
    uint256 public nonce;

    constructor(address app_, address quote_, address risky_) {
        app = app_;
        quote = quote_;
        risky = risky_;
    }

    function shipParams(uint256 quoteAmount)
        external
        view
        returns (address, bytes memory strategy, address[] memory tokens, uint256[] memory amounts)
    {
        tokens = new address[](2);
        tokens[0] = quote;
        tokens[1] = risky;
        amounts = new uint256[](2);
        amounts[0] = quoteAmount;
        strategy = abi.encode(app, quote, risky, quoteAmount);
        return (app, strategy, tokens, amounts);
    }
}

/// @dev Fills either direction at the oracle mark, scaled by `fillRateWad`. On a fork this stands
///      in for existing ETH/USDC liquidity; the fill rate is what lets tests push a settlement sale
///      below the vault's floor.
contract MockSpotSwapper is ISpotSwapper {
    MockOracle public immutable oracle;
    MockERC20 public immutable quote;
    MockERC20 public immutable risky;

    uint256 public fillRateWad = 1e18;

    constructor(MockOracle oracle_, MockERC20 quote_, MockERC20 risky_) {
        oracle = oracle_;
        quote = quote_;
        risky = risky_;
    }

    function setFillRate(uint256 fillRateWad_) external {
        fillRateWad = fillRateWad_;
    }

    function swapExactIn(address tokenIn, address, uint256 amountIn, uint256 minOut)
        external
        returns (uint256 amountOut)
    {
        if (tokenIn == address(quote)) {
            quote.transferFrom(msg.sender, address(this), amountIn);
            amountOut = ((amountIn * 1e18) / oracle.priceWad(address(risky)) * fillRateWad) / 1e18;
            risky.mint(msg.sender, amountOut);
        } else {
            risky.transferFrom(msg.sender, address(this), amountIn);
            amountOut = (oracle.valueInQuote(address(risky), amountIn) * fillRateWad) / 1e18;
            quote.mint(msg.sender, amountOut);
        }
        require(amountOut >= minOut, "MockSpotSwapper: minOut");
    }
}

/// @dev A v3 pool that reports whatever cumulative history the test sets. `setMeanTick` synthesises
///      a history whose average over `window` is exactly that tick; `setCumulatives` sets the raw
///      pair so rounding and uneven windows can be exercised directly.
contract MockV3Pool is IUniswapV3PoolObserver {
    address public token0;
    address public token1;

    int56 internal older;
    int56 internal newer;
    bool internal stale;

    constructor(address token0_, address token1_) {
        (token0, token1) = token0_ < token1_ ? (token0_, token1_) : (token1_, token0_);
    }

    function setMeanTick(int24 tick, uint32 window) external {
        older = 0;
        newer = int56(tick) * int56(uint56(window));
    }

    function setCumulatives(int56 older_, int56 newer_) external {
        older = older_;
        newer = newer_;
    }

    /// @dev Mimics the pool refusing a window it has no observations for.
    function setStale(bool stale_) external {
        stale = stale_;
    }

    function observe(uint32[] calldata)
        external
        view
        returns (int56[] memory tickCumulatives, uint160[] memory secondsPerLiquidityCumulativeX128s)
    {
        require(!stale, "OLD");
        tickCumulatives = new int56[](2);
        tickCumulatives[0] = older;
        tickCumulatives[1] = newer;
        secondsPerLiquidityCumulativeX128s = new uint160[](2);
    }
}
