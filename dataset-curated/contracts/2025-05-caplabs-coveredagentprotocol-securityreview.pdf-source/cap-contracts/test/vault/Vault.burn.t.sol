// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { VaultLogic } from "../../contracts/vault/libraries/VaultLogic.sol";
import { TestDeployer } from "../deploy/TestDeployer.sol";
import { MockERC20 } from "../mocks/MockERC20.sol";
import { console } from "forge-std/console.sol";

contract VaultBurnTest is TestDeployer {
    address user;

    function setUp() public {
        _deployCapTestEnvironment();
        _initTestVaultLiquidity(usdVault);

        user = makeAddr("test_user");
        _initTestUserMintCapToken(usdVault, user, 4000e18);
    }

    function test_vault_burn() public {
        vm.startPrank(user);

        // burn the cUSD tokens we own
        uint256 burnAmount = 100e18;
        uint256 minOutputAmount = 95e6; // Expect at least 95% back accounting for potential fees
        uint256 deadline = block.timestamp + 1 hours;

        uint256 outputAmount = cUSD.burn(address(usdt), burnAmount, minOutputAmount, user, deadline);

        // Verify final balances
        assertEq(cUSD.balanceOf(user), 4000e18 - burnAmount, "Should have burned their cUSD tokens");
        assertEq(outputAmount, usdt.balanceOf(user), "Should have received minOutputAmount back");
        assertGt(outputAmount, 0, "Should have received more than 0 USDT back");
    }

    function test_burn_with_invalid_asset() public {
        vm.startPrank(user);

        MockERC20 invalidAsset = new MockERC20("Invalid", "INV", 18);

        // Burn cUSD with USDT
        uint256 amountIn = 100e18;
        uint256 minAmountOut = 95e6; // Accounting for potential fees
        uint256 deadline = block.timestamp + 1 hours;

        vm.expectRevert();
        cUSD.burn(address(invalidAsset), amountIn, minAmountOut, user, deadline);
    }

    function test_burn_with_invalid_min_amount() public {
        vm.startPrank(user);

        // Burn cUSD with USDT
        uint256 amountIn = 100e18;
        uint256 minAmountOut = 105e6; // Accounting for potential fees
        uint256 deadline = block.timestamp + 1 hours;

        vm.expectRevert();
        cUSD.burn(address(usdt), amountIn, minAmountOut, user, deadline);
    }

    function test_burn_with_invalid_deadline() public {
        vm.startPrank(user);

        // Burn cUSD with USDT
        uint256 amountIn = 100e18;
        uint256 minAmountOut = 95e6; // Accounting for potential fees
        uint256 deadline = block.timestamp - 1 hours;

        vm.expectRevert();
        cUSD.burn(address(usdt), amountIn, minAmountOut, user, deadline);
    }

    function test_burn_with_one_wei() public {
        vm.startPrank(user);

        // Burn cUSD with USDT
        uint256 amountIn = 1;
        uint256 minAmountOut = 1; // Accounting for potential fees
        uint256 deadline = block.timestamp + 1 hours;

        vm.expectRevert(); // Slippage
        cUSD.burn(address(usdt), amountIn, minAmountOut, user, deadline);

        minAmountOut = 0;

        vm.expectRevert(VaultLogic.InvalidAmount.selector);
        cUSD.burn(address(usdt), amountIn, minAmountOut, user, deadline);
    }
}
