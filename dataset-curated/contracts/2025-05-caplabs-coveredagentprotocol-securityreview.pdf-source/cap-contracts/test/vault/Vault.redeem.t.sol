// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { TestDeployer } from "../deploy/TestDeployer.sol";
import { MockERC20 } from "../mocks/MockERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract VaultRedeemTest is TestDeployer {
    address user;

    function setUp() public {
        _deployCapTestEnvironment();
        _initTestVaultLiquidity(usdVault);

        user = makeAddr("test_user");
        _initTestUserMintCapToken(usdVault, user, 4000e18);
    }

    function test_vault_redeem() public {
        vm.startPrank(user);

        // redeem the cUSD tokens we own
        uint256 redeemAmount = 100e18;
        uint256 minOutputAmount = uint256(95e6) / uint256(3); // Expect at least 95% back accounting for potential fees
        uint256 deadline = block.timestamp + 1 hours;

        address[] memory assets = cUSD.assets();
        uint256 assetLength = assets.length;

        uint256[] memory minOutputAmounts = new uint256[](assetLength);
        for (uint256 i = 0; i < assetLength; i++) {
            minOutputAmounts[i] = minOutputAmount;
        }

        uint256[] memory outputAmount = cUSD.redeem(redeemAmount, minOutputAmounts, user, deadline);

        // Verify final balances
        assertEq(cUSD.balanceOf(user), 4000e18 - redeemAmount, "Should have burned their cUSD tokens");
        for (uint256 i = 0; i < assetLength; i++) {
            assertGe(outputAmount[i], minOutputAmounts[i], "Should have received at least minOutputAmount back");
            assertEq(
                IERC20(assets[i]).balanceOf(user), outputAmount[i], "Should have received the correct amount of assets"
            );
        }

        address recipient = makeAddr("test_recipient");
        outputAmount = cUSD.redeem(redeemAmount, minOutputAmounts, recipient, deadline);

        // Verify final balances
        assertEq(cUSD.balanceOf(user), 4000e18 - (redeemAmount * 2), "Should have burned their cUSD tokens");
        for (uint256 i = 0; i < assetLength; i++) {
            assertGe(outputAmount[i], minOutputAmounts[i], "Should have received at least minOutputAmount back");
            assertEq(
                IERC20(assets[i]).balanceOf(recipient),
                outputAmount[i],
                "Should have received the correct amount of assets"
            );
        }
    }

    function test_redeem_with_invalid_minAmounts() public {
        vm.startPrank(user);

        // redeem the cUSD tokens we own
        uint256 redeemAmount = 100e18;
        uint256 minOutputAmount = 95e6; // Expect too much back
        uint256 deadline = block.timestamp + 1 hours;

        address[] memory assets = cUSD.assets();
        uint256 assetLength = assets.length;

        uint256[] memory minOutputAmounts = new uint256[](assetLength);
        for (uint256 i = 0; i < assetLength; i++) {
            minOutputAmounts[i] = minOutputAmount;
        }

        vm.expectRevert();
        cUSD.redeem(redeemAmount, minOutputAmounts, user, deadline);
    }

    function test_redeem_with_invalid_minAmounts_length() public {
        vm.startPrank(user);

        // redeem the cUSD tokens we own
        uint256 redeemAmount = 100e18;
        uint256 minOutputAmount = 32e6; // Expect too much back
        uint256 deadline = block.timestamp + 1 hours;

        address[] memory assets = cUSD.assets();
        uint256 assetLength = assets.length;

        uint256[] memory minOutputAmounts = new uint256[](assetLength - 1);
        for (uint256 i = 0; i < assetLength - 1; i++) {
            minOutputAmounts[i] = minOutputAmount;
        }

        vm.expectRevert();
        cUSD.redeem(redeemAmount, minOutputAmounts, user, deadline);

        minOutputAmounts = new uint256[](assetLength + 1);
        for (uint256 i = 0; i < assetLength + 1; i++) {
            minOutputAmounts[i] = minOutputAmount;
        }

        vm.expectRevert();
        cUSD.redeem(redeemAmount, minOutputAmounts, user, deadline);
    }

    function test_redeem_with_invalid_deadline() public {
        vm.startPrank(user);

        // redeem the cUSD tokens we own
        uint256 redeemAmount = 100e18;
        uint256 minOutputAmount = 32e6;
        uint256 deadline = block.timestamp - 1 hours;

        address[] memory assets = cUSD.assets();
        uint256 assetLength = assets.length;

        uint256[] memory minOutputAmounts = new uint256[](assetLength);
        for (uint256 i = 0; i < assetLength; i++) {
            minOutputAmounts[i] = minOutputAmount;
        }

        vm.expectRevert();
        cUSD.redeem(redeemAmount, minOutputAmounts, user, deadline);
    }

    function test_redeem_with_one_wei() public {
        vm.startPrank(user);

        // redeem the cUSD tokens we own
        uint256 redeemAmount = 1;
        uint256 minOutputAmount = 1; // Accounting for potential fees
        uint256 deadline = block.timestamp + 1 hours;

        address[] memory assets = cUSD.assets();
        uint256 assetLength = assets.length;

        uint256[] memory minOutputAmounts = new uint256[](assetLength);
        for (uint256 i = 0; i < assetLength; i++) {
            minOutputAmounts[i] = minOutputAmount;
        }

        vm.expectRevert();
        cUSD.redeem(redeemAmount, minOutputAmounts, user, deadline);
    }
}
