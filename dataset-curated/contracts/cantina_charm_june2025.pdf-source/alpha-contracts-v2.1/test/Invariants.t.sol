// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";

import {VaultTestUtils} from "./VaultTestUtils.sol";

contract InvariantsTest is Test, VaultTestUtils {
    function setUp() public {
        vm.createSelectFork(vm.envString("ALCHEMY_RPC"), 17073835);
        prepareTokens();
        deployFactory();
    }

    function test_totalAmountsIncludesFees() public {
        depositInFactory();

        (uint256 total0, uint256 total1) = vault.getTotalAmounts();

        swapForwardAndBack(false);
        swapForwardAndBack(true);

        (uint256 total0After, uint256 total1After) = vault.getTotalAmounts();

        // Using stricter tolerances to match TypeScript test
        vm.assertApproxEqAbs(total0, total0After, 10000, "total0 != total0After");
        vm.assertApproxEqAbs(total1, total1After, 1000000000000, "total1 != total1After");

        vm.assertNotEq(total0, total0After);
        vm.assertNotEq(total1, total1After);

        // simulate poke
        vm.startPrank(other);
        vault.deposit(100, 10, 0, 0, other);

        (total0After, total1After) = vault.getTotalAmounts();

        // Using stricter tolerances to match TypeScript test
        vm.assertApproxEqAbs(total0, total0After, 1000000, "(after deposit) total0 != total0After");
        vm.assertApproxEqAbs(total1, total1After, 1000000000000000, "(after deposit) total1 != total1After");
        vm.assertGt(total0After, total0);
        vm.assertGt(total1After, total1);
    }
}
