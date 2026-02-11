// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { Vault } from "../../contracts/vault/Vault.sol";

import { VaultLogic } from "../../contracts/vault/libraries/VaultLogic.sol";
import { TestDeployer } from "../deploy/TestDeployer.sol";
import { MockERC20 } from "../mocks/MockERC20.sol";

contract VaultRescueTest is TestDeployer {
    address admin;
    address user;
    MockERC20 token;
    uint256 rescueAmount;

    function setUp() public {
        _deployCapTestEnvironment();
        _initTestVaultLiquidity(usdVault);

        admin = makeAddr("admin");
        user = makeAddr("test_user");

        token = new MockERC20("Test Token", "TEST", 18);

        // Grant admin role for rescue functionality
        _grantAccess(Vault.rescueERC20.selector, address(cUSD), admin);

        rescueAmount = 1000e6;
        token.mint(address(cUSD), rescueAmount);

        // Initial balance check
        assertEq(token.balanceOf(address(cUSD)), rescueAmount, "Vault should have rescue tokens");
        assertEq(token.balanceOf(user), 0, "User should start with 0 balance");

        assertGt(usdt.balanceOf(address(cUSD)), 0, "Vault should have some usdt");
    }

    function test_vault_rescue() public {
        // Rescue tokens
        {
            vm.prank(admin);
            cUSD.rescueERC20(address(token), user);
            vm.stopPrank();
        }

        // Verify final balances
        assertEq(token.balanceOf(address(cUSD)), 0, "Vault should have 0 tokens after rescue");
        assertEq(token.balanceOf(user), rescueAmount, "User should have received rescued tokens");
    }

    function test_vault_rescue_revert_unauthorized() public {
        // Try to rescue tokens without improper role
        {
            vm.prank(user);
            vm.expectRevert(); // Should revert due to missing role
            cUSD.rescueERC20(address(token), user);
            vm.stopPrank();
        }

        // balance are unchanged
        assertEq(token.balanceOf(address(cUSD)), rescueAmount, "Vault should have rescue tokens");
        assertEq(token.balanceOf(user), 0, "User should have 0 balance");
    }

    function test_cannot_rescue_vault_token() public {
        // try to rescue the vault token
        {
            vm.prank(admin);
            vm.expectRevert(abi.encodeWithSelector(VaultLogic.AssetNotRescuable.selector, address(usdt)));
            cUSD.rescueERC20(address(usdt), user);
            vm.stopPrank();
        }
        assertEq(usdt.balanceOf(user), 0, "User should have 0 usdt");
    }

    function test_can_rescue_vault_token_itself() public {
        // mint some cUSD to the vault itself
        {
            _initTestUserMintCapToken(usdVault, user, 1000e18);
            vm.prank(user);
            cUSD.transfer(address(cUSD), 1000e18);
            vm.stopPrank();
        }

        assertEq(cUSD.balanceOf(address(cUSD)), 1000e18, "Vault should have some cUSD");
        assertEq(cUSD.balanceOf(user), 0, "User should have 0 cUSD");
        assertEq(cUSD.balanceOf(admin), 0, "Admin should have 0 cUSD");

        // try to rescue the vault token
        {
            vm.prank(admin);
            cUSD.rescueERC20(address(cUSD), user);
            vm.stopPrank();
        }

        assertEq(cUSD.balanceOf(address(cUSD)), 0, "Vault should have 0 cUSD");
        assertEq(cUSD.balanceOf(user), 1000e18, "User should have received rescued cUSD");
        assertEq(cUSD.balanceOf(admin), 0, "Admin should have received rescued cUSD");
    }
}
