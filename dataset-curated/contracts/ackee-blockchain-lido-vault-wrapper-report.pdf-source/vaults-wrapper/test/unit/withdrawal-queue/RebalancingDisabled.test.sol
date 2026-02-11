// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {WithdrawalQueue} from "src/WithdrawalQueue.sol";
import {OssifiableProxy} from "src/proxy/OssifiableProxy.sol";
import {StvStETHPool} from "src/StvStETHPool.sol";
import {MockLazyOracle} from "test/mocks/MockLazyOracle.sol";
import {MockDashboard, MockDashboardFactory} from "test/mocks/MockDashboard.sol";
import {MockVaultHub} from "test/mocks/MockVaultHub.sol";
import {MockStETH} from "test/mocks/MockStETH.sol";

contract RebalancingDisabledTest is Test {
    WithdrawalQueue public withdrawalQueue;
    StvStETHPool public pool;
    MockLazyOracle public lazyOracle;
    MockDashboard public dashboard;
    MockVaultHub public vaultHub;
    MockStETH public steth;

    address internal owner;
    address internal finalizeRoleHolder;

    function setUp() public {
        owner = makeAddr("owner");
        finalizeRoleHolder = makeAddr("finalizeRoleHolder");

        // Deploy mocks
        dashboard = new MockDashboardFactory().createMockDashboard(owner);
        lazyOracle = new MockLazyOracle();
        steth = dashboard.STETH();
        vaultHub = dashboard.VAULT_HUB();

        WithdrawalQueue impl = new WithdrawalQueue(
            address(pool),
            address(dashboard),
            address(vaultHub),
            address(steth),
            address(dashboard.VAULT()),
            address(lazyOracle),
            1 days,
            false
        );
        OssifiableProxy proxy = new OssifiableProxy(address(impl), owner, "");
        withdrawalQueue = WithdrawalQueue(payable(proxy));
    }

    function test_RequestWithdrawal_RevertWhenRebalancingDisabled() public {
        vm.expectRevert(WithdrawalQueue.RebalancingIsNotSupported.selector);
        withdrawalQueue.requestWithdrawal(address(this), 1, 1);
    }

    function test_RequestWithdrawalBatch_RevertWhenRebalancingDisabled() public {
        uint256[] memory stvAmounts = new uint256[](1);
        stvAmounts[0] = 1;

        uint256[] memory stethShares = new uint256[](1);
        stethShares[0] = 1;

        vm.expectRevert(WithdrawalQueue.RebalancingIsNotSupported.selector);
        withdrawalQueue.requestWithdrawalBatch(address(this), stvAmounts, stethShares);
    }
}
