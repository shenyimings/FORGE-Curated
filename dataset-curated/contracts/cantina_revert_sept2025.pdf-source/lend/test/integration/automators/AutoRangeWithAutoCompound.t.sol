// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "./AutomatorIntegrationTestBase.sol";

import "../../../src/transformers/AutoRange.sol";
import "../../../src/utils/Constants.sol";

contract AutoRangeWithAutoCompoundTest is AutomatorIntegrationTestBase {
    AutoRange autoRange;

    function setUp() external {
        _setupBase();
        autoRange = new AutoRange(NPM, OPERATOR_ACCOUNT, WITHDRAWER_ACCOUNT, 60, 100, EX0x, UNIVERSAL_ROUTER);
    }

    function testNoAccess() external {
        vm.expectRevert(Constants.Unauthorized.selector);
        autoRange.autoCompound(AutoRange.AutoCompoundParams(TEST_NFT_2, false, 0, block.timestamp));
    }

    function testNotConfigured() external {
        vm.prank(OPERATOR_ACCOUNT);
        vm.expectRevert(Constants.NotConfigured.selector);
        autoRange.autoCompound(AutoRange.AutoCompoundParams(TEST_NFT_2, false, 0, block.timestamp));
    }


    function testNoApprove() external {

        vm.prank(TEST_NFT_2_ACCOUNT);
        autoRange.configToken(TEST_NFT_2, address(0), AutoRange.PositionConfig(0, 0, 0, 1, 0, 0, false, true, 0));

        vm.prank(OPERATOR_ACCOUNT);
        vm.expectRevert("Not approved");
        autoRange.autoCompound(AutoRange.AutoCompoundParams(TEST_NFT_2, false, 0, block.timestamp));
    }

    function testCompoundNoSwapAndLeftover() external {
        vm.prank(TEST_NFT_2_ACCOUNT);
        NPM.approve(address(autoRange), TEST_NFT_2);

        vm.prank(TEST_NFT_2_ACCOUNT);
        autoRange.configToken(TEST_NFT_2, address(0), AutoRange.PositionConfig(0, 0, 0, 1, 0, 0, false, true, 0));

        (,,,,,,, uint128 liquidity,,,,) = NPM.positions(TEST_NFT_2);
        assertEq(liquidity, 80059851033970806503);

        vm.prank(OPERATOR_ACCOUNT);
        autoRange.autoCompound(AutoRange.AutoCompoundParams(TEST_NFT_2, false, 0, block.timestamp));

        (,,,,,,, liquidity,,,,) = NPM.positions(TEST_NFT_2);
        assertEq(liquidity, 99102324844935209920);

        //_testWithdrawLeftover();
        //_testWithdrawProtocolFee(0, 1940566999638732);
    }

    function testCompoundSwap0To1() external {
        vm.prank(TEST_NFT_2_ACCOUNT);
        NPM.approve(address(autoRange), TEST_NFT_2);

        vm.prank(TEST_NFT_2_ACCOUNT);
        autoRange.configToken(TEST_NFT_2, address(0), AutoRange.PositionConfig(0, 0, 0, 1, 0, 0, false, true, 0));

        (,,,,,,, uint128 liquidity,,,,) = NPM.positions(TEST_NFT_2);
        assertEq(liquidity, 80059851033970806503);

        vm.prank(OPERATOR_ACCOUNT);
        autoRange.autoCompound(AutoRange.AutoCompoundParams(TEST_NFT_2, true, 123456789012345678, block.timestamp));

        // more liquidity than without swap
        (,,,,,,, liquidity,,,,) = NPM.positions(TEST_NFT_2);
        assertEq(liquidity, 99117944276318382811);

        //_testWithdrawLeftover();
        //_testWithdrawProtocolFee(0, 1942158733643263);
    }

    function testCompoundSwap1To0() external {
        vm.prank(TEST_NFT_2_ACCOUNT);
        NPM.approve(address(autoRange), TEST_NFT_2);

        vm.prank(TEST_NFT_2_ACCOUNT);
        autoRange.configToken(TEST_NFT_2, address(0), AutoRange.PositionConfig(0, 0, 0, 1, 0, 0, false, true, 0));

        (,,,,,,, uint128 liquidity,,,,) = NPM.positions(TEST_NFT_2);
        assertEq(liquidity, 80059851033970806503);

        vm.prank(OPERATOR_ACCOUNT);
        autoRange.autoCompound(AutoRange.AutoCompoundParams(TEST_NFT_2, false, 1234567890123456, block.timestamp));

        // less liquidity than without swap
        (,,,,,,, liquidity,,,,) = NPM.positions(TEST_NFT_2);
        assertEq(liquidity, 98864783327532224693);

        //_testWithdrawLeftover();
        //_testWithdrawProtocolFee(0, 1916359786106899);
    }
}
