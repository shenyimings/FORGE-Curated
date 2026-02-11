/// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {ALTBCPool, IERC20} from "src/amm/ALTBCPool.sol";
import "src/common/IALTBCEvents.sol";
import {ALTBCPoolCommonImpl} from "test/amm/common/ALTBCPoolCommonImpl.sol";
import {PoolCommonTest} from "liquidity-base/test/amm/common/PoolCommon.t.u.sol";
import {MathLibs, packedFloat} from "lib/liquidity-base/src/amm/mathLibs/MathLibs.sol";
import "forge-std/console2.sol";

/**
 * @title Test Pool functionality
 * @dev unit test
 * @author @oscarsernarosero @mpetersoCode55 @cirsteve
 */
abstract contract ALTBCPoolCommonTest is ALTBCPoolCommonImpl, PoolCommonTest {
    using MathLibs for packedFloat;

    function testLiquidity_Pool_XSquareNeverOverflows() public view {
        // Verifying this doesn't revert due to an overflow
        ALTBCPool(address(pool)).TOTAL_SUPPLY_LIMIT() * ALTBCPool(address(pool)).TOTAL_SUPPLY_LIMIT();
    }

    function testestLiquidity_Pool_deployment_NoInitialLiquidity() public startAsAdmin {
        vm.expectRevert(abi.encodeWithSignature("NoInitialLiquidity()"));
        altbcFactory.createPool(address(xToken), address(yToken), 0, altbcInput, 0, "Name", "SYMBOL");
    }

    function testestLiquidity_Pool_deployment_CZero() public startAsAdmin {
        altbcInput._C = 0;
        vm.expectRevert(abi.encodeWithSignature("CCannotBeZero()"));
        altbcFactory.createPool(address(xToken), address(yToken), 0, altbcInput, X_TOKEN_MAX_SUPPLY, "Name", "SYMBOL");
    }

    function testestLiquidity_Pool_deployment_VZero() public startAsAdmin {
        altbcInput._V = 0;
        vm.expectRevert(abi.encodeWithSignature("VCannotBeZero()"));
        altbcFactory.createPool(address(xToken), address(yToken), 0, altbcInput, X_TOKEN_MAX_SUPPLY, "Name", "SYMBOL");
    }

    function testestLiquidity_Pool_deployment_xMinZero() public startAsAdmin {
        altbcInput._xMin = 0;
        vm.expectRevert(abi.encodeWithSignature("xMinCannotBeZero()"));
        altbcFactory.createPool(address(xToken), address(yToken), 0, altbcInput, X_TOKEN_MAX_SUPPLY, "Name", "SYMBOL");
    }

    function testLiquidity_Pool_deploymentEvent() public startAsAdmin {
        IERC20(address(xToken)).approve(address(altbcFactory), X_TOKEN_MAX_SUPPLY);
        vm.expectEmit(true, true, true, true);
        emit ALTBCPoolDeployed(address(xToken), address(yToken), "v0.2.0", 0, 0, address(0xB0b), altbcInput);
        altbcFactory.createPool(address(xToken), address(yToken), 0, altbcInput, X_TOKEN_MAX_SUPPLY, "Name", "SYMBOL");
    }

    function testLiquidity_Pool_HighDecimalYToken() public {
        _setUpTokensAndFactories(X_TOKEN_MAX_SUPPLY);
        vm.startPrank(admin);
        IERC20(address(xToken)).approve(address(altbcFactory), X_TOKEN_MAX_SUPPLY);
        vm.expectRevert(abi.encodeWithSignature("YTokenDecimalsGT18()"));
        altbcFactory.createPool(address(xToken), address(highDecimalCoin), 30, altbcInput, X_TOKEN_MAX_SUPPLY, "Name", "SYMBOL");
    }

    function testLiquidity_Pool_HighDecimalXToken() public {
        _setUpTokensAndFactories(X_TOKEN_MAX_SUPPLY);
        vm.startPrank(admin);
        IERC20(address(xToken)).approve(address(altbcFactory), X_TOKEN_MAX_SUPPLY);
        vm.expectRevert(abi.encodeWithSignature("XTokenDecimalsIsNot18()"));
        altbcFactory.createPool(address(highDecimalCoin), address(stableCoin), 30, altbcInput, X_TOKEN_MAX_SUPPLY, "Name", "SYMBOL");
    }

    function testLiquidity_Pool_DepositInactiveLiquidity() public {
        vm.startPrank(admin);
        altbcInput._wInactive = fullToken;
        address poolAddr = altbcFactory.createPool(address(xToken), address(yToken), 0, altbcInput, X_TOKEN_MAX_SUPPLY, "Name", "SYMBOL");
        uint inactiveId = ALTBCPool(poolAddr).INACTIVE_ID();
        vm.expectRevert(abi.encodeWithSignature("CannotDepositInactiveLiquidity()"));
        ALTBCPool(poolAddr).depositLiquidity(inactiveId, 1e18, 1e18);
    }

    function testLiquidity_Pool_WithdrawRevenueInactiveLiquidity() public {
        vm.startPrank(admin);
        altbcInput._wInactive = fullToken;
        address poolAddr = altbcFactory.createPool(address(xToken), address(yToken), 0, altbcInput, X_TOKEN_MAX_SUPPLY, "Name", "SYMBOL");
        uint inactiveId = ALTBCPool(poolAddr).INACTIVE_ID();
        vm.expectRevert("ALTBCPool: Q too high");
        ALTBCPool(poolAddr).withdrawRevenue(inactiveId, 1);
    }
}

/**
 * @title Test Pool Stable Coin functionality
 * @dev unit test
 * @author @oscarsernarosero @mpetersoCode55
 */
contract PoolStableCoinTest is ALTBCPoolCommonTest {
    function setUp() public endWithStopPrank {
        _setupPool(true);
    }
}

/**
 * @title Test Pool WETH functionality
 * @dev unit test
 * @author @oscarsernarosero @mpetersoCode55
 */
contract PoolWETHTest is ALTBCPoolCommonTest {
    function setUp() public endWithStopPrank {
        _setupPool(false);
    }
}
