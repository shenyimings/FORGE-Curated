// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { Base } from "../../Base.sol";

import { deployVault } from "src/utils/Deployers.sol";
import { AvKATVault as Vault } from "src/AvKATVault.sol";
import { IVaultNFT as IVault } from "src/interfaces/IVaultNFT.sol";
import { ProxyLib } from "@aragon/osx-commons-contracts/src/utils/deployment/ProxyLib.sol";

contract VaultInitializeTest is Base {
    function setUp() public override {
        super.setUp();
    }

    function test_Initialize() public view {
        assertEq(address(vault.strategy()), address(acStrategy));
        assertEq(vault.masterTokenId(), masterTokenId);
    }

    function testReverts_IfTokenNotApprovedOrOwned() public {
        (, address newVault) = deployVault(address(dao), address(escrow), address(defaultStrategy), "name", "symbol");

        // Create a token but don't transfer it to the vault
        escrowToken.approve(address(escrow), 1);
        uint256 wrongTokenId = escrow.createLock(1);

        vm.expectRevert();
        Vault(newVault).initializeMasterTokenAndStrategy(wrongTokenId, address(acStrategy));
    }

    function test_CanOnlyBeCalledOnce() public {
        vm.expectRevert(IVault.MasterTokenAlreadySet.selector);
        vault.initializeMasterTokenAndStrategy(masterTokenId, address(acStrategy));
    }

    function testReverts_IfTokenIdCannotBeZero() public {
        (, address newVault) = deployVault(address(dao), address(escrow), address(defaultStrategy), "name", "symbol");

        vm.startPrank(address(dao));
        dao.grant(newVault, address(this), vault.VAULT_ADMIN_ROLE());
        vm.stopPrank();

        vm.expectRevert(IVault.TokenIdCannotBeZero.selector);
        Vault(newVault).initializeMasterTokenAndStrategy(0, address(acStrategy));
    }

    function testReverts_IfDefaultStrategyIsZeroAddress() public {
        // Deploy base implementation
        address vaultBase = address(new Vault());

        // Try to deploy proxy with zero address default strategy
        vm.expectRevert(Vault.DefaultStrategyCannotBeZero.selector);
        ProxyLib.deployUUPSProxy(
            vaultBase, abi.encodeCall(Vault.initialize, (address(dao), address(escrow), address(0), "name", "symbol"))
        );
    }
}
