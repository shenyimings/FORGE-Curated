// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {Factory} from "src/Factory.sol";
import {FactoryHelper} from "test/utils/FactoryHelper.sol";

contract TimelockUpgradeIntegrationTest is Test {
    Factory factory;

    function setUp() public {
        // Deploy a fresh Factory using core addresses discovered from the locator
        string memory locatorAddressStr = vm.envString("CORE_LOCATOR_ADDRESS");
        address locatorAddress = vm.parseAddress(locatorAddressStr);

        FactoryHelper helper = new FactoryHelper();
        factory = helper.deployMainFactory(locatorAddress);
    }

    // function test_timelockControlsProxyAdmins() public {
    //     vm.deal(address(this), 100 ether);

    //     (address ignoredVault, address dashboard, address payable poolProxy, address wqProxy, /** distributor */) =
    //         factory.createVaultWithNoMintingNoStrategy{value: 1 ether}(
    //             address(this), address(this), 0, 1 hours, 30 days, 1 days, false
    //         );
    //     // suppress unused variable
    //     ignoredVault;

    //     // Timelock should be the admin of both proxies
    //     address adminWrapper = _getAdmin(poolProxy);
    //     address adminWq = _getAdmin(wqProxy);
    //     assertEq(adminWrapper, adminWq, "Both proxies should share the same admin (timelock)");

    //     // Non-admin cannot upgrade directly
    //     vm.expectRevert();
    //     OssifiableProxy(poolProxy).proxy__upgradeToAndCall(address(0x1), "");

    //     // Schedule an upgrade via timelock and execute after delay
    //     TimelockController tl = TimelockController(payable(adminWrapper));
    //     address newImpl = address(new StvPool(dashboard, false, wqProxy, address(0)));
    //     bytes memory payload = abi.encodeWithSignature(
    //         "proxy__upgradeToAndCall(address,bytes)", newImpl, bytes("")
    //     );
    //     bytes32 predecessor = bytes32(0);
    //     bytes32 salt = keccak256("upgrade-pool");

    //     uint256 minDelay = tl.getMinDelay();
    //     vm.prank(address(this));
    //     tl.schedule(poolProxy, 0, payload, predecessor, salt, minDelay);

    //     vm.expectRevert();
    //     tl.execute(poolProxy, 0, payload, predecessor, salt);

    //     vm.warp(block.timestamp + minDelay + 1);
    //     tl.execute(poolProxy, 0, payload, predecessor, salt);

    //     // Verify implementation changed
    //     address implAfter = _getImplementation(poolProxy);
    //     assertEq(implAfter, newImpl, "Wrapper implementation should be updated by timelock");
    // }

    // function test_onlyProposerCanSchedule() public {
    //     vm.deal(address(this), 100 ether);
    //     (, , address payable poolProxy, address wqProxy, /** distributor */) = factory.createVaultWithNoMintingNoStrategy{value: 1 ether}(
    //         address(this), address(this), 0, 1 hours, 30 days, 1 days, false
    //     );
    //     TimelockController tl = TimelockController(payable(_getAdmin(poolProxy)));
    //     bytes memory payload = abi.encodeWithSignature("proxy__changeAdmin(address)", address(0xdead));
    //     uint256 minDelay = tl.getMinDelay();
    //     bytes32 predecessor = bytes32(0);
    //     bytes32 salt = keccak256("only-proposer");
    //     // non-proposer attempt
    //     address attacker = address(0xBEEF);
    //     vm.prank(attacker);
    //     vm.expectRevert();
    //     tl.schedule(poolProxy, 0, payload, predecessor, salt, minDelay);
    //     // proposer (pool admin) can schedule
    //     tl.schedule(poolProxy, 0, payload, predecessor, salt, minDelay);
    //     // clean up by cancelling to avoid affecting later tests
    //     bytes32 id = tl.hashOperation(poolProxy, 0, payload, predecessor, salt);
    //     tl.cancel(id);
    //     // silence unused var
    //     wqProxy;
    // }

    // function test_onlyCustomExecutorCanExecute() public {
    //     vm.deal(address(this), 100 ether);
    //     address customExec = address(0xE0EC);
    //     (, address dashboard, address payable poolProxy, /** withdrawalQueueProxy */ , /** distributor */) = factory.createVaultWithNoMintingNoStrategy{value: 1 ether}(
    //         address(this), address(this), 0, 1 hours, 30 days, 1 days, false, customExec
    //     );
    //     TimelockController tl = TimelockController(payable(_getAdmin(poolProxy)));
    //     address newImpl = address(new StvPool(dashboard, false, poolProxy, address(0)));
    //     bytes memory payload = abi.encodeWithSignature("proxy__upgradeToAndCall(address,bytes)", newImpl, bytes(""));
    //     uint256 minDelay = tl.getMinDelay();
    //     bytes32 predecessor = bytes32(0);
    //     bytes32 salt = keccak256("only-executor-custom");
    //     tl.schedule(poolProxy, 0, payload, predecessor, salt, minDelay);
    //     vm.warp(block.timestamp + minDelay + 1);
    //     // wrong executor
    //     vm.expectRevert();
    //     tl.execute(poolProxy, 0, payload, predecessor, salt);
    //     // correct custom executor
    //     vm.prank(customExec);
    //     tl.execute(poolProxy, 0, payload, predecessor, salt);
    // }

    // function test_upgradeWithdrawalQueueViaTimelock() public {
    //     vm.deal(address(this), 100 ether);
    //     (address vault, address dashboard, address payable poolProxy, address wqProxy, /** distributor */) =
    //         factory.createVaultWithNoMintingNoStrategy{value: 1 ether}(
    //             address(this), address(this), 0, 1 hours, 30 days, 1 days, false
    //         );
    //     TimelockController tl = TimelockController(payable(_getAdmin(poolProxy)));
    //     // deploy new WQ implementation with same constructor args
    //     IDashboard dash = IDashboard(payable(dashboard));
    //     address newWqImpl = address(new WithdrawalQueue(
    //         poolProxy,
    //         dashboard,
    //         dash.VAULT_HUB(),
    //         dash.STETH(),
    //         vault,
    //         factory.LAZY_ORACLE(),
    //         30 days,
    //         1 days
    //     ));
    //     bytes memory payload = abi.encodeWithSignature("proxy__upgradeToAndCall(address,bytes)", newWqImpl, bytes(""));
    //     uint256 minDelay = tl.getMinDelay();
    //     bytes32 predecessor = bytes32(0);
    //     bytes32 salt = keccak256("upgrade-wq");
    //     tl.schedule(wqProxy, 0, payload, predecessor, salt, minDelay);
    //     vm.warp(block.timestamp + minDelay + 1);
    //     tl.execute(wqProxy, 0, payload, predecessor, salt);
    //     address implAfter = _getImplementation(wqProxy);
    //     assertEq(implAfter, newWqImpl, "WithdrawalQueue implementation should be updated by timelock");
    // }

    // function test_batchChangeAdminBothProxies() public {
    //     vm.deal(address(this), 100 ether);
    //     (, , address payable poolProxy, address wqProxy, /** distributor */) = factory.createVaultWithNoMintingNoStrategy{value: 1 ether}(
    //         address(this), address(this), 0, 1 hours, 30 days, 1 days, false
    //     );
    //     TimelockController tl = TimelockController(payable(_getAdmin(poolProxy)));
    //     // new timelock
    //     address[] memory proposers = new address[](1);
    //     proposers[0] = address(this);
    //     address[] memory executors = new address[](1);
    //     executors[0] = address(this);
    //     TimelockController newTl = new TimelockController(tl.getMinDelay(), proposers, executors, address(0));

    //     address[] memory targets = new address[](2);
    //     targets[0] = poolProxy;
    //     targets[1] = wqProxy;
    //     uint256[] memory values = new uint256[](2);
    //     bytes[] memory payloads = new bytes[](2);
    //     payloads[0] = abi.encodeWithSignature("proxy__changeAdmin(address)", address(newTl));
    //     payloads[1] = abi.encodeWithSignature("proxy__changeAdmin(address)", address(newTl));
    //     bytes32 predecessor = bytes32(0);
    //     bytes32 salt = keccak256("batch-admin-change");
    //     uint256 minDelay = tl.getMinDelay();

    //     tl.scheduleBatch(targets, values, payloads, predecessor, salt, minDelay);
    //     vm.warp(block.timestamp + minDelay + 1);
    //     tl.executeBatch(targets, values, payloads, predecessor, salt);

    //     assertEq(_getAdmin(poolProxy), address(newTl), "Wrapper admin should be new timelock");
    //     assertEq(_getAdmin(wqProxy), address(newTl), "WQ admin should be new timelock");
    // }

    // function test_updateDelayViaTimelock() public {
    //     vm.deal(address(this), 100 ether);
    //     (, , address payable poolProxy, /** withdrawalQueueProxy */ , /** distributor */) = factory.createVaultWithNoMintingNoStrategy{value: 1 ether}(
    //         address(this), address(this), 0, 1 hours, 30 days, 1 days, false
    //     );
    //     TimelockController tl = TimelockController(payable(_getAdmin(poolProxy)));
    //     uint256 current = tl.getMinDelay();
    //     uint256 newDelay = current + 1 days;
    //     bytes memory payload = abi.encodeWithSignature("updateDelay(uint256)", newDelay);
    //     bytes32 predecessor = bytes32(0);
    //     bytes32 salt = keccak256("update-delay");
    //     tl.schedule(address(tl), 0, payload, predecessor, salt, current);
    //     vm.warp(block.timestamp + current + 1);
    //     tl.execute(address(tl), 0, payload, predecessor, salt);
    //     assertEq(tl.getMinDelay(), newDelay, "min delay should update");
    //     // verify schedule must meet new delay
    //     vm.expectRevert();
    //     tl.schedule(address(tl), 0, payload, predecessor, keccak256("too-short"), newDelay - 1);
    // }

    // function test_cancelPreventsExecute() public {
    //     vm.deal(address(this), 100 ether);
    //     (, , address payable poolProxy, /** withdrawalQueueProxy */ , /** distributor */) = factory.createVaultWithNoMintingNoStrategy{value: 1 ether}(
    //         address(this), address(this), 0, 1 hours, 30 days, 1 days, false
    //     );
    //     TimelockController tl = TimelockController(payable(_getAdmin(poolProxy)));
    //     bytes memory payload = abi.encodeWithSignature("proxy__upgradeToAndCall(address,bytes)", address(0x1), bytes(""));
    //     uint256 minDelay = tl.getMinDelay();
    //     bytes32 predecessor = bytes32(0);
    //     bytes32 salt = keccak256("cancel-test");
    //     tl.schedule(poolProxy, 0, payload, predecessor, salt, minDelay);
    //     bytes32 id = tl.hashOperation(poolProxy, 0, payload, predecessor, salt);
    //     tl.cancel(id);
    //     vm.warp(block.timestamp + minDelay + 1);
    //     vm.expectRevert();
    //     tl.execute(poolProxy, 0, payload, predecessor, salt);
    // }

    // function test_revertExecuteBeforeDelay() public {
    //     vm.deal(address(this), 100 ether);
    //     (, address dashboard, address payable poolProxy, /** withdrawalQueueProxy */ , /** distributor */) = factory.createVaultWithNoMintingNoStrategy{value: 1 ether}(
    //         address(this), address(this), 0, 1 hours, 30 days, 1 days, false
    //     );
    //     TimelockController tl = TimelockController(payable(_getAdmin(poolProxy)));
    //     address newImpl = address(new StvPool(dashboard, false, poolProxy, address(0)));
    //     bytes memory payload = abi.encodeWithSignature("proxy__upgradeToAndCall(address,bytes)", newImpl, bytes(""));
    //     uint256 minDelay = tl.getMinDelay();
    //     bytes32 predecessor = bytes32(0);
    //     bytes32 salt = keccak256("pre-delay-revert");
    //     tl.schedule(poolProxy, 0, payload, predecessor, salt, minDelay);
    //     // immediately try to execute
    //     vm.expectRevert();
    //     tl.execute(poolProxy, 0, payload, predecessor, salt);
    // }

    // function test_proxiesShareSameTimelockAfterOperations() public {
    //     vm.deal(address(this), 100 ether);
    //     (address ignoredVault, address dashboard, address payable poolProxy, address wqProxy, /** distributor */) =
    //         factory.createVaultWithNoMintingNoStrategy{value: 1 ether}(
    //             address(this), address(this), 0, 1 hours, 30 days, 1 days, false
    //         );
    //     ignoredVault;
    //     TimelockController tl = TimelockController(payable(_getAdmin(poolProxy)));
    //     // perform an upgrade on pool
    //     address newImpl = address(new StvPool(dashboard, false, wqProxy, address(0)));
    //     bytes memory payload = abi.encodeWithSignature("proxy__upgradeToAndCall(address,bytes)", newImpl, bytes(""));
    //     uint256 minDelay = tl.getMinDelay();
    //     bytes32 predecessor = bytes32(0);
    //     bytes32 salt = keccak256("shared-tl-invariant");
    //     tl.schedule(poolProxy, 0, payload, predecessor, salt, minDelay);
    //     vm.warp(block.timestamp + minDelay + 1);
    //     tl.execute(poolProxy, 0, payload, predecessor, salt);
    //     // admins should still be same
    //     assertEq(_getAdmin(poolProxy), _getAdmin(wqProxy), "admins diverged");
    // }

    // function _getAdmin(address proxy) internal view returns (address admin) {
    //     (bool ok, bytes memory ret) = proxy.staticcall(abi.encodeWithSignature("proxy__getAdmin()"));
    //     require(ok && ret.length >= 32, "proxy__getAdmin failed");
    //     admin = abi.decode(ret, (address));
    // }

    // function _getImplementation(address proxy) internal view returns (address impl) {
    //     (bool ok, bytes memory ret) = proxy.staticcall(abi.encodeWithSignature("proxy__getImplementation()"));
    //     require(ok && ret.length >= 32, "proxy__getImplementation failed");
    //     impl = abi.decode(ret, (address));
    // }
}
