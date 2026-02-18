// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.29;

import "forge-std/src/Test.sol";
import "../src/proxy/TimelockUpgradeableProxy.sol";
import "../src/proxy/Initializable.sol";
import "../src/proxy/AddressRegistry.sol";

contract MockInitializable is Initializable {
    bool public didInitialize;

    function doSomething() external pure returns (bool) {
        return true;
    }

    function _initialize(bytes calldata /* data */) internal override {
        didInitialize = true;
    }
}

contract TestTimelockProxy is Test {
    Initializable public impl;
    TimelockUpgradeableProxy public proxy;
    address public upgradeOwner;
    address public pauseOwner;
    address public feeReceiver;
    AddressRegistry public registry = ADDRESS_REGISTRY;

    function deployAddressRegistry() public {
        address deployer = makeAddr("deployer");
        vm.prank(deployer);
        address addressRegistry = address(new AddressRegistry());
        TimelockUpgradeableProxy p = new TimelockUpgradeableProxy(
            address(addressRegistry),
            abi.encodeWithSelector(Initializable.initialize.selector, abi.encode(upgradeOwner, pauseOwner, feeReceiver))
        );
        registry = AddressRegistry(address(p));

        assertEq(address(registry), address(ADDRESS_REGISTRY), "AddressRegistry is incorrect");
    }

    function setUp() public {
        upgradeOwner = makeAddr("upgradeOwner");
        pauseOwner = makeAddr("pauseOwner");
        feeReceiver = makeAddr("feeReceiver");

        deployAddressRegistry();

        impl = new MockInitializable();
        proxy = new TimelockUpgradeableProxy(
            address(impl),
            abi.encodeWithSelector(Initializable.initialize.selector, abi.encode("name", "symbol"))
        );
    }

    function test_cannotReinitializeImplementation() public {
        // Cannot re-initialize the implementation
        vm.expectRevert(abi.encodeWithSelector(InvalidInitialization.selector));
        impl.initialize(bytes(""));
    }

    function test_initializeProxy() public {
        // Cannot re-initialize the proxy
        vm.expectRevert(abi.encodeWithSelector(InvalidInitialization.selector));
        Initializable(address(proxy)).initialize(bytes(""));

        // Check that the proxy is initialized
        assertEq(MockInitializable(address(proxy)).didInitialize(), true);
    }

    function test_initiateUpgrade() public {
        Initializable timelock2 = new Initializable();
        vm.expectRevert(abi.encodeWithSelector(Unauthorized.selector, address(this)));
        proxy.initiateUpgrade(address(timelock2));

        vm.expectEmit(true, true, true, true);
        emit TimelockUpgradeableProxy.UpgradeInitiated(address(timelock2), uint32(block.timestamp + proxy.UPGRADE_DELAY()));
        vm.prank(upgradeOwner);
        proxy.initiateUpgrade(address(timelock2));

        assertEq(proxy.newImplementation(), address(timelock2));
        assertEq(proxy.upgradeValidAt(), uint32(block.timestamp + proxy.UPGRADE_DELAY()));

        vm.startPrank(upgradeOwner);
        // Cannot upgrade before the delay
        vm.expectRevert(abi.encodeWithSelector(InvalidUpgrade.selector));
        proxy.executeUpgrade(bytes(""));

        vm.warp(block.timestamp + proxy.UPGRADE_DELAY() + 1);
        proxy.executeUpgrade(bytes(""));

        assertEq(proxy.newImplementation(), address(timelock2));
        vm.stopPrank();
    }

    function test_cancelUpgrade() public {
        Initializable timelock2 = new Initializable();

        vm.prank(upgradeOwner);
        proxy.initiateUpgrade(address(timelock2));
        assertEq(proxy.newImplementation(), address(timelock2));
        assertEq(proxy.upgradeValidAt(), uint32(block.timestamp + proxy.UPGRADE_DELAY()));

        vm.prank(upgradeOwner);
        proxy.initiateUpgrade(address(0));

        assertEq(proxy.newImplementation(), address(0));
        assertEq(proxy.upgradeValidAt(), uint32(0));

        vm.expectRevert(abi.encodeWithSelector(Unauthorized.selector, address(this)));
        proxy.executeUpgrade(bytes(""));

        vm.startPrank(upgradeOwner);
        vm.expectRevert(abi.encodeWithSelector(InvalidUpgrade.selector));
        proxy.executeUpgrade(bytes(""));
        vm.stopPrank();
    }

    function test_pause() public {
        vm.expectRevert(abi.encodeWithSelector(Unauthorized.selector, address(this)));
        proxy.pause();

        vm.prank(pauseOwner);
        proxy.pause();

        vm.expectRevert(abi.encodeWithSelector(Paused.selector));
        MockInitializable(address(proxy)).doSomething();

        vm.expectRevert(abi.encodeWithSelector(Unauthorized.selector, address(this)));
        proxy.unpause();

        // Whitelist the doSomething function
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = MockInitializable.doSomething.selector;
        vm.expectRevert(abi.encodeWithSelector(Unauthorized.selector, address(this)));
        proxy.whitelistSelectors(selectors, true);

        vm.prank(pauseOwner);
        proxy.whitelistSelectors(selectors, true);

        assertEq(MockInitializable(address(proxy)).doSomething(), true);

        vm.prank(pauseOwner);
        proxy.unpause();

        assertEq(MockInitializable(address(proxy)).doSomething(), true);
    }

    function test_transferUpgradeOwnership() public {
        address newUpgradeOwner = makeAddr("newUpgradeOwner");
        vm.expectRevert(abi.encodeWithSelector(Unauthorized.selector, address(this)));
        registry.transferUpgradeAdmin(newUpgradeOwner);

        vm.expectEmit(true, true, true, true);
        emit AddressRegistry.PendingUpgradeAdminSet(newUpgradeOwner);
        vm.prank(upgradeOwner);
        registry.transferUpgradeAdmin(newUpgradeOwner);

        vm.expectRevert(abi.encodeWithSelector(Unauthorized.selector, address(this)));
        registry.acceptUpgradeOwnership();

        vm.expectEmit(true, true, true, true);
        emit AddressRegistry.UpgradeAdminTransferred(newUpgradeOwner);
        vm.prank(newUpgradeOwner);
        registry.acceptUpgradeOwnership();

        assertEq(registry.upgradeAdmin(), newUpgradeOwner);
    }

    function test_transferPauseAdmin() public {
        address newPauseAdmin = makeAddr("newPauseAdmin");
        vm.expectRevert(abi.encodeWithSelector(Unauthorized.selector, address(this)));
        registry.transferPauseAdmin(newPauseAdmin);

        vm.expectEmit(true, true, true, true);
        emit AddressRegistry.PendingPauseAdminSet(newPauseAdmin);
        vm.prank(upgradeOwner);
        registry.transferPauseAdmin(newPauseAdmin);

        vm.expectRevert(abi.encodeWithSelector(Unauthorized.selector, address(this)));
        registry.acceptPauseAdmin();

        vm.expectEmit(true, true, true, true);
        emit AddressRegistry.PauseAdminTransferred(newPauseAdmin);
        vm.prank(newPauseAdmin);
        registry.acceptPauseAdmin();

        assertEq(registry.pauseAdmin(), newPauseAdmin);
    }

    function test_transferFeeReceiver() public {
        address newFeeReceiver = makeAddr("newFeeReceiver");
        vm.expectRevert(abi.encodeWithSelector(Unauthorized.selector, address(this)));
        registry.transferFeeReceiver(newFeeReceiver);

        vm.expectEmit(true, true, true, true);
        emit AddressRegistry.FeeReceiverTransferred(newFeeReceiver);
        vm.prank(upgradeOwner);
        registry.transferFeeReceiver(newFeeReceiver);

        assertEq(registry.feeReceiver(), newFeeReceiver);
    }
    
}
