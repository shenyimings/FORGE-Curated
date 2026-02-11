// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {StvStETHPool} from "src/StvStETHPool.sol";
import {IVaultHub} from "src/interfaces/core/IVaultHub.sol";
import {IWstETH} from "src/interfaces/core/IWstETH.sol";
import {FeaturePausable} from "src/utils/FeaturePausable.sol";
import {StvStETHPoolHarness} from "test/utils/StvStETHPoolHarness.sol";
import {TimelockHarness} from "test/utils/TimelockHarness.sol";

/**
 * @title DisconnectTest
 * @notice Disconnection flow steps
 *
 * - Inform users about upcoming disconnect and timeline
 * - Make sure all roles you will need are assigned
 * - Exit all validators
 *    - Voluntarily if possible
 *    - Forcibly if needed:
 *      - Call `triggerValidatorWithdrawals` on Pool contract from `TRIGGER_VALIDATOR_WITHDRAWAL_ROLE`
 * - Finalize all withdrawal requests
 * - Pause deposits and minting (if enabled) on Pool contract and withdrawals on Withdrawal Queue contract
 *    - Call `pauseDeposits` method on Pool contract from `DEPOSITS_PAUSE_ROLE`
 *    - Call `pauseMinting` method on Pool contract from `MINTING_PAUSE_ROLE`
 *    - Call `pauseWithdrawals` method on Withdrawal Queue contract from `WITHDRAWALS_PAUSE_ROLE`
 * - Rebalance Staking Vault if liability shares are left
 *    - Rebalance Staking Vault to zero liability
 *      - Call `rebalanceVaultWithShares` on Dashboard contract from `REBALANCE_ROLE`
 *    - Ensure no undercollateralized users. Force rebalance them if any exist
 *      - Call `forceRebalanceAndSocializeLoss` on Pool contract from `LOSS_SOCIALIZER_ROLE`
 * - Disconnect Staking Vault
 *    - Initiate voluntary disconnect on Dashboard from Timelock Controller
 * - Withdraw assets from Staking Vault and distribute them to users
 *    - Make sure you account for Initial Connect Deposit that remains locked in the vault
 */
contract DisconnectTest is StvStETHPoolHarness, TimelockHarness {
    WrapperContext ctx;

    address finalizer = NODE_OPERATOR;

    function setUp() public {
        _initializeCore();

        ctx = _deployStvStETHPool({enableAllowlist: false, nodeOperatorFeeBP: 200, reserveRatioGapBP: 500});
        _setupTimelock(address(ctx.timelock), NODE_OPERATOR, NODE_OPERATOR);

        vm.deal(address(this), 100 ether);
    }

    function test_Disconnect_InitialState() public view {
        // Vault is connected
        assertTrue(core.vaultHub().isVaultConnected(address(ctx.vault)), "Vault should be connected");
        assertFalse(core.vaultHub().isPendingDisconnect(address(ctx.vault)), "Vault should not be pending disconnect");

        // Pool has assets and supply
        assertGt(ctx.pool.totalAssets(), 0, "Pool should have assets");
        assertGt(ctx.pool.totalSupply(), 0, "Pool should have supply");

        // No liability
        assertEq(ctx.dashboard.liabilityShares(), 0, "Should have no liability shares initially");
    }

    function test_Disconnect_VoluntaryDisconnect() public {
        IVaultHub vaultHub = core.vaultHub();
        StvStETHPool pool = stvStETHPool(ctx);

        // Users can deposit before disconnect
        uint256 depositAmount = 10 ether;
        pool.depositETH{value: depositAmount}(address(this), address(0));
        assertGt(pool.balanceOf(address(this)), 0, "User should receive STV tokens");
        assertApproxEqAbs(
            pool.assetsOf(address(this)), depositAmount, WEI_ROUNDING_TOLERANCE, "User assets should match deposit"
        );

        // Users can mint stETH before disconnect
        uint256 stethSharesToMint = 10 ** 18;
        pool.mintStethShares(stethSharesToMint);
        assertEq(pool.mintedStethSharesOf(address(this)), stethSharesToMint, "User should have minted stETH shares");

        // Disconnect should revert since liability shares are not zero
        vm.prank(address(ctx.timelock));
        vm.expectRevert(
            abi.encodeWithSignature(
                "NoLiabilitySharesShouldBeLeft(address,uint256)", address(ctx.vault), stethSharesToMint
            )
        );
        ctx.dashboard.voluntaryDisconnect();

        // Users have time to exit from the pool
        uint256 requestId = ctx.withdrawalQueue.requestWithdrawal(address(this), pool.balanceOf(address(this)) / 5, 0);
        vm.warp(block.timestamp + 30 days);

        // Assign roles to temp trusted actor
        address trustedActor = makeAddr("trustedActor");
        vm.deal(trustedActor, 10 ether);

        address[] memory targets = new address[](7);
        bytes[] memory payloads = new bytes[](7);

        targets[0] = address(pool);
        targets[1] = address(pool);
        targets[2] = address(pool);
        targets[3] = address(ctx.withdrawalQueue);
        targets[4] = address(ctx.withdrawalQueue);
        targets[5] = address(ctx.dashboard);
        targets[6] = address(ctx.dashboard);

        bytes32 lossSocializerRole = pool.LOSS_SOCIALIZER_ROLE();
        bytes32 depositsPauseRole = pool.DEPOSITS_PAUSE_ROLE();
        bytes32 mintingPauseRole = pool.MINTING_PAUSE_ROLE();
        bytes32 withdrawalsPauseRole = ctx.withdrawalQueue.WITHDRAWALS_PAUSE_ROLE();
        bytes32 finalizeRole = ctx.withdrawalQueue.FINALIZE_ROLE();
        bytes32 triggerValidatorRole = ctx.dashboard.TRIGGER_VALIDATOR_WITHDRAWAL_ROLE();
        bytes32 rebalanceRole = ctx.dashboard.REBALANCE_ROLE();

        payloads[0] = abi.encodeWithSignature("grantRole(bytes32,address)", lossSocializerRole, trustedActor);
        payloads[1] = abi.encodeWithSignature("grantRole(bytes32,address)", depositsPauseRole, trustedActor);
        payloads[2] = abi.encodeWithSignature("grantRole(bytes32,address)", mintingPauseRole, trustedActor);
        payloads[3] = abi.encodeWithSignature("grantRole(bytes32,address)", withdrawalsPauseRole, trustedActor);
        payloads[4] = abi.encodeWithSignature("grantRole(bytes32,address)", finalizeRole, trustedActor);
        payloads[5] = abi.encodeWithSignature("grantRole(bytes32,address)", triggerValidatorRole, trustedActor);
        payloads[6] = abi.encodeWithSignature("grantRole(bytes32,address)", rebalanceRole, trustedActor);

        _timelockScheduleAndExecuteBatch(targets, payloads);

        // Verify roles assigned
        assertTrue(pool.hasRole(lossSocializerRole, trustedActor), "Loss socializer role should be granted");
        assertTrue(pool.hasRole(depositsPauseRole, trustedActor), "Deposits pause role should be granted");
        assertTrue(pool.hasRole(mintingPauseRole, trustedActor), "Minting pause role should be granted");
        assertTrue(
            ctx.withdrawalQueue.hasRole(withdrawalsPauseRole, trustedActor), "Withdrawals pause role should be granted"
        );
        assertTrue(ctx.withdrawalQueue.hasRole(finalizeRole, trustedActor), "Finalize role should be granted");
        assertTrue(
            ctx.dashboard.hasRole(triggerValidatorRole, trustedActor), "Trigger validator role should be granted"
        );
        assertTrue(ctx.dashboard.hasRole(rebalanceRole, trustedActor), "Rebalance role should be granted");

        // Pause Withdrawal Queue
        bytes32 withdrawalsFeatureId = ctx.withdrawalQueue.WITHDRAWALS_FEATURE();
        vm.prank(trustedActor);
        ctx.withdrawalQueue.pauseWithdrawals();
        assertTrue(ctx.withdrawalQueue.isFeaturePaused(withdrawalsFeatureId), "Withdrawals feature should be paused");

        // Check withdrawal requests are paused
        uint256 toWithdrawAmount = pool.balanceOf(address(this)) / 5;
        assertGt(toWithdrawAmount, 0, "Amount to withdraw should be greater than zero");
        vm.expectRevert(abi.encodeWithSelector(FeaturePausable.FeaturePauseEnforced.selector, withdrawalsFeatureId));
        ctx.withdrawalQueue.requestWithdrawal(address(this), toWithdrawAmount, 0);

        // Check there are requests to finalize
        uint256 requestToFinalized = ctx.withdrawalQueue.unfinalizedRequestsNumber();
        assertGt(requestToFinalized, 0, "Should have unfinalized withdrawal requests");

        // Oracle report to update vault state
        reportVaultValueChangeNoFees(ctx, 100_00);

        // Finalize all withdrawal requests
        vm.prank(trustedActor);
        ctx.withdrawalQueue.finalize(requestToFinalized, address(0));
        assertEq(ctx.withdrawalQueue.unfinalizedRequestsNumber(), 0, "All requests should be finalized");
        assertEq(ctx.withdrawalQueue.unfinalizedStv(), 0, "No unfinalized STV should remain");
        assertEq(ctx.withdrawalQueue.unfinalizedAssets(), 0, "No unfinalized assets should remain");
        assertEq(ctx.withdrawalQueue.unfinalizedStethShares(), 0, "No unfinalized stETH shares should remain");

        // Pause Deposits
        bytes32 depositsFeatureId = pool.DEPOSITS_FEATURE();
        vm.prank(trustedActor);
        pool.pauseDeposits();
        assertTrue(pool.isFeaturePaused(depositsFeatureId), "Deposits feature should be paused");

        // Check deposits are paused
        vm.expectRevert(abi.encodeWithSelector(FeaturePausable.FeaturePauseEnforced.selector, depositsFeatureId));
        pool.depositETH{value: 1 ether}(address(this), address(0));

        // Pause Minting
        bytes32 mintingFeatureId = pool.MINTING_FEATURE();
        vm.prank(trustedActor);
        pool.pauseMinting();
        assertTrue(pool.isFeaturePaused(mintingFeatureId), "Minting feature should be paused");

        // Check minting is paused
        vm.expectRevert(abi.encodeWithSelector(FeaturePausable.FeaturePauseEnforced.selector, mintingFeatureId));
        pool.mintStethShares(10 ** 18);

        vm.expectRevert(abi.encodeWithSelector(FeaturePausable.FeaturePauseEnforced.selector, mintingFeatureId));
        pool.mintWsteth(10 ** 18);

        // Verify validators can be forcibly withdrawn
        bytes memory mockPubkey = new bytes(48);
        mockPubkey[47] = 0x01;

        uint64[] memory amountsInGwei = new uint64[](1);
        amountsInGwei[0] = 32 * 10 ** 9;

        uint256 withdrawalFee = 10 gwei;
        address twContract = 0x00000961Ef480Eb55e80D19ad83579A64c007002; // EL triggerable withdrawals (EIP-7002) contract

        vm.mockCall(twContract, new bytes(0), abi.encode(uint256(withdrawalFee)));
        vm.mockCall(twContract, bytes.concat(mockPubkey, bytes8(uint64(amountsInGwei[0]))), new bytes(0));
        vm.prank(trustedActor);
        ctx.dashboard.triggerValidatorWithdrawals{value: withdrawalFee}(mockPubkey, amountsInGwei, trustedActor);

        // Check vault has liability shares
        uint256 liabilityShares = ctx.dashboard.liabilityShares();
        assertGt(liabilityShares, 0, "Vault should have liability shares before rebalance");

        // Rebalance vault to zero liability
        vm.prank(trustedActor);
        ctx.dashboard.rebalanceVaultWithShares(liabilityShares);
        assertEq(ctx.dashboard.liabilityShares(), 0, "Liability shares should be zero after rebalance");

        // Schedule and execute disconnect
        _timelockSchedule(address(ctx.dashboard), abi.encodeWithSignature("voluntaryDisconnect()"));
        _timelockWarp();
        reportVaultValueChangeNoFees(ctx, 0); // voluntaryDisconnect() requires fresh oracle report
        _timelockExecute(address(ctx.dashboard), abi.encodeWithSignature("voluntaryDisconnect()"));

        // Verify disconnect is pending
        assertTrue(vaultHub.isVaultConnected(address(ctx.vault)), "Vault should still be connected");
        assertTrue(vaultHub.isPendingDisconnect(address(ctx.vault)), "Vault should be pending disconnect");

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
        assertFalse(vaultHub.isVaultConnected(address(ctx.vault)), "Vault should be disconnected after report");

        // Finalize disconnect by abandoning dashboard
        assertEq(ctx.vault.owner(), address(core.vaultHub()), "VaultHub should be vault owner initially");
        vm.prank(address(ctx.timelock));
        ctx.dashboard.abandonDashboard(trustedActor);

        vm.prank(trustedActor);
        ctx.vault.acceptOwnership();
        assertEq(ctx.vault.owner(), trustedActor, "Disconnect manager should be vault owner after transfer");

        // Check that claims are possible after disconnect
        uint256 balanceBefore = address(this).balance;
        uint256 claimableEther = ctx.withdrawalQueue.getClaimableEther(requestId);
        ctx.withdrawalQueue.claimWithdrawal(address(this), requestId);
        uint256 balanceAfter = address(this).balance;
        assertGt(claimableEther, 0, "Should have claimable ether");
        assertEq(balanceAfter - balanceBefore, claimableEther, "Claimed amount should match expected");

        // Check the vault has non zero assets to withdraw
        uint256 availableBalance = ctx.vault.availableBalance();
        assertGt(availableBalance, 0, "Vault should have available balance");
        assertEq(address(ctx.vault).balance, availableBalance, "Vault ETH balance should match available balance");

        // Withdraw assets from the vault to distributor contract
        address distributor = address(pool.DISTRIBUTOR());

        // Distributor has no eth support, so ETH should be converted to WETH or wstETH before
        IWstETH wsteth = core.wsteth();
        uint256 vaultWstethBalanceBefore = wsteth.balanceOf(address(ctx.vault));

        vm.prank(trustedActor);
        ctx.vault.withdraw(address(wsteth), availableBalance);
        uint256 vaultWstethBalanceAfter = wsteth.balanceOf(address(ctx.vault));
        assertGt(vaultWstethBalanceAfter, vaultWstethBalanceBefore, "Vault should receive wstETH after withdrawal");

        uint256 distributorWstethBalanceBefore = wsteth.balanceOf(distributor);
        vm.prank(trustedActor);
        ctx.vault.collectERC20(address(wsteth), distributor, vaultWstethBalanceAfter);
        uint256 distributorWstethBalanceAfter = wsteth.balanceOf(distributor);
        assertGt(distributorWstethBalanceAfter, distributorWstethBalanceBefore, "Distributor should receive wstETH");
    }

    // Fallback to receive ETH
    receive() external payable {}
}
