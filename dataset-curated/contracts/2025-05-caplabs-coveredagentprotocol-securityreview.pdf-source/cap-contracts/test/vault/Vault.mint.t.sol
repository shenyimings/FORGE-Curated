// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { TestDeployer } from "../deploy/TestDeployer.sol";
import { MockChainlinkPriceFeed } from "../mocks/MockChainlinkPriceFeed.sol";

contract VaultMintTest is TestDeployer {
    address user;

    function setUp() public {
        _deployCapTestEnvironment();

        user = makeAddr("test_user");
    }

    function test_vault_mint_on_empty_vault() public {
        vm.startPrank(user);

        // Approve USDT spending
        usdt.mint(user, 100e6);
        usdt.approve(address(cUSD), 100e6);

        // Mint cUSD with USDT
        uint256 amountIn = 100e6;
        uint256 minAmountOut = 95e6; // Accounting for potential fees
        uint256 deadline = block.timestamp + 1 hours;

        cUSD.mint(address(usdt), amountIn, minAmountOut, user, deadline);

        // Assert the minting was successful
        assertGt(cUSD.balanceOf(user), 0, "Should have received cUSD tokens");
        assertEq(usdt.balanceOf(address(cUSD)), amountIn, "Vault should have received USDT");
        assertEq(usdt.balanceOf(user), 0, "User should have spent USDT");
    }

    function test_vault_mint_with_different_prices() public {
        // Set USDT price to 1.02 USD
        _setAssetOraclePrice(address(usdt), 102e8);

        vm.startPrank(user);

        // Approve USDT spending
        usdt.mint(user, 100e6);
        usdt.approve(address(cUSD), 100e6);

        // Mint cUSD with USDT
        uint256 amountIn = 100e6;
        uint256 minAmountOut = 90e6;
        uint256 deadline = block.timestamp + 1 hours;

        cUSD.mint(address(usdt), amountIn, minAmountOut, user, deadline);

        // We should receive less cUSD since USDT is worth more
        assertGe(cUSD.balanceOf(user), amountIn * 98 / 100, "Should have received less cUSD due to higher USDT price");
        assertEq(usdt.balanceOf(address(cUSD)), amountIn, "Vault should have received USDT");
    }

    function test_mint_on_non_empty_vault() public {
        _initTestVaultLiquidity(usdVault);

        vm.startPrank(user);

        // Approve USDT spending
        usdt.mint(user, 100e6);
        usdt.approve(address(cUSD), 100e6);

        // Mint cUSD with USDT
        uint256 amountIn = 100e6;
        uint256 minAmountOut = 95e6; // Accounting for potential fees
        uint256 deadline = block.timestamp + 1 hours;

        cUSD.mint(address(usdt), amountIn, minAmountOut, user, deadline);
    }
}
