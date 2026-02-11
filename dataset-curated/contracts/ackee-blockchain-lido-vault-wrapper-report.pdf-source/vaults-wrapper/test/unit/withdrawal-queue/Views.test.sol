// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {SetupWithdrawalQueue} from "./SetupWithdrawalQueue.sol";
import {Test} from "forge-std/Test.sol";
import {WithdrawalQueue} from "src/WithdrawalQueue.sol";

contract ViewsTest is Test, SetupWithdrawalQueue {
    function setUp() public override {
        super.setUp();
    }

    function test_CalculateCurrentStvRate_InitialMatchesFormula() public view {
        assertEq(withdrawalQueue.calculateCurrentStvRate(), 10 ** 27);
    }

    function test_CalculateCurrentStvRate_TracksAssetsAfterRewardsAndPenalties() public {
        dashboard.mock_simulateRewards(1 ether);
        assertEq(withdrawalQueue.calculateCurrentStvRate(), 10 ** 27 * 2);

        dashboard.mock_simulateRewards(-1 ether);
        assertEq(withdrawalQueue.calculateCurrentStvRate(), 10 ** 27);
    }

    function test_CalculateCurrentStethShareRate_FollowsOracleValue() public {
        uint256 precision = withdrawalQueue.E27_PRECISION_BASE();
        steth.mock_setTotalPooled(10, 20);
        assertEq(withdrawalQueue.calculateCurrentStethShareRate(), precision / 2);

        steth.mock_setTotalPooled(90, 30);
        assertEq(withdrawalQueue.calculateCurrentStethShareRate(), precision * 3);
    }

    function test_GetWithdrawalStatus_ArrayMatchesSingle() public {
        pool.depositETH{value: 100 ether}(address(this), address(0));
        uint256 requestId1 = withdrawalQueue.requestWithdrawal(address(this), 10 ** STV_DECIMALS, 0);
        uint256 requestId2 = withdrawalQueue.requestWithdrawal(address(this), 2 * 10 ** STV_DECIMALS, 0);

        uint256[] memory ids = new uint256[](2);
        ids[0] = requestId1;
        ids[1] = requestId2;

        WithdrawalQueue.WithdrawalRequestStatus[] memory statuses = withdrawalQueue.getWithdrawalStatusBatch(ids);
        assertEq(statuses.length, 2);
        assertEq(statuses[0].amountOfStv, 10 ** STV_DECIMALS);
        assertEq(statuses[1].amountOfStv, 2 * 10 ** STV_DECIMALS);
        assertFalse(statuses[0].isFinalized);
        assertFalse(statuses[1].isFinalized);

        lazyOracle.mock__updateLatestReportTimestamp(block.timestamp);
        _finalizeRequests(1);

        WithdrawalQueue.WithdrawalRequestStatus memory statusSingle = withdrawalQueue.getWithdrawalStatus(requestId1);
        assertTrue(statusSingle.isFinalized);
        assertFalse(statusSingle.isClaimed);

        statuses = withdrawalQueue.getWithdrawalStatusBatch(ids);
        assertTrue(statuses[0].isFinalized);
        assertFalse(statuses[0].isClaimed);
        assertFalse(statuses[1].isFinalized);
    }

    function test_GetWithdrawalStatus_RevertOnInvalidRequestId() public {
        vm.expectRevert(abi.encodeWithSelector(WithdrawalQueue.InvalidRequestId.selector, 0));
        withdrawalQueue.getWithdrawalStatus(0);

        uint256[] memory ids = new uint256[](1);
        ids[0] = 0;
        vm.expectRevert(abi.encodeWithSelector(WithdrawalQueue.InvalidRequestId.selector, 0));
        withdrawalQueue.getWithdrawalStatusBatch(ids);
    }

    function test_GetWithdrawalStatusBatch_RevertWhenArrayContainsZero() public {
        pool.depositETH{value: 100 ether}(address(this), address(0));
        uint256 requestId = withdrawalQueue.requestWithdrawal(address(this), 10 ** STV_DECIMALS, 0);

        uint256[] memory ids = new uint256[](2);
        ids[0] = requestId;
        ids[1] = 0;

        vm.expectRevert(abi.encodeWithSelector(WithdrawalQueue.InvalidRequestId.selector, 0));
        withdrawalQueue.getWithdrawalStatusBatch(ids);
    }

    function test_GetClaimableEther_ViewLifecycle() public {
        pool.depositETH{value: 100 ether}(address(this), address(0));
        uint256 requestId = withdrawalQueue.requestWithdrawal(address(this), 10 ** STV_DECIMALS, 0);

        assertEq(withdrawalQueue.getClaimableEther(requestId), 0);

        lazyOracle.mock__updateLatestReportTimestamp(block.timestamp);
        _finalizeRequests(1);

        uint256[] memory requestIds = new uint256[](1);
        requestIds[0] = requestId;
        uint256[] memory hints =
            withdrawalQueue.findCheckpointHintBatch(requestIds, 1, withdrawalQueue.getLastCheckpointIndex());

        uint256 claimable = withdrawalQueue.getClaimableEther(requestId);
        assertGt(claimable, 0);

        uint256[] memory batchClaimable = withdrawalQueue.getClaimableEtherBatch(requestIds, hints);
        assertEq(batchClaimable[0], claimable);

        withdrawalQueue.claimWithdrawal(address(this), requestId);
        assertEq(withdrawalQueue.getClaimableEther(requestId), 0);

        batchClaimable = withdrawalQueue.getClaimableEtherBatch(requestIds, hints);
        assertEq(batchClaimable[0], 0);
    }

    function test_GetClaimableEtherBatch_ReturnsZeroForUnfinalized() public {
        pool.depositETH{value: 100 ether}(address(this), address(0));
        uint256 requestId = withdrawalQueue.requestWithdrawal(address(this), 10 ** STV_DECIMALS, 0);

        uint256[] memory requestIds = new uint256[](1);
        requestIds[0] = requestId;
        uint256[] memory hints = new uint256[](1);
        hints[0] = 0;

        uint256[] memory claimable = withdrawalQueue.getClaimableEtherBatch(requestIds, hints);
        assertEq(claimable[0], 0);

        assertEq(withdrawalQueue.getClaimableEther(requestId), 0);
    }

    receive() external payable {}
}
