// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {StvStETHPool} from "src/StvStETHPool.sol";
import {WithdrawalQueue} from "src/WithdrawalQueue.sol";
import {OssifiableProxy} from "src/proxy/OssifiableProxy.sol";
import {MockDashboard, MockDashboardFactory} from "test/mocks/MockDashboard.sol";
import {MockLazyOracle} from "test/mocks/MockLazyOracle.sol";
import {MockStETH} from "test/mocks/MockStETH.sol";
import {MockVaultHub} from "test/mocks/MockVaultHub.sol";

abstract contract SetupWithdrawalQueue is Test {
    WithdrawalQueue public withdrawalQueue;
    StvStETHPool public pool;
    MockLazyOracle public lazyOracle;
    MockDashboard public dashboard;
    MockVaultHub public vaultHub;
    MockStETH public steth;

    address public owner;
    address public finalizeRoleHolder;
    address public finalizePauseRoleHolder;
    address public finalizeResumeRoleHolder;
    address public withdrawalsPauseRoleHolder;
    address public withdrawalsResumeRoleHolder;
    address public userAlice;
    address public userBob;

    uint256 public constant MIN_WITHDRAWAL_DELAY_TIME = 1 days;
    uint256 public constant INITIAL_DEPOSIT = 1 ether;
    uint256 public constant RESERVE_RATIO_GAP_BP = 5_00; // 5%

    uint256 public constant STV_DECIMALS = 27;
    uint256 public constant ASSETS_DECIMALS = 18;

    function setUp() public virtual {
        // Create addresses
        owner = makeAddr("owner");
        finalizeRoleHolder = makeAddr("finalizeRoleHolder");
        finalizePauseRoleHolder = makeAddr("finalizePauseRoleHolder");
        finalizeResumeRoleHolder = makeAddr("finalizeResumeRoleHolder");
        withdrawalsPauseRoleHolder = makeAddr("withdrawalsPauseRoleHolder");
        withdrawalsResumeRoleHolder = makeAddr("withdrawalsResumeRoleHolder");
        userAlice = makeAddr("userAlice");
        userBob = makeAddr("userBob");

        // Fund accounts
        vm.deal(owner, 100 ether);
        vm.deal(userAlice, 1000 ether);
        vm.deal(userBob, 1000 ether);

        // Deploy mocks
        dashboard = new MockDashboardFactory().createMockDashboard(owner);
        lazyOracle = new MockLazyOracle();
        steth = dashboard.STETH();
        vaultHub = dashboard.VAULT_HUB();

        // Fund dashboard
        dashboard.fund{value: INITIAL_DEPOSIT}();

        // Deploy StvStETHPool proxy with temporary implementation
        StvStETHPool tempImpl = new StvStETHPool(
            address(dashboard), false, RESERVE_RATIO_GAP_BP, address(0), address(0), keccak256("test.wq.pool")
        );
        OssifiableProxy poolProxy = new OssifiableProxy(address(tempImpl), owner, "");
        pool = StvStETHPool(payable(poolProxy));

        // Deploy WithdrawalQueue with correct pool address
        WithdrawalQueue wqImpl = new WithdrawalQueue(
            address(pool),
            address(dashboard),
            address(vaultHub),
            address(steth),
            address(dashboard.VAULT()),
            address(lazyOracle),
            MIN_WITHDRAWAL_DELAY_TIME,
            true
        );

        OssifiableProxy wqProxy = new OssifiableProxy(address(wqImpl), owner, "");
        withdrawalQueue = WithdrawalQueue(payable(wqProxy));

        // Initialize WithdrawalQueue
        withdrawalQueue.initialize(owner, finalizeRoleHolder, owner, owner);

        // Grant additional roles
        vm.startPrank(owner);
        withdrawalQueue.grantRole(withdrawalQueue.WITHDRAWALS_PAUSE_ROLE(), withdrawalsPauseRoleHolder);
        withdrawalQueue.grantRole(withdrawalQueue.WITHDRAWALS_RESUME_ROLE(), withdrawalsResumeRoleHolder);
        withdrawalQueue.grantRole(withdrawalQueue.FINALIZE_PAUSE_ROLE(), finalizePauseRoleHolder);
        withdrawalQueue.grantRole(withdrawalQueue.FINALIZE_RESUME_ROLE(), finalizeResumeRoleHolder);
        vm.stopPrank();

        // Set oracle timestamp to current time
        lazyOracle.mock__updateLatestReportTimestamp(block.timestamp);

        // Deploy Wrapper implementation
        StvStETHPool poolImpl = new StvStETHPool(
            address(dashboard),
            false,
            RESERVE_RATIO_GAP_BP,
            address(withdrawalQueue),
            address(0),
            keccak256("test.wq.pool")
        );
        vm.prank(owner);
        poolProxy.proxy__upgradeTo(address(poolImpl));

        // Initialize pool
        pool.initialize(owner, "Test", "stvETH");
    }

    // Helper function to create and finalize a withdrawal request

    function _requestWithdrawalAndFinalize(uint256 _stvAmount) internal returns (uint256 requestId) {
        requestId = withdrawalQueue.requestWithdrawal(address(this), _stvAmount, 0);
        _finalizeRequests(1);
    }

    function _finalizeRequests(uint256 _maxRequests) internal {
        _warpAndMockOracleReport();

        vm.prank(finalizeRoleHolder);
        withdrawalQueue.finalize(_maxRequests, address(0));
    }

    function _warpAndMockOracleReport() internal {
        lazyOracle.mock__updateLatestReportTimestamp(block.timestamp);
        vm.warp(MIN_WITHDRAWAL_DELAY_TIME + 1 + block.timestamp);
    }
}
