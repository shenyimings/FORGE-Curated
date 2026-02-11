// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {SetupWithdrawalQueue} from "./SetupWithdrawalQueue.sol";
import {Test} from "forge-std/Test.sol";

contract GasCostCoverageTest is Test, SetupWithdrawalQueue {
    function setUp() public override {
        super.setUp();

        vm.deal(address(this), 200_000 ether);
        vm.deal(finalizeRoleHolder, 10 ether);

        pool.depositETH{value: 100_000 ether}(address(this), address(0));
    }

    function _setGasCostCoverage(uint256 coverage) internal {
        vm.prank(finalizeRoleHolder);
        withdrawalQueue.setFinalizationGasCostCoverage(coverage);
    }

    function test_FinalizeGasCostCoverage_ZeroCoverageDoesNotPayFinalizer() public {
        uint256 initialBalance = finalizeRoleHolder.balance;
        _requestWithdrawalAndFinalize(10 ** STV_DECIMALS);

        assertEq(finalizeRoleHolder.balance, initialBalance);
    }

    function test_FinalizeGasCostCoverage_PaysFinalizerWhenSet() public {
        uint256 coverage = 0.0005 ether;
        uint256 initialBalance = finalizeRoleHolder.balance;

        _setGasCostCoverage(coverage);
        _requestWithdrawalAndFinalize(10 ** STV_DECIMALS);

        assertEq(finalizeRoleHolder.balance, initialBalance + coverage);
    }

    function test_FinalizeGasCostCoverage_ReducesClaimByCoverage() public {
        uint256 coverage = 0.0005 ether;
        _setGasCostCoverage(coverage);

        uint256 stvToRequest = 10 ** STV_DECIMALS;
        uint256 requestId = withdrawalQueue.requestWithdrawal(address(this), stvToRequest, 0);
        uint256 expectedAssets = pool.previewRedeem(stvToRequest);
        _finalizeRequests(1);

        uint256 balanceBefore = address(this).balance;
        uint256 claimed = withdrawalQueue.claimWithdrawal(address(this), requestId);

        assertEq(claimed, expectedAssets - coverage);
        assertEq(address(this).balance, balanceBefore + claimed);
    }

    function test_FinalizeGasCostCoverage_ReducesClaimableByCoverage() public {
        uint256 coverage = 0.0005 ether;
        _setGasCostCoverage(coverage);

        uint256 stvToRequest = 10 ** STV_DECIMALS;
        uint256 requestId = withdrawalQueue.requestWithdrawal(address(this), stvToRequest, 0);
        uint256 expectedAssets = pool.previewRedeem(stvToRequest);
        _finalizeRequests(1);

        assertEq(withdrawalQueue.getClaimableEther(requestId), expectedAssets - coverage);
    }

    function test_FinalizeGasCostCoverage_RequestWithRebalance() public {
        uint256 coverage = 0.0005 ether;
        _setGasCostCoverage(coverage);

        uint256 mintedStethShares = 10 ** ASSETS_DECIMALS;
        uint256 stvToRequest = 2 * 10 ** STV_DECIMALS;
        pool.mintStethShares(mintedStethShares);

        uint256 totalAssets = pool.previewRedeem(stvToRequest);
        uint256 assetsToRebalance = pool.STETH().getPooledEthBySharesRoundUp(mintedStethShares);
        uint256 expectedClaimable = totalAssets - assetsToRebalance - coverage;
        assertGt(expectedClaimable, 0);

        uint256 requestId = withdrawalQueue.requestWithdrawal(address(this), stvToRequest, mintedStethShares);
        _finalizeRequests(1);

        assertEq(withdrawalQueue.getClaimableEther(requestId), expectedClaimable);
    }

    function test_FinalizeGasCostCoverage_CoverageCapsToRemainingAssets() public {
        uint256 coverage = withdrawalQueue.MAX_GAS_COST_COVERAGE();
        uint256 minValue = withdrawalQueue.MIN_WITHDRAWAL_VALUE();
        _setGasCostCoverage(coverage);

        uint256 stvToRequest = (10 ** STV_DECIMALS * minValue) / 1 ether;
        uint256 totalAssets = pool.previewRedeem(stvToRequest);
        assertEq(totalAssets, minValue);

        uint256 requestId = withdrawalQueue.requestWithdrawal(address(this), stvToRequest, 0);
        dashboard.mock_simulateRewards(-int256(pool.totalAssets() - 1 ether));

        uint256 finalizerBalanceBefore = finalizeRoleHolder.balance;
        _finalizeRequests(1);
        uint256 finalizerBalanceAfter = finalizeRoleHolder.balance;

        assertGt(finalizerBalanceAfter, finalizerBalanceBefore);
        assertLt(finalizerBalanceAfter - finalizerBalanceBefore, coverage);

        assertEq(withdrawalQueue.getClaimableEther(requestId), 0);
    }

    function test_FinalizeGasCostCoverage_DifferentGasCostRecipient() public {
        uint256 coverage = 0.0005 ether;
        _setGasCostCoverage(coverage);

        address recipient = makeAddr("finalizerRecipient");
        withdrawalQueue.requestWithdrawal(address(this), 10 ** STV_DECIMALS, 0);

        uint256 finalizerBalanceBefore = finalizeRoleHolder.balance;
        uint256 recipientBalanceBefore = recipient.balance;

        _warpAndMockOracleReport();
        vm.prank(finalizeRoleHolder);
        uint256 finalizedRequests = withdrawalQueue.finalize(1, recipient);

        assertEq(finalizedRequests, 1);

        uint256 finalizerBalanceAfter = finalizeRoleHolder.balance;
        uint256 recipientBalanceAfter = recipient.balance;

        assertEq(finalizerBalanceAfter, finalizerBalanceBefore);
        assertEq(recipientBalanceAfter - recipientBalanceBefore, coverage);
    }

    // Receive ETH for claiming tests
    receive() external payable {}
}
