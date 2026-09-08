// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {Aqua} from "@1inch/aqua/src/Aqua.sol";
import {AquaSwapVMRouter} from "@1inch/swap-vm/src/routers/AquaSwapVMRouter.sol";
import {XYCSwap} from "@1inch/swap-vm/src/instructions/XYCSwap.sol";
import {Extruction} from "@1inch/swap-vm/src/instructions/Extruction.sol";
import {OraclePriceAdjuster} from "@1inch/swap-vm/src/instructions/OraclePriceAdjuster.sol";

contract DepsSmokeTest is Test {
    function test_official1inchContractsDeploy() public {
        Aqua aqua = new Aqua();
        AquaSwapVMRouter router = new AquaSwapVMRouter(address(aqua), address(0), address(this), "SwapVM", "1.0.0");
        assertTrue(address(router) != address(0));
        assertGt(XYCSwap.build().length, 0, "instruction builders link");
    }
}
