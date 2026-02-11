// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.23;

import {Test} from "forge-std/Test.sol";
import {InstanceManager} from "../../instance/InstanceManager.sol";
import {IAddressProvider} from "../../interfaces/IAddressProvider.sol";
import {BytecodeRepository} from "../../global/BytecodeRepository.sol";
import {ProxyCall} from "../../helpers/ProxyCall.sol";
import {
    AP_INSTANCE_MANAGER,
    AP_CROSS_CHAIN_GOVERNANCE,
    AP_TREASURY,
    AP_BYTECODE_REPOSITORY,
    AP_ADDRESS_PROVIDER,
    AP_INSTANCE_MANAGER_PROXY,
    AP_CROSS_CHAIN_GOVERNANCE_PROXY,
    AP_TREASURY_PROXY,
    AP_GEAR_TOKEN,
    AP_WETH_TOKEN,
    NO_VERSION_CONTROL
} from "../../libraries/ContractLiterals.sol";

contract InstanceManagerTest is Test {
    InstanceManager public manager;
    address public owner;
    address public treasury;
    address public crossChainGovernance;
    address public weth;
    address public gear;
    IAddressProvider public addressProvider;

    function setUp() public {
        owner = makeAddr("owner");
        treasury = makeAddr("treasury");
        weth = makeAddr("weth");
        gear = makeAddr("gear");

        manager = new InstanceManager(owner);
        addressProvider = IAddressProvider(manager.addressProvider());
    }

    /// @notice Test constructor sets up initial state correctly
    function test_IM_01_constructor_sets_initial_state() public view {
        // Verify proxies were created
        assertTrue(manager.instanceManagerProxy() != address(0));
        assertTrue(manager.treasuryProxy() != address(0));
        assertTrue(manager.crossChainGovernanceProxy() != address(0));

        // Verify initial addresses were set
        assertEq(
            addressProvider.getAddressOrRevert(AP_BYTECODE_REPOSITORY, NO_VERSION_CONTROL), manager.bytecodeRepository()
        );
        assertEq(addressProvider.getAddressOrRevert(AP_CROSS_CHAIN_GOVERNANCE, NO_VERSION_CONTROL), owner);
        assertEq(
            addressProvider.getAddressOrRevert(AP_INSTANCE_MANAGER_PROXY, NO_VERSION_CONTROL),
            manager.instanceManagerProxy()
        );
        assertEq(addressProvider.getAddressOrRevert(AP_TREASURY_PROXY, NO_VERSION_CONTROL), manager.treasuryProxy());
        assertEq(
            addressProvider.getAddressOrRevert(AP_CROSS_CHAIN_GOVERNANCE_PROXY, NO_VERSION_CONTROL),
            manager.crossChainGovernanceProxy()
        );

        // Verify ownership
        assertEq(manager.owner(), owner);
    }

    /// @notice Test activation sets up remaining addresses
    function test_IM_02_activate_sets_remaining_addresses() public {
        vm.prank(owner);
        manager.activate(owner, treasury, weth, gear);

        assertTrue(manager.isActivated());
        assertEq(addressProvider.getAddressOrRevert(AP_INSTANCE_MANAGER, NO_VERSION_CONTROL), address(manager));
        assertEq(addressProvider.getAddressOrRevert(AP_TREASURY, NO_VERSION_CONTROL), treasury);
        assertEq(addressProvider.getAddressOrRevert(AP_WETH_TOKEN, NO_VERSION_CONTROL), weth);
        assertEq(addressProvider.getAddressOrRevert(AP_GEAR_TOKEN, NO_VERSION_CONTROL), gear);
    }

    /// @notice Test only owner can activate
    function test_IM_03_activate_only_owner() public {
        vm.prank(makeAddr("notOwner"));
        vm.expectRevert("Ownable: caller is not the owner");
        manager.activate(owner, treasury, weth, gear);
    }

    /// @notice Test can't activate twice
    function test_IM_04_cant_activate_twice() public {
        vm.startPrank(owner);

        manager.activate(owner, treasury, weth, gear);

        // Second activation should not change state
        address newTreasury = makeAddr("newTreasury");
        manager.activate(owner, newTreasury, weth, gear);

        assertEq(addressProvider.getAddressOrRevert(AP_TREASURY, NO_VERSION_CONTROL), treasury);
        vm.stopPrank();
    }

    /// @notice Test setting global address requires correct prefix
    function test_IM_05_setGlobalAddress_requires_prefix() public {
        vm.mockCall(
            addressProvider.getAddressOrRevert(AP_CROSS_CHAIN_GOVERNANCE, NO_VERSION_CONTROL),
            abi.encodeWithSignature("getAddress(bytes32)"),
            abi.encode(msg.sender)
        );

        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(InstanceManager.InvalidKeyException.selector, "INVALID"));
        manager.setGlobalAddress("INVALID", address(0), false);
    }

    /// @notice Test setting local address requires correct prefix
    function test_IM_06_setLocalAddress_requires_prefix() public {
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(InstanceManager.InvalidKeyException.selector, "INVALID"));
        manager.setLocalAddress("INVALID", address(0), false);
    }

    /// @notice Test only cross chain governance can configure global
    function test_IM_07_configureGlobal_access_control() public {
        vm.prank(makeAddr("notGovernance"));
        vm.expectRevert("Only cross chain governance can call this function");
        manager.configureGlobal(address(0), "");
    }

    /// @notice Test only owner can configure local
    function test_IM_08_configureLocal_access_control() public {
        vm.prank(makeAddr("notOwner"));
        vm.expectRevert("Ownable: caller is not the owner");
        manager.configureLocal(address(0), "");
    }

    /// @notice Test only treasury can configure treasury
    function test_IM_09_configureTreasury_access_control() public {
        vm.prank(owner);
        manager.activate(owner, treasury, weth, gear);

        vm.prank(makeAddr("notTreasury"));
        vm.expectRevert("Only financial multisig can call this function");
        manager.configureTreasury(address(0), "");
    }
}
