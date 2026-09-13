// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console2} from "forge-std/Script.sol";

import {TrancheVault} from "../src/TrancheVault.sol";
import {IAquaRegistry} from "../src/interfaces/IAquaRegistry.sol";
import {IBufferStrategy} from "../src/interfaces/IBufferStrategy.sol";
import {IPositionVenue} from "../src/interfaces/IPositionVenue.sol";
import {IQuoteOracle} from "../src/interfaces/IQuoteOracle.sol";
import {ISpotSwapper} from "../src/interfaces/ISpotSwapper.sol";
import {RiskPolicy} from "../src/libraries/RiskPolicy.sol";
import {
    MockAqua,
    MockBufferStrategy,
    MockERC20,
    MockOracle,
    MockPositionVenue,
    MockSpotSwapper
} from "../test/mocks/Mocks.sol";

contract DeployDevnet is Script {
    function run() external {
        uint256 key = vm.envUint("PRIVATE_KEY");
        address curator = vm.addr(key);

        vm.startBroadcast(key);
        MockERC20 quote = new MockERC20("USD Coin", "USDC", 6);
        MockERC20 risky = new MockERC20("Wrapped Ether", "WETH", 18);
        MockOracle oracle = new MockOracle();
        MockAqua aqua = new MockAqua();
        oracle.setPrice(address(risky), 2_000e6);

        TrancheVault.Config memory config = TrancheVault.Config({
            couponWad: 0.01e18,
            lambdaWad: 0.7e18,
            maxCouponWad: 0.015e18,
            minJuniorShareWad: 0.05e18,
            maxJuniorShareWad: 0.6e18,
            bufferShipShareWad: 0,
            bufferCallCoverageWad: 0.1e18,
            minRebalanceCoverageWad: 0.2e18,
            liquidationSlippageWad: 0.01e18,
            risk: RiskPolicy.Params({
                baseSpreadWad: 0.0005e18,
                alphaWad: 2e18,
                kappaWad: 0.5e18,
                targetCoverageWad: 0.4285e18,
                bidCutoffWad: 0.9e18,
                maxInventoryWad: 0.3e18
            }),
            subscriptionEnd: uint64(block.timestamp + 7 days),
            epochDuration: 30 days,
            activationGrace: 1 days,
            unwindWindow: 1 days,
            rebalanceCooldown: 6 hours
        });
        TrancheVault vault = new TrancheVault(
            quote,
            risky,
            IQuoteOracle(address(oracle)),
            IAquaRegistry(address(aqua)),
            curator,
            config
        );
        MockPositionVenue position = new MockPositionVenue(quote, address(vault));
        MockBufferStrategy strategy = new MockBufferStrategy(
            curator,
            address(quote),
            address(risky)
        );
        MockSpotSwapper swapper = new MockSpotSwapper(oracle, quote, risky);
        vault.setVenues(
            IPositionVenue(address(position)),
            IBufferStrategy(address(strategy)),
            ISpotSwapper(address(swapper))
        );

        quote.mint(curator, 2_000_000e6);
        quote.approve(address(vault), 1_000_000e6);
        vault.depositSenior(700_000e6);
        vault.depositJunior(300_000e6);
        vm.stopBroadcast();

        console2.log("TRELP_VAULT_ADDRESS", address(vault));
        console2.log("TRELP_QUOTE_ADDRESS", address(quote));
        console2.log("TRELP_RISKY_ADDRESS", address(risky));
        console2.log("TRELP_POSITION_VENUE", address(position));
        console2.log("TRELP_CURATOR", curator);
    }
}
