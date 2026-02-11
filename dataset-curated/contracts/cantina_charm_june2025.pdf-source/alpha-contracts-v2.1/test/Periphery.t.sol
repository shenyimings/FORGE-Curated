// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {AlphaProPeriphery, PositionAmounts} from "../contracts/AlphaProPeriphery.sol";

import {VaultTestUtils} from "./VaultTestUtils.sol";

contract PeripheryTest is Test, VaultTestUtils {
    function setUp() public {
        vm.createSelectFork(vm.envString("ALCHEMY_RPC"), 17073835);
        prepareTokens();
        deployPeriphery();
        deployFactory();
    }

    function test_checkAccruedFeesAreGood() public {
        depositInFactory();

        (PositionAmounts[3] memory results, uint256 balance0, uint256 balance1) =
            alphaProPeriphery.getVaultPositions(address(vault));

        (uint256 total0, uint256 total1) = vault.getTotalAmounts();

        // NOTE: [FAIL: test_checkAccruedFeesAreGood_1: 20999999999 != 20369999999]
        vm.assertEq(
            balance0 + results[0].amount0 + results[1].amount0 + results[2].amount0,
            total0,
            "test_checkAccruedFeesAreGood_1"
        );
        // NOTE: [FAIL: test_checkAccruedFeesAreGood_2: 9999999999999999998 != 9700000000000000013]
        vm.assertEq(
            balance1 + results[0].amount1 + results[1].amount1 + results[2].amount1,
            total1,
            "test_checkAccruedFeesAreGood_2"
        );
        vm.assertEq(results[1].fees0, 0, "base.fees0 != 0");
        vm.assertEq(results[1].fees1, 0, "base.fees1 != 0");

        swapForwardAndBack(false);
        swapForwardAndBack(true);

        (results, balance0, balance1) = alphaProPeriphery.getVaultPositions(address(vault));

        uint256 calculatedTotal0 = 0;
        uint256 calculatedTotal1 = 0;

        for (uint256 i = 0; i < results.length; i++) {
            calculatedTotal0 += results[i].amount0 + results[i].fees0;
            calculatedTotal1 += results[i].amount1 + results[i].fees1;
        }

        vault.rebalance();

        (total0, total1) = vault.getTotalAmounts();

        vm.assertApproxEqAbs(calculatedTotal0 + balance0, total0, 2, "test_checkAccruedFeesAreGood_3");
        vm.assertApproxEqAbs(calculatedTotal1 + balance1, total1, 2, "test_checkAccruedFeesAreGood_4");
    }
}
