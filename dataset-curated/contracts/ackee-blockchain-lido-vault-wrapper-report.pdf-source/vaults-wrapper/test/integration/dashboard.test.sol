// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {IOperatorGrid} from "src/interfaces/core/IOperatorGrid.sol";
import {IVaultHub} from "src/interfaces/core/IVaultHub.sol";
import {StvPoolHarness} from "test/utils/StvPoolHarness.sol";
import {TimelockHarness} from "test/utils/TimelockHarness.sol";

/**
 * @title DashboardTest
 * @notice Integration tests for Dashboard functionality
 */
contract DashboardTest is StvPoolHarness, TimelockHarness {
    WrapperContext ctx;

    // Deployment parameters
    uint256 nodeOperatorFeeBP = 200; // 2%
    uint256 confirmExpiry = CONFIRM_EXPIRY;
    address feeRecipient = NODE_OPERATOR;

    // Role holders
    address nodeOperatorManager = NODE_OPERATOR;

    function setUp() public {
        _initializeCore();

        ctx = _deployStvPool({enableAllowlist: false, nodeOperatorFeeBP: nodeOperatorFeeBP});
        _setupTimelock(address(ctx.timelock), NODE_OPERATOR, NODE_OPERATOR);
    }

    // Timelock tests

    function test_Dashboard_RolesAreSetCorrectly() public view {
        // Check that the timelock is the admin of the dashboard
        bytes32 adminRole = ctx.dashboard.DEFAULT_ADMIN_ROLE();
        assertTrue(ctx.dashboard.hasRole(adminRole, address(ctx.timelock)));
        assertEq(ctx.dashboard.getRoleMember(adminRole, 0), address(ctx.timelock));
        assertEq(ctx.dashboard.getRoleMemberCount(adminRole), 1);
        assertEq(ctx.dashboard.getRoleAdmin(adminRole), adminRole);

        // Check that the timelock has proposer and executor roles
        bytes32 proposerRole = ctx.timelock.PROPOSER_ROLE();
        bytes32 executorRole = ctx.timelock.EXECUTOR_ROLE();

        assertTrue(ctx.timelock.hasRole(proposerRole, timelockProposer));
        assertTrue(ctx.timelock.hasRole(executorRole, timelockExecutor));
    }

    // Methods required both DEFAULT_ADMIN_ROLE and NODE_OPERATOR_MANAGER_ROLE access:
    // - setFeeRate
    // - setConfirmExpiry
    // - correctSettledGrowth

    function test_Dashboard_CanSetFeeRate() public {
        assertEq(ctx.dashboard.feeRate(), nodeOperatorFeeBP);
        uint256 expectedOperatorFeeBP = nodeOperatorFeeBP + 100; // + 1%

        // 1. Set Fee Rate by Timelock
        _timelockSchedule(address(ctx.dashboard), abi.encodeWithSignature("setFeeRate(uint256)", expectedOperatorFeeBP));
        _timelockWarp();
        reportVaultValueChangeNoFees(ctx, 0); // setFeeRate() requires oracle report
        _timelockExecute(address(ctx.dashboard), abi.encodeWithSignature("setFeeRate(uint256)", expectedOperatorFeeBP));

        assertEq(ctx.dashboard.feeRate(), nodeOperatorFeeBP); // shouldn't change

        // 2. Set Fee Rate by Node Operator Manager
        vm.prank(nodeOperatorManager);
        bool updated = ctx.dashboard.setFeeRate(expectedOperatorFeeBP);
        assertTrue(updated);
        assertEq(uint256(ctx.dashboard.feeRate()), expectedOperatorFeeBP);
    }

    function test_Dashboard_CanSetConfirmExpiry() public {
        assertEq(ctx.dashboard.getConfirmExpiry(), confirmExpiry);
        uint256 newConfirmExpiry = confirmExpiry + 1 hours;

        // 1. Set Confirm Expiry by Timelock
        _timelockScheduleAndExecute(
            address(ctx.dashboard), abi.encodeWithSignature("setConfirmExpiry(uint256)", newConfirmExpiry)
        );
        assertEq(ctx.dashboard.getConfirmExpiry(), confirmExpiry); // shouldn't change

        // 2. Set Confirm Expiry by Node Operator Manager
        vm.prank(nodeOperatorManager);
        bool updated = ctx.dashboard.setConfirmExpiry(newConfirmExpiry);
        assertTrue(updated);
        assertEq(uint256(ctx.dashboard.getConfirmExpiry()), newConfirmExpiry);
    }

    function test_Dashboard_CanCorrectSettledGrowth() public {
        int256 initialSettledGrowth = ctx.dashboard.settledGrowth();
        int256 newSettledGrowth = initialSettledGrowth + 1;

        // 1. Correct Settled Growth by Timelock
        _timelockScheduleAndExecute(
            address(ctx.dashboard),
            abi.encodeWithSignature("correctSettledGrowth(int256,int256)", newSettledGrowth, initialSettledGrowth)
        );
        assertEq(ctx.dashboard.settledGrowth(), initialSettledGrowth); // shouldn't change

        // 2. Correct Settled Growth by Node Operator Manager
        vm.prank(nodeOperatorManager);
        bool updated = ctx.dashboard.correctSettledGrowth(newSettledGrowth, initialSettledGrowth);
        assertTrue(updated);
        assertEq(ctx.dashboard.settledGrowth(), newSettledGrowth);
    }

    // Methods required a DEFAULT_ADMIN_ROLE access:
    // - disburseAbnormallyHighFee
    // - recoverERC20
    // - collectERC20FromVault (can also be called from COLLECT_VAULT_ERC20_ROLE)

    function test_Dashboard_CanDisburseAbnormallyHighFee() public {
        _timelockScheduleAndExecute(address(ctx.dashboard), abi.encodeWithSignature("disburseAbnormallyHighFee()"));
    }

    function test_Dashboard_CanRecoverERC20() public {
        address receiver = makeAddr("receiver");

        // ERC20
        ERC20 tokenERC20 = new ERC20();
        uint256 amountERC20 = 1 * 10 ** 18;

        tokenERC20.mint(address(ctx.dashboard), amountERC20);

        _timelockScheduleAndExecute(
            address(ctx.dashboard),
            abi.encodeWithSignature("recoverERC20(address,address,uint256)", address(tokenERC20), receiver, amountERC20)
        );
        vm.assertEq(tokenERC20.balanceOf(receiver), amountERC20);

        // ETH
        address tokenETH = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
        uint256 amountETH = 1 ether;

        uint256 receiverInitialBalance = receiver.balance;
        vm.deal(address(ctx.dashboard), amountETH);

        _timelockScheduleAndExecute(
            address(ctx.dashboard),
            abi.encodeWithSignature("recoverERC20(address,address,uint256)", tokenETH, receiver, amountETH)
        );
        vm.assertEq(receiver.balance, receiverInitialBalance + amountETH);
    }

    function test_Dashboard_CanCollectERC20FromVault() public {
        ERC20 token = new ERC20();
        address receiver = makeAddr("receiver");
        uint256 amount = 1 * 10 ** 18;

        token.mint(address(ctx.vault), amount);

        _timelockScheduleAndExecute(
            address(ctx.dashboard),
            abi.encodeWithSignature("collectERC20FromVault(address,address,uint256)", address(token), receiver, amount)
        );
        vm.assertEq(token.balanceOf(receiver), amount);
    }

    // Methods required a single-role access:
    // - addFeeExemption. Requires NODE_OPERATOR_FEE_EXEMPT_ROLE
    // - setFeeRecipient. Requires NODE_OPERATOR_MANAGER_ROLE
    // - changeTier. Requires VAULT_CONFIGURATION_ROLE
    // - syncTier. Requires VAULT_CONFIGURATION_ROLE
    // - updateShareLimit. Requires VAULT_CONFIGURATION_ROLE

    function test_Dashboard_CanAddFeeExemption() public {
        // The role is not granted initially
        bytes32 feeExemptionRole = ctx.dashboard.NODE_OPERATOR_FEE_EXEMPT_ROLE();
        assertFalse(ctx.dashboard.hasRole(feeExemptionRole, address(this)));

        // Grant the role to this contract
        vm.prank(nodeOperatorManager);
        ctx.dashboard.grantRole(feeExemptionRole, address(this));
        assertTrue(ctx.dashboard.hasRole(feeExemptionRole, address(this)));

        // Add fee exemptions
        ctx.dashboard.addFeeExemption(1 wei);
    }

    function test_Dashboard_CanSetFeeRecipient() public {
        assertEq(ctx.dashboard.feeRecipient(), feeRecipient);
        address newFeeRecipient = makeAddr("newFeeRecipient");

        vm.prank(nodeOperatorManager);
        ctx.dashboard.setFeeRecipient(newFeeRecipient);
    }

    function test_Dashboard_CanChangeTier() public {
        // Register a new tier
        IOperatorGrid operatorGrid = core.operatorGrid();
        IOperatorGrid.TierParams memory tier = IOperatorGrid.TierParams({
            shareLimit: 10 * 10 ** 18,
            reserveRatioBP: 1000,
            forcedRebalanceThresholdBP: 500,
            infraFeeBP: 100,
            liquidityFeeBP: 50,
            reservationFeeBP: 25
        });
        IOperatorGrid.TierParams[] memory params = new IOperatorGrid.TierParams[](1);
        params[0] = tier;

        address registrator = operatorGrid.getRoleMember(operatorGrid.REGISTRY_ROLE(), 0);
        uint256 tierId = operatorGrid.tiersCount();

        vm.startPrank(registrator);
        operatorGrid.registerGroup(NODE_OPERATOR, 100 * 10 ** 18);

        vm.expectEmit(true, true, true, false);
        emit IOperatorGrid.TierAdded(NODE_OPERATOR, tierId, 0, 0, 0, 0, 0, 0);

        operatorGrid.registerTiers(NODE_OPERATOR, params);
        vm.stopPrank();

        // The role is not granted initially
        bytes32 vaultConfigurationRole = ctx.dashboard.VAULT_CONFIGURATION_ROLE();
        assertFalse(ctx.dashboard.hasRole(vaultConfigurationRole, address(this)));

        // Grant the role to this contract
        _timelockScheduleAndExecute(
            address(ctx.dashboard),
            abi.encodeWithSignature("grantRole(bytes32,address)", vaultConfigurationRole, address(this))
        );
        assertTrue(ctx.dashboard.hasRole(vaultConfigurationRole, address(this)));

        // Change tier
        ctx.dashboard.changeTier(tierId, 10 ** 18);
    }

    function test_Dashboard_CanSyncTier() public {
        // Modify the current tier
        IOperatorGrid operatorGrid = core.operatorGrid();
        (, uint256 tierId,,,,,,) = operatorGrid.vaultTierInfo(address(ctx.vault));

        uint256[] memory ids = new uint256[](1);
        ids[0] = tierId;

        IOperatorGrid.TierParams[] memory params = new IOperatorGrid.TierParams[](1);
        IOperatorGrid.Tier memory tier = operatorGrid.tier(tierId);
        params[0] = IOperatorGrid.TierParams({
            shareLimit: tier.shareLimit,
            reserveRatioBP: tier.reserveRatioBP,
            forcedRebalanceThresholdBP: tier.forcedRebalanceThresholdBP,
            infraFeeBP: tier.infraFeeBP + 1, // change infra fee
            liquidityFeeBP: tier.liquidityFeeBP,
            reservationFeeBP: tier.reservationFeeBP
        });

        address registrator = operatorGrid.getRoleMember(operatorGrid.REGISTRY_ROLE(), 0);
        vm.prank(registrator);
        operatorGrid.alterTiers(ids, params);

        // The role is not granted initially
        bytes32 vaultConfigurationRole = ctx.dashboard.VAULT_CONFIGURATION_ROLE();
        assertFalse(ctx.dashboard.hasRole(vaultConfigurationRole, address(this)));

        // Grant the role to this contract
        _timelockScheduleAndExecute(
            address(ctx.dashboard),
            abi.encodeWithSignature("grantRole(bytes32,address)", vaultConfigurationRole, address(this))
        );
        assertTrue(ctx.dashboard.hasRole(vaultConfigurationRole, address(this)));

        // Sync tier
        ctx.dashboard.syncTier();
    }

    function test_Dashboard_CanUpdateShareLimit() public {
        uint256 currentShareLimit = ctx.dashboard.vaultConnection().shareLimit;
        assertGt(currentShareLimit, 10 ** 18);

        uint256 newShareLimit = currentShareLimit - 10 ** 18;

        // The role is not granted initially
        bytes32 vaultConfigurationRole = ctx.dashboard.VAULT_CONFIGURATION_ROLE();
        assertFalse(ctx.dashboard.hasRole(vaultConfigurationRole, address(this)));

        // Grant the role to this contract
        _timelockScheduleAndExecute(
            address(ctx.dashboard),
            abi.encodeWithSignature("grantRole(bytes32,address)", vaultConfigurationRole, address(this))
        );
        assertTrue(ctx.dashboard.hasRole(vaultConfigurationRole, address(this)));

        // Update share limit
        ctx.dashboard.updateShareLimit(newShareLimit);
    }

    // Voluntary disconnect from VaultHub

    function test_Dashboard_CanVoluntaryDisconnect() public {
        IVaultHub vaultHub = core.vaultHub();

        // Verify initial connection state
        assertTrue(vaultHub.isVaultConnected(address(ctx.vault)));
        assertFalse(vaultHub.isPendingDisconnect(address(ctx.vault)));

        // Schedule and execute disconnect
        _timelockSchedule(address(ctx.dashboard), abi.encodeWithSignature("voluntaryDisconnect()"));
        _timelockWarp();
        reportVaultValueChangeNoFees(ctx, 0); // voluntaryDisconnect() requires fresh oracle report
        _timelockExecute(address(ctx.dashboard), abi.encodeWithSignature("voluntaryDisconnect()"));

        // Verify disconnect is pending
        assertTrue(vaultHub.isVaultConnected(address(ctx.vault)));
        assertTrue(vaultHub.isPendingDisconnect(address(ctx.vault)));

        // Apply oracle report to finalize disconnect
        IVaultHub.VaultRecord memory vaultRecord = vaultHub.vaultRecord(address(ctx.vault));

        vm.prank(address(core.lazyOracle()));
        vaultHub.applyVaultReport({
            _vault: address(ctx.vault),
            _reportTimestamp: block.timestamp,
            _reportTotalValue: vaultRecord.report.totalValue,
            _reportInOutDelta: vaultRecord.report.inOutDelta,
            _reportCumulativeLidoFees: vaultRecord.cumulativeLidoFees,
            _reportLiabilityShares: vaultRecord.liabilityShares,
            _reportMaxLiabilityShares: vaultRecord.maxLiabilityShares,
            _reportSlashingReserve: 0
        });

        assertFalse(vaultHub.isVaultConnected(address(ctx.vault)));
    }
}

contract ERC20 is ERC20Upgradeable {
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}
