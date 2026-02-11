// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "./AutomatorIntegrationTestBase.sol";

import "../../../src/transformers/AutoCompound.sol";
import "../../../src/utils/Constants.sol";

contract AutoCompoundTest is AutomatorIntegrationTestBase {
    AutoCompound autoCompound;
    
    // Mock AERO token address (using a random address for testing)
    address constant AERO_TOKEN = address(0x940181a94A35A4569E4529A3CDfB74e38FD98631);

    function setUp() external {
        _setupBase();
        autoCompound = new AutoCompound(NPM, OPERATOR_ACCOUNT, WITHDRAWER_ACCOUNT, 60, 100, AERO_TOKEN);
    }

    function testNoAccess() external {
        vm.expectRevert(Constants.Unauthorized.selector);
        autoCompound.execute(AutoCompound.ExecuteParams(TEST_NFT_2, false, 0, block.timestamp));
    }

    function testNoApprove() external {
        vm.prank(OPERATOR_ACCOUNT);
        vm.expectRevert("Not approved");
        autoCompound.execute(AutoCompound.ExecuteParams(TEST_NFT_2, false, 0, block.timestamp));
    }

    function _testWithdrawLeftover() internal {
        uint256 baiBalance = DAI.balanceOf(TEST_NFT_2_ACCOUNT);
        uint256 wethBalance = WETH_ERC20.balanceOf(TEST_NFT_2_ACCOUNT);

        uint256 daiLeftover = autoCompound.positionBalances(TEST_NFT_2, address(DAI));
        uint256 wethLeftover = autoCompound.positionBalances(TEST_NFT_2, address(WETH_ERC20));

        vm.expectRevert(Constants.Unauthorized.selector);
        autoCompound.withdrawLeftoverBalances(TEST_NFT_2, TEST_NFT_2_ACCOUNT);

        vm.prank(TEST_NFT_2_ACCOUNT);
        autoCompound.withdrawLeftoverBalances(TEST_NFT_2, TEST_NFT_2_ACCOUNT);

        uint256 baiBalanceAfter = DAI.balanceOf(TEST_NFT_2_ACCOUNT);
        uint256 wethBalanceAfter = WETH_ERC20.balanceOf(TEST_NFT_2_ACCOUNT);

        assertEq(baiBalanceAfter - baiBalance, daiLeftover);
        assertEq(wethBalanceAfter - wethBalance, wethLeftover);

        daiLeftover = autoCompound.positionBalances(TEST_NFT_2, address(DAI));
        wethLeftover = autoCompound.positionBalances(TEST_NFT_2, address(WETH_ERC20));
        assertEq(daiLeftover, 0);
        assertEq(wethLeftover, 0);
    }

    function _testWithdrawProtocolFee(uint256 expectedDaiFee, uint256 expectedWethFee) internal {
        uint256 daiFee = autoCompound.positionBalances(0, address(DAI));
        uint256 wethFee = autoCompound.positionBalances(0, address(WETH_ERC20));
        assertEq(daiFee, expectedDaiFee);
        assertEq(wethFee, expectedWethFee);

        address[] memory tokens = new address[](2);
        tokens[0] = address(DAI);
        tokens[1] = address(address(WETH_ERC20));

        vm.expectRevert(Constants.Unauthorized.selector);
        autoCompound.withdrawBalances(tokens, WITHDRAWER_ACCOUNT);

        vm.prank(WITHDRAWER_ACCOUNT);
        autoCompound.withdrawBalances(tokens, WITHDRAWER_ACCOUNT);

        daiFee = autoCompound.positionBalances(0, address(DAI));
        wethFee = autoCompound.positionBalances(0, address(WETH_ERC20));
        assertEq(daiFee, 0);
        assertEq(wethFee, 0);
    }

    function testCompoundNoSwapAndLeftover() external {
        vm.prank(TEST_NFT_2_ACCOUNT);
        NPM.approve(address(autoCompound), TEST_NFT_2);

        (,,,,,,, uint128 liquidity,,,,) = NPM.positions(TEST_NFT_2);
        assertEq(liquidity, 80059851033970806503);

        vm.prank(OPERATOR_ACCOUNT);
        autoCompound.execute(AutoCompound.ExecuteParams(TEST_NFT_2, false, 0, block.timestamp));

        (,,,,,,, liquidity,,,,) = NPM.positions(TEST_NFT_2);
        assertEq(liquidity, 99102324844935209920);

        _testWithdrawLeftover();
        _testWithdrawProtocolFee(0, 1940566999638732);
    }

    function testCompoundSwap0To1() external {
        vm.prank(TEST_NFT_2_ACCOUNT);
        NPM.approve(address(autoCompound), TEST_NFT_2);

        (,,,,,,, uint128 liquidity,,,,) = NPM.positions(TEST_NFT_2);
        assertEq(liquidity, 80059851033970806503);

        vm.prank(OPERATOR_ACCOUNT);
        autoCompound.execute(AutoCompound.ExecuteParams(TEST_NFT_2, true, 123456789012345678, block.timestamp));

        // more liquidity than without swap
        (,,,,,,, liquidity,,,,) = NPM.positions(TEST_NFT_2);
        assertEq(liquidity, 99117944276318382811);

        _testWithdrawLeftover();
        _testWithdrawProtocolFee(0, 1942158733643263);
    }

    function testCompoundSwap1To0() external {
        vm.prank(TEST_NFT_2_ACCOUNT);
        NPM.approve(address(autoCompound), TEST_NFT_2);

        (,,,,,,, uint128 liquidity,,,,) = NPM.positions(TEST_NFT_2);
        assertEq(liquidity, 80059851033970806503);

        vm.prank(OPERATOR_ACCOUNT);
        autoCompound.execute(AutoCompound.ExecuteParams(TEST_NFT_2, false, 1234567890123456, block.timestamp));

        // less liquidity than without swap
        (,,,,,,, liquidity,,,,) = NPM.positions(TEST_NFT_2);
        assertEq(liquidity, 98864783327532224693);

        _testWithdrawLeftover();
        _testWithdrawProtocolFee(0, 1916359786106899);
    }
}
