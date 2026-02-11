// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

// Forge imports
import {Test} from "forge-std/Test.sol";

// Dependency imports
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UnsafeUpgrades} from "@foundry-upgrades/Upgrades.sol";

// Internal imports
import {LeverageToken} from "src/LeverageToken.sol";
import {ILeverageToken} from "src/interfaces/ILeverageToken.sol";

contract LeverageTokenTest is Test {
    LeverageToken public leverageToken;

    function setUp() public virtual {
        address leverageTokenImplementation = address(new LeverageToken());

        vm.expectEmit(true, true, true, true);
        emit ILeverageToken.LeverageTokenInitialized("Test name", "Test symbol");

        address leverageTokenProxy = UnsafeUpgrades.deployUUPSProxy(
            leverageTokenImplementation,
            abi.encodeWithSelector(LeverageToken.initialize.selector, address(this), "Test name", "Test symbol")
        );

        leverageToken = LeverageToken(leverageTokenProxy);
    }

    function test_setUp() public view {
        assertEq(leverageToken.name(), "Test name");
        assertEq(leverageToken.symbol(), "Test symbol");
        assertEq(leverageToken.owner(), address(this));
    }

    function test_initialize_RevertIf_AlreadyInitialized() public {
        vm.expectRevert(abi.encodeWithSelector(Initializable.InvalidInitialization.selector));
        leverageToken.initialize(address(this), "Test name", "Test symbol");
    }
}
