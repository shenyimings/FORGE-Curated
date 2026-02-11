// SPDX-License-Identifier: UNLICENSED
// Gearbox Protocol. Generalized leverage for DeFi protocols
// (c) Gearbox Foundation, 2024.
pragma solidity ^0.8.23;

import {Test} from "forge-std/Test.sol";

import {Governor} from "../market/Governor.sol";

import {IGovernor} from "../interfaces/IGovernor.sol";
import {ITimeLock} from "../interfaces/ITimeLock.sol";

contract TargetMock {
    fallback() external payable {}
}

contract GovernorUnitTest is Test {
    Governor governor;

    address timeLock;
    uint256 delay;

    address target0;
    address target1;
    address owner;
    address vetoAdmin;
    address queueAdmin;
    address executionAdmin;

    function setUp() public {
        target0 = address(new TargetMock());
        target1 = address(new TargetMock());
        owner = makeAddr("owner");
        vetoAdmin = makeAddr("vetoAdmin");
        queueAdmin = makeAddr("queueAdmin");
        executionAdmin = makeAddr("executionAdmin");

        governor = new Governor(owner, vetoAdmin, 1 days, true);

        timeLock = governor.timeLock();
        delay = ITimeLock(timeLock).delay();
        uint256 eta = block.timestamp + delay;

        vm.startPrank(owner);
        governor.queueTransaction(address(governor), 0, "addQueueAdmin(address)", abi.encode(queueAdmin), eta);
        governor.queueTransaction(address(governor), 0, "addExecutionAdmin(address)", abi.encode(executionAdmin), eta);
        vm.warp(eta);
        governor.executeTransaction(address(governor), 0, "addQueueAdmin(address)", abi.encode(queueAdmin), eta);
        governor.executeTransaction(address(governor), 0, "addExecutionAdmin(address)", abi.encode(executionAdmin), eta);
        vm.stopPrank();
    }

    // ------- //
    // GENERAL //
    // ------- //

    function test_GOV_01_setUp_is_correct() public view {
        assertEq(ITimeLock(timeLock).admin(), address(governor), "Timelock admin");
        assertEq(governor.vetoAdmin(), vetoAdmin, "Veto admin");
        assertEq(governor.queueAdmins(), _toDyn([queueAdmin]), "Queue admins");
        assertEq(governor.executionAdmins(), _toDyn([executionAdmin]), "Queue admins");
        assertTrue(governor.isPermissionlessExecutionAllowed(), "Permissionless execution is forbiden");
    }

    function test_GOV_02_constructor_reverts_on_zero_veto_admin() public {
        vm.expectRevert(IGovernor.AdminCantBeZeroAddressException.selector);
        new Governor(owner, address(0), 1 days, false);
    }

    function test_GOV_03_constructor_works_as_expected() public {
        vm.expectEmit(true, true, true, true);
        emit IGovernor.UpdateVetoAdmin(vetoAdmin);

        vm.expectEmit(true, true, true, true);
        emit IGovernor.AllowPermissionlessExecution();

        governor = new Governor(owner, vetoAdmin, 1 days, true);

        assertEq(governor.owner(), owner, "Owner");
        assertEq(governor.vetoAdmin(), vetoAdmin, "Veto admin");
        assertEq(governor.queueAdmins().length, 0, "Queue admins");
        assertEq(governor.executionAdmins().length, 0, "Execution admins");
        assertTrue(governor.isPermissionlessExecutionAllowed(), "Permissionless execution is forbidden");
    }

    function test_GOV_04_external_functions_have_correct_access_rights() public {
        vm.expectRevert(IGovernor.CallerNotQueueAdminException.selector);
        governor.queueTransaction(address(0), 0, "", "", block.timestamp + delay);

        vm.expectRevert(IGovernor.CallerNotQueueAdminException.selector);
        governor.startBatch(0);

        vm.expectRevert(IGovernor.CallerNotVetoAdminException.selector);
        governor.cancelTransaction(address(0), 0, "", "", 0);

        vm.expectRevert(IGovernor.CallerNotVetoAdminException.selector);
        governor.cancelBatch(new IGovernor.TxParams[](0));

        vm.expectRevert(IGovernor.CallerNotTimelockException.selector);
        governor.addQueueAdmin(address(0));

        vm.expectRevert(IGovernor.CallerNotTimelockException.selector);
        governor.removeQueueAdmin(address(0));

        vm.expectRevert(IGovernor.CallerNotTimelockException.selector);
        governor.addExecutionAdmin(address(0));

        vm.expectRevert(IGovernor.CallerNotTimelockException.selector);
        governor.removeExecutionAdmin(address(0));

        vm.expectRevert(IGovernor.CallerNotTimelockException.selector);
        governor.updateVetoAdmin(address(0));

        vm.expectRevert(IGovernor.CallerNotTimelockException.selector);
        governor.allowPermissionlessExecution();

        vm.expectRevert(IGovernor.CallerNotTimelockException.selector);
        governor.forbidPermissionlessExecution();
    }

    // ------- //
    // ACTIONS //
    // ------- //

    function test_GOV_05_queueTransaction_reverts_if_transaction_is_already_queued_in_timelock() public {
        uint256 eta = block.timestamp + delay;

        vm.prank(owner);
        governor.queueTransaction(target0, 123, "signature", "data", eta);

        vm.expectRevert(IGovernor.TransactionAlreadyQueuedException.selector);
        vm.prank(owner);
        governor.queueTransaction(target0, 123, "signature", "data", eta);
    }

    function test_GOV_06_queueTransaction_works_as_expected_when_batch_is_not_initiated() public {
        uint256 eta = block.timestamp + delay;

        vm.expectCall(timeLock, abi.encodeCall(ITimeLock.queueTransaction, (target0, 123, "signature", "data", eta)));

        vm.prank(owner);
        bytes32 txHash = governor.queueTransaction(target0, 123, "signature", "data", eta);

        assertEq(txHash, _getTxHash(target0, 123, "signature", "data", eta), "Tx hash");
        assertTrue(ITimeLock(timeLock).queuedTransactions(txHash), "Tx not queued");

        (uint64 batchBlock,) = governor.batchedTxInfo(txHash);
        assertEq(batchBlock, 0, "Batch block");
    }

    function test_GOV_07_startBatch_reverts_if_batch_is_already_started() public {
        vm.prank(owner);
        governor.startBatch(123);

        vm.expectRevert(IGovernor.BatchAlreadyStartedException.selector);

        vm.prank(queueAdmin);
        governor.startBatch(456);
    }

    function test_GOV_08_startBatch_works_as_expected() public {
        vm.expectEmit(true, true, true, true);
        emit IGovernor.QueueBatch(owner, block.number);

        vm.prank(owner);
        governor.startBatch(uint80(block.timestamp + delay));

        (address initiator, uint16 length, uint80 eta) = governor.batchInfo(block.number);

        assertEq(initiator, owner, "Inititator");
        assertEq(length, 0, "Length");
        assertEq(eta, block.timestamp + delay, "ETA");
    }

    function test_GOV_09_queueTransaction_reverts_if_caller_is_not_batch_initiator() public {
        uint256 eta = block.timestamp + delay;

        vm.prank(owner);
        governor.startBatch(uint80(eta));

        vm.expectRevert(IGovernor.CallerNotBatchInitiatorException.selector);

        vm.prank(queueAdmin);
        governor.queueTransaction(target0, 123, "signature", "data", eta);
    }

    function test_GOV_10_queueTransaction_reverts_if_eta_is_different_from_batch_eta() public {
        uint256 eta = block.timestamp + delay;

        vm.prank(owner);
        governor.startBatch(uint80(eta));

        vm.expectRevert(IGovernor.ETAMistmatchException.selector);

        vm.prank(owner);
        governor.queueTransaction(target0, 123, "signature", "data", eta + 1);
    }

    function test_GOV_11_queueTransaction_works_as_expected_when_batch_is_initiated() public {
        uint256 batchBlock = block.number;
        uint256 eta = block.timestamp + delay;

        vm.startPrank(owner);
        governor.startBatch(uint80(eta));

        vm.expectCall(timeLock, abi.encodeCall(ITimeLock.queueTransaction, (target0, 123, "signature", "data", eta)));
        bytes32 tx1Hash = governor.queueTransaction(target0, 123, "signature", "data", eta);

        vm.expectCall(timeLock, abi.encodeCall(ITimeLock.queueTransaction, (target1, 123, "signature", "data", eta)));
        bytes32 tx2Hash = governor.queueTransaction(target1, 123, "signature", "data", eta);
        vm.stopPrank();

        vm.roll(block.number + 42);

        assertEq(tx1Hash, _getTxHash(target0, 123, "signature", "data", eta), "Tx 1 hash");
        assertEq(tx2Hash, _getTxHash(target1, 123, "signature", "data", eta), "Tx 2 hash");
        assertTrue(ITimeLock(timeLock).queuedTransactions(tx1Hash), "Tx 1 not queued");
        assertTrue(ITimeLock(timeLock).queuedTransactions(tx2Hash), "Tx 2 not queued");

        (, uint16 length,) = governor.batchInfo(batchBlock);
        assertEq(length, 2, "Batch length");

        (uint64 tx1BatchBlock, uint16 tx1Index) = governor.batchedTxInfo(tx1Hash);
        assertEq(tx1BatchBlock, batchBlock, "Tx 1 batch block");
        assertEq(tx1Index, 0, "Tx 1 batch index");

        (uint64 tx2BatchBlock, uint16 tx2Index) = governor.batchedTxInfo(tx2Hash);
        assertEq(tx2BatchBlock, batchBlock, "Tx 2 batch block");
        assertEq(tx2Index, 1, "Tx 2 batch index");
    }

    function test_GOV_12_executeTransaction_and_cancelTransaction_revert_if_tx_is_part_of_batch() public {
        uint256 eta = block.timestamp + delay;

        vm.startPrank(owner);
        governor.startBatch(uint80(eta));
        governor.queueTransaction(target0, 123, "signature", "data", eta);
        vm.stopPrank();

        vm.expectRevert(IGovernor.CantPerformActionOutsideBatchException.selector);
        vm.prank(vetoAdmin);
        governor.cancelTransaction(target0, 123, "signature", "data", eta);

        vm.expectRevert(IGovernor.CantPerformActionOutsideBatchException.selector);
        governor.executeTransaction(target0, 123, "signature", "data", eta);
    }

    function test_GOV_13_executeTransaction_and_cancelTransaction_work_as_expected_for_individual_txs() public {
        uint256 eta = block.timestamp + delay;

        vm.prank(owner);
        bytes32 txHash = governor.queueTransaction(target0, 123, "signature", "data", eta);

        vm.warp(eta);

        uint256 snap = vm.snapshot();

        // cancellation
        vm.expectCall(timeLock, abi.encodeCall(ITimeLock.cancelTransaction, (target0, 123, "signature", "data", eta)));
        vm.prank(vetoAdmin);
        governor.cancelTransaction(target0, 123, "signature", "data", eta);
        assertFalse(ITimeLock(timeLock).queuedTransactions(txHash), "Tx still queued");

        vm.revertTo(snap);

        // execution
        vm.expectCall(timeLock, abi.encodeCall(ITimeLock.executeTransaction, (target0, 123, "signature", "data", eta)));
        governor.executeTransaction{value: 123}(target0, 123, "signature", "data", eta);
        assertFalse(ITimeLock(timeLock).queuedTransactions(txHash), "Tx still queued");
    }

    function test_GOV_14_executeBatch_and_cancelBatch_revert_if_provided_batch_is_incorrect() public {
        uint256 eta = block.timestamp + delay;

        vm.startPrank(owner);
        governor.startBatch(uint80(eta));
        governor.queueTransaction(target0, 123, "signature", "data", eta);
        governor.queueTransaction(target1, 123, "signature", "data", eta);
        vm.stopPrank();

        vm.warp(eta);

        // empty batch
        IGovernor.TxParams[] memory txs;
        vm.expectRevert(IGovernor.IncorrectBatchException.selector);
        vm.prank(vetoAdmin);
        governor.cancelBatch(txs);

        vm.expectRevert(IGovernor.IncorrectBatchException.selector);
        governor.executeBatch(txs);

        // missing tx
        txs = new IGovernor.TxParams[](1);
        txs[0] = IGovernor.TxParams(target0, 123, "signature", "data", eta);
        vm.expectRevert(IGovernor.IncorrectBatchException.selector);
        vm.prank(vetoAdmin);
        governor.cancelBatch(txs);

        vm.expectRevert(IGovernor.IncorrectBatchException.selector);
        governor.executeBatch{value: 123}(txs);

        // extra tx
        txs = new IGovernor.TxParams[](3);
        txs[0] = IGovernor.TxParams(target0, 123, "signature", "data", eta);
        txs[1] = IGovernor.TxParams(target1, 123, "signature", "data", eta);
        txs[2] = IGovernor.TxParams(target0, 123, "signature", "baddata", eta);
        vm.expectRevert(IGovernor.IncorrectBatchException.selector);
        vm.prank(vetoAdmin);
        governor.cancelBatch(txs);

        vm.expectRevert(IGovernor.IncorrectBatchException.selector);
        governor.executeBatch{value: 369}(txs);

        // wrong tx
        txs = new IGovernor.TxParams[](2);
        txs[0] = IGovernor.TxParams(target0, 123, "signature", "data", eta);
        txs[1] = IGovernor.TxParams(target1, 123, "signature", "baddata", eta);

        bytes32 txHash = _getTxHash(target1, 123, "signature", "baddata", eta);
        vm.expectRevert(abi.encodeWithSelector(IGovernor.UnexpectedTransactionException.selector, txHash));
        vm.prank(vetoAdmin);
        governor.cancelBatch(txs);

        vm.expectRevert(abi.encodeWithSelector(IGovernor.UnexpectedTransactionException.selector, txHash));
        governor.executeBatch{value: 246}(txs);

        // wrong tx order
        txs = new IGovernor.TxParams[](2);
        txs[0] = IGovernor.TxParams(target1, 123, "signature", "data", eta);
        txs[1] = IGovernor.TxParams(target0, 123, "signature", "data", eta);
        txHash = _getTxHash(target1, 123, "signature", "data", eta);

        vm.expectRevert(abi.encodeWithSelector(IGovernor.UnexpectedTransactionException.selector, txHash));
        vm.prank(vetoAdmin);
        governor.cancelBatch(txs);

        vm.expectRevert(abi.encodeWithSelector(IGovernor.UnexpectedTransactionException.selector, txHash));
        governor.executeBatch{value: 246}(txs);
    }

    function test_GOV_15_executeBatch_and_cancelBatch_work_as_expected() public {
        uint256 eta = block.timestamp + delay;
        uint256 batchBlock = block.number;

        vm.startPrank(owner);
        governor.startBatch(uint80(eta));
        bytes32 tx1Hash = governor.queueTransaction(target0, 123, "signature", "data", eta);
        bytes32 tx2Hash = governor.queueTransaction(target1, 123, "signature", "data", eta);
        vm.stopPrank();

        vm.warp(eta);
        vm.roll(block.number + 42);

        IGovernor.TxParams[] memory txs = new IGovernor.TxParams[](2);
        txs[0] = IGovernor.TxParams(target0, 123, "signature", "data", eta);
        txs[1] = IGovernor.TxParams(target1, 123, "signature", "data", eta);

        uint256 snap = vm.snapshot();

        // cancellation
        vm.expectEmit(true, true, true, true);
        emit IGovernor.CancelBatch(vetoAdmin, batchBlock);

        vm.expectCall(timeLock, abi.encodeCall(ITimeLock.cancelTransaction, (target0, 123, "signature", "data", eta)));
        vm.expectCall(timeLock, abi.encodeCall(ITimeLock.cancelTransaction, (target1, 123, "signature", "data", eta)));

        vm.prank(vetoAdmin);
        governor.cancelBatch(txs);

        (address initiator,,) = governor.batchInfo(batchBlock);
        assertEq(initiator, address(0), "Batch not cleared after cancellation");

        (uint64 tx1BatchBlock,) = governor.batchedTxInfo(tx1Hash);
        assertEq(tx1BatchBlock, 0, "Tx 1 still batched");

        (uint64 tx2BatchBlock,) = governor.batchedTxInfo(tx2Hash);
        assertEq(tx2BatchBlock, 0, "Tx 2 still batched");

        assertFalse(ITimeLock(timeLock).queuedTransactions(tx1Hash), "Tx 1 still queued after cancellation");
        assertFalse(ITimeLock(timeLock).queuedTransactions(tx2Hash), "Tx 2 still queued after cancellation");

        vm.revertTo(snap);

        // execution

        vm.expectEmit(true, true, true, true);
        emit IGovernor.ExecuteBatch(address(this), batchBlock);

        vm.expectCall(timeLock, abi.encodeCall(ITimeLock.executeTransaction, (target0, 123, "signature", "data", eta)));
        vm.expectCall(timeLock, abi.encodeCall(ITimeLock.executeTransaction, (target1, 123, "signature", "data", eta)));

        governor.executeBatch{value: 456}(txs);

        (initiator,,) = governor.batchInfo(batchBlock);
        assertEq(initiator, address(0), "Batch not cleared after cancellation");

        (tx1BatchBlock,) = governor.batchedTxInfo(tx1Hash);
        assertEq(tx1BatchBlock, 0, "Tx 1 still batched");

        (tx2BatchBlock,) = governor.batchedTxInfo(tx2Hash);
        assertEq(tx2BatchBlock, 0, "Tx 2 still batched");

        assertFalse(ITimeLock(timeLock).queuedTransactions(tx1Hash), "Tx 1 still queued after execution");
        assertFalse(ITimeLock(timeLock).queuedTransactions(tx2Hash), "Tx 2 still queued after execution");
    }

    // ------------- //
    // CONFIGURATION //
    // ------------- //

    function test_GOV_16_addQueueAdmin_and_removeQueueAdmin_work_as_expected() public {
        address newQueueAdmin = makeAddr("newQueueAdmin");
        uint256 eta = block.timestamp + delay;

        vm.prank(owner);
        governor.queueTransaction(address(governor), 0, "addQueueAdmin(address)", abi.encode(newQueueAdmin), eta);

        vm.expectEmit(true, true, true, true);
        emit IGovernor.AddQueueAdmin(newQueueAdmin);

        vm.warp(eta);
        governor.executeTransaction(address(governor), 0, "addQueueAdmin(address)", abi.encode(newQueueAdmin), eta);

        assertEq(governor.queueAdmins(), _toDyn([queueAdmin, newQueueAdmin]), "Queue admins after adding");

        eta = block.timestamp + delay;

        vm.prank(owner);
        governor.queueTransaction(address(governor), 0, "removeQueueAdmin(address)", abi.encode(newQueueAdmin), eta);

        vm.expectEmit(true, true, true, true);
        emit IGovernor.RemoveQueueAdmin(newQueueAdmin);

        vm.warp(eta);
        governor.executeTransaction(address(governor), 0, "removeQueueAdmin(address)", abi.encode(newQueueAdmin), eta);

        assertEq(governor.queueAdmins(), _toDyn([queueAdmin]), "Queue admins after removing");
    }

    function test_GOV_16_addExecutionAdmin_and_removeExecutionAdmin_work_as_expected() public {
        address newExecutionAdmin = makeAddr("newExecutionAdmin");
        uint256 eta = block.timestamp + delay;

        vm.prank(owner);
        governor.queueTransaction(
            address(governor), 0, "addExecutionAdmin(address)", abi.encode(newExecutionAdmin), eta
        );

        vm.expectEmit(true, true, true, true);
        emit IGovernor.AddExecutionAdmin(newExecutionAdmin);

        vm.warp(eta);
        governor.executeTransaction(
            address(governor), 0, "addExecutionAdmin(address)", abi.encode(newExecutionAdmin), eta
        );

        assertEq(
            governor.executionAdmins(), _toDyn([executionAdmin, newExecutionAdmin]), "Execution admins after adding"
        );

        eta = block.timestamp + delay;

        vm.prank(owner);
        governor.queueTransaction(
            address(governor), 0, "removeExecutionAdmin(address)", abi.encode(newExecutionAdmin), eta
        );

        vm.expectEmit(true, true, true, true);
        emit IGovernor.RemoveExecutionAdmin(newExecutionAdmin);

        vm.warp(eta);
        governor.executeTransaction(
            address(governor), 0, "removeExecutionAdmin(address)", abi.encode(newExecutionAdmin), eta
        );

        assertEq(governor.executionAdmins(), _toDyn([executionAdmin]), "Execution admins after removing");
    }

    function test_GOV_18_updateVetoAdmin_works_as_expected() public {
        address newVetoAdmin = makeAddr("newVetoAdmin");
        uint256 eta = block.timestamp + delay;

        vm.prank(owner);
        governor.queueTransaction(address(governor), 0, "updateVetoAdmin(address)", abi.encode(newVetoAdmin), eta);

        vm.expectEmit(true, true, true, true);
        emit IGovernor.UpdateVetoAdmin(newVetoAdmin);

        vm.warp(eta);
        governor.executeTransaction(address(governor), 0, "updateVetoAdmin(address)", abi.encode(newVetoAdmin), eta);

        assertEq(governor.vetoAdmin(), newVetoAdmin, "Veto admin after update");
    }

    function test_GOV_19_allowPermissionlessExecution_and_forbidPermissionlessExecution_work_as_expected() public {
        uint256 eta = block.timestamp + delay;

        vm.startPrank(owner);
        governor.queueTransaction(target0, 0, "signature", "data", eta);
        governor.startBatch(uint80(eta));
        governor.queueTransaction(target1, 0, "signature", "data", eta);
        vm.stopPrank();

        IGovernor.TxParams[] memory txs = new IGovernor.TxParams[](1);
        txs[0] = IGovernor.TxParams(target1, 0, "signature", "data", eta);

        vm.expectEmit(true, true, true, true);
        emit IGovernor.ForbidPermissionlessExecution();

        vm.prank(timeLock);
        governor.forbidPermissionlessExecution();
        assertFalse(governor.isPermissionlessExecutionAllowed(), "Permissionless execution is allowed");

        vm.warp(eta);

        // can't be executed by non-execution admin
        vm.expectRevert(IGovernor.CallerNotExecutionAdminException.selector);
        vm.prank(queueAdmin);
        governor.executeTransaction(target0, 0, "signature", "data", eta);

        vm.expectRevert(IGovernor.CallerNotExecutionAdminException.selector);
        vm.prank(queueAdmin);
        governor.executeBatch(txs);

        // can be executed by execution admin or owner
        vm.prank(owner);
        governor.executeTransaction(target0, 0, "signature", "data", eta);

        vm.prank(executionAdmin);
        governor.executeBatch(txs);

        vm.expectEmit(true, true, true, true);
        emit IGovernor.AllowPermissionlessExecution();

        vm.prank(timeLock);
        governor.allowPermissionlessExecution();
        assertTrue(governor.isPermissionlessExecutionAllowed(), "Permissionless execution is forbidden");
    }

    // ----- //
    // UTILS //
    // ----- //

    function _toDyn(address[1] memory addrs) internal pure returns (address[] memory dynAddrs) {
        dynAddrs = new address[](1);
        dynAddrs[0] = addrs[0];
    }

    function _toDyn(address[2] memory addrs) internal pure returns (address[] memory dynAddrs) {
        dynAddrs = new address[](2);
        dynAddrs[0] = addrs[0];
        dynAddrs[1] = addrs[1];
    }

    function _toDyn(address[3] memory addrs) internal pure returns (address[] memory dynAddrs) {
        dynAddrs = new address[](3);
        dynAddrs[0] = addrs[0];
        dynAddrs[1] = addrs[1];
        dynAddrs[2] = addrs[2];
    }

    function _getTxHash(address target, uint256 value, string memory signature, bytes memory data, uint256 eta)
        internal
        pure
        returns (bytes32)
    {
        return keccak256(abi.encode(target, value, signature, data, eta));
    }
}
