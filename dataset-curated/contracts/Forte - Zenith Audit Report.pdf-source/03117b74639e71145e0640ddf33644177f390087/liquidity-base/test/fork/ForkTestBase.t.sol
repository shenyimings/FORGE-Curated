/// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {GenericERC20FixedSupply, GenericERC20} from "test/util/TestCommon.sol";

import {TestCommonSetup} from "test/util/TestCommonSetup.sol";

/**
 * @title Base for Fork Testing
 * @dev unit test
 * @author @oscarsernarosero @mpetersoCode55 @cirsteve @palmerg4
 */
abstract contract ForkTestBase is TestCommonSetup {
    bool withStableCoin;
    bool wEth;
    bool wMatic;

    function testTransferZeroCollateralA() public startAsAdmin {
        vm.expectRevert(abi.encodeWithSignature("ZeroValueNotAllowed()"));
        pool.swap(address(_yToken), 0, 1000);
    }

    function testTransferZeroCollateralB() public startAsAdmin {
        uint expected = ERC20_DECIMALS;
        vm.expectRevert("max slippage reached");
        pool.swap(address(_yToken), 1, expected);
    }

    function testNotEnoughXToken() public startAsAdmin {
        (uint expected, , ) = pool.simSwap(address(_yToken), 1 * STABLECOIN_DEC);
        (uint actual, , ) = pool.swap(address(_yToken), 1 * STABLECOIN_DEC, expected);

        xToken.transfer(address(0x1), 1000);

        (uint expectedY, , ) = pool.simSwap(address(xToken), actual - 1);
        vm.expectRevert(
            abi.encodeWithSignature(
                "ERC20InsufficientBalance(address,uint256,uint256)",
                address(admin),
                xToken.balanceOf(address(admin)),
                actual - 1
            )
        );

        pool.swap(address(xToken), (actual - 1), expectedY);
    }

    function testTransferZeroXToken() public startAsAdmin {
        vm.expectRevert(abi.encodeWithSignature("ZeroValueNotAllowed()"));
        pool.swap(address(xToken), 0, 1000);
    }
}
