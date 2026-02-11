// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {StageMath} from "../../src/libraries/StageMath.sol";

contract StageMathTest is Test {
    using StageMath for uint256;

    function testAdd() public pure {
        uint256 stage = 0;
        uint128 amount = 100;
        uint256 newStage = stage.add(amount);
        (uint128 total, uint128 liquidity) = StageMath.decode(newStage);
        assertEq(total, amount);
        assertEq(liquidity, amount);
    }

    function testSub() public pure {
        uint256 stage = 0;
        uint128 amount = 100;
        uint256 newStage = stage.add(amount).sub(amount);
        (uint128 total, uint128 liquidity) = StageMath.decode(newStage);
        assertEq(total, amount, "Total should be equal to amount");
        assertEq(liquidity, 0, "Liquidity should be zero after subtraction");
    }

    function testIsFree() public pure {
        uint256 stage = 0;
        uint32 leavePart = 5; // Default level part
        assertTrue(StageMath.isFree(stage, leavePart));
        stage = stage.add(100);
        assertFalse(StageMath.isFree(stage, leavePart));
        stage = stage.sub(50);
        assertFalse(StageMath.isFree(stage, leavePart), "Stage should not be free after reducing liquidity");
        stage = stage.sub(30);
        assertTrue(StageMath.isFree(stage, leavePart), "Stage should be free after reducing liquidity");
    }
}
