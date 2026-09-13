// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ERC20} from "solmate/src/tokens/ERC20.sol";

import {IQuoteOracle} from "../../src/interfaces/IQuoteOracle.sol";
import {ISpotSwapper} from "../../src/interfaces/ISpotSwapper.sol";

/// @notice Fills at the oracle mark, so seeding and liquidation follow the demo's market.
/// @dev Demo infrastructure. A real deployment routes through `V3SpotSwapper`.
contract OracleSwapper is ISpotSwapper {
    IQuoteOracle public immutable oracle;
    address public immutable quote;
    address public immutable risky;

    constructor(IQuoteOracle oracle_, address quote_, address risky_) {
        oracle = oracle_;
        quote = quote_;
        risky = risky_;
    }

    function swapExactIn(address tokenIn, address tokenOut, uint256 amountIn, uint256 minOut)
        external
        returns (uint256 amountOut)
    {
        ERC20(tokenIn).transferFrom(msg.sender, address(this), amountIn);
        amountOut = tokenIn == risky
            ? oracle.valueInQuote(risky, amountIn)
            : (amountIn * 1e18) / oracle.valueInQuote(risky, 1e18);
        require(amountOut >= minOut, "minOut");
        ERC20(tokenOut).transfer(msg.sender, amountOut);
    }
}
