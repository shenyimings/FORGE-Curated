// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.26;

import "./helpers/IntegrationTest.sol";
import {EVCUtil} from "../lib/ethereum-vault-connector/src/utils/EVCUtil.sol";

contract DeploymentTest is IntegrationTest {
    function testSetName(string memory name) public {
        vm.prank(OWNER);
        vault.setName(name);

        assertEq(vault.name(), name);
    }

    function testSetNameEvent(string memory name) public {
        vm.expectEmit();
        emit EventsLib.SetName(name);
        vm.prank(OWNER);
        vault.setName(name);
    }

    function testSetNameNotOwner(string memory name) public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this)));
        vault.setName(name);
    }

    function testSetSymbol(string memory symbol) public {
        vm.prank(OWNER);
        vault.setSymbol(symbol);

        assertEq(vault.symbol(), symbol);
    }

    function testSetSymbolEvent(string memory symbol) public {
        vm.expectEmit();
        emit EventsLib.SetSymbol(symbol);
        vm.prank(OWNER);
        vault.setSymbol(symbol);
    }

    function testSetSymbolNotOwner(string memory name) public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this)));
        vault.setSymbol(name);
    }

    function testDeployEulerEarnAddresssZero() public {
        vm.expectRevert(EVCUtil.EVC_InvalidAddress.selector);
        createEulerEarn(OWNER, address(0), permit2, 1 days, address(loanToken), "EulerEarn Vault", "EEV");
    }

    function testDeployEulerEarn(
        address owner,
        address evc,
        address permit2,
        uint256 initialTimelock,
        string memory name,
        string memory symbol
    ) public {
        assumeNotZeroAddress(owner);
        assumeNotZeroAddress(evc);
        initialTimelock = _boundInitialTimelock(initialTimelock);

        IEulerEarn newVault = createEulerEarn(owner, evc, permit2, initialTimelock, address(loanToken), name, symbol);

        assertEq(newVault.owner(), owner, "owner");
        assertEq(address(newVault.EVC()), evc, "evc");
        assertEq(newVault.timelock(), initialTimelock, "timelock");
        assertEq(newVault.asset(), address(loanToken), "asset");
        assertEq(newVault.name(), name, "name");
        assertEq(newVault.symbol(), symbol, "symbol");
    }
}
