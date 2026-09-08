// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {ERC20} from "solmate/tokens/ERC20.sol";

import {IBufferVenue} from "../../src/interfaces/IBufferVenue.sol";
import {IPositionVenue} from "../../src/interfaces/IPositionVenue.sol";
import {IQuoteOracle} from "../../src/interfaces/IQuoteOracle.sol";

contract MockERC20 is ERC20 {
    constructor(string memory n, string memory s, uint8 d) ERC20(n, s, d) {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external {
        _burn(from, amount);
    }
}

contract MockOracle is IQuoteOracle {
    /// @dev quote units per 1e18 of the risky token
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

/// @dev Stands in for the Aqua leg. Deliberately moves NO tokens on `ship`, matching Aqua's
///      virtual-balance model: the capital stays in the vault's own wallet.
contract MockBufferVenue is IBufferVenue {
    uint256 internal _shipped;
    bool internal _isShipped;

    function ship(uint256 quoteAmount) external {
        _shipped = quoteAmount;
        _isShipped = true;
    }

    function dock() external {
        _shipped = 0;
        _isShipped = false;
    }

    function shippedQuote() external view returns (uint256) {
        return _shipped;
    }

    function isShipped() external view returns (bool) {
        return _isShipped;
    }
}
