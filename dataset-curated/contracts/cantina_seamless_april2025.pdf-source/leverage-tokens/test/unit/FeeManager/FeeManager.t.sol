// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

// Forge imports
import {Test} from "forge-std/Test.sol";

// Dependency imports
import {UnsafeUpgrades} from "@foundry-upgrades/Upgrades.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

// Local imports
import {FeeManager} from "src/FeeManager.sol";
import {FeeManagerHarness} from "test/unit/harness/FeeManagerHarness.sol";
import {ExternalAction} from "src/types/DataTypes.sol";

contract FeeManagerTest is Test {
    address public feeManagerRole = makeAddr("feeManagerRole");
    FeeManagerHarness public feeManager;

    function setUp() public virtual {
        address feeManagerImplementation = address(new FeeManagerHarness());
        address feeManagerProxy = UnsafeUpgrades.deployUUPSProxy(
            feeManagerImplementation, abi.encodeWithSelector(FeeManagerHarness.initialize.selector, address(this))
        );

        feeManager = FeeManagerHarness(feeManagerProxy);
        feeManager.grantRole(feeManager.FEE_MANAGER_ROLE(), feeManagerRole);
    }

    function test_setUp() public view virtual {
        bytes32 expectedSlot = keccak256(abi.encode(uint256(keccak256("seamless.contracts.storage.FeeManager")) - 1))
            & ~bytes32(uint256(0xff));

        assertTrue(feeManager.hasRole(feeManager.FEE_MANAGER_ROLE(), feeManagerRole));
        assertEq(feeManager.exposed_getFeeManagerStorageSlot(), expectedSlot);
    }

    function test_feeManagerInit_RevertsIfNotInitializer() public {
        vm.expectRevert(Initializable.NotInitializing.selector);
        feeManager.__FeeManager_init(address(this));
    }

    function _setTreasuryActionFee(address caller, ExternalAction action, uint256 fee) internal {
        vm.prank(caller);
        feeManager.setTreasuryActionFee(action, fee);
    }

    function _setTreasury(address caller, address treasury) internal {
        vm.prank(caller);
        feeManager.setTreasury(treasury);
    }
}
