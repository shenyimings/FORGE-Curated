// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {IOutbox} from "@arbitrum/nitro-contracts/src/bridge/IOutbox.sol";
import {IBridge} from "@arbitrum/nitro-contracts/src/bridge/IBridge.sol";

contract ArbitrumOutputMock is IOutbox {
    mapping(bytes32 => bytes32) public roots;

    function initialize(IBridge _bridge) external {
        // initialize
    }

    function rollup() external view returns (address) {
        return address(0);
    }

    function bridge() external view returns (IBridge) {
        return IBridge(address(0));
    }

    function spent(uint256) external view returns (bytes32) {
        return bytes32(0);
    }

    function OUTBOX_VERSION() external view returns (uint128) {
        return 0;
    }

    function updateSendRoot(bytes32 sendRoot, bytes32 l2BlockHash) external {
        // update send root
        roots[sendRoot] = l2BlockHash;
    }

    function updateRollupAddress() external {
        // update rollup address
    }

    function executeTransaction(
        uint256 batchNum,
        bytes32[] memory proof,
        uint256 index,
        address l2Sender,
        address destAddr,
        uint256 l2Block,
        uint256 l1Block,
        uint256 l2Timestamp,
        uint256 amount,
        bytes memory calldataForL1
    ) external {
        // execute transaction
    }

    function isMaster() external view returns (bool) {
        return false;
    }

    function l2ToL1Sender() external view returns (address) {
        return address(0);
    }

    function l2ToL1Block() external view returns (uint256) {
        return 0;
    }

    function l2ToL1EthBlock() external view returns (uint256) {
        return 0;
    }

    function l2ToL1Timestamp() external view returns (uint256) {
        return 0;
    }

    function l2ToL1OutputId() external view returns (bytes32) {
        return bytes32(0);
    }

    function executeTransaction(
        bytes32[] calldata proof,
        uint256 index,
        address l2Sender,
        address to,
        uint256 l2Block,
        uint256 l1Block,
        uint256 l2Timestamp,
        uint256 value,
        bytes calldata data
    ) external {
        // execute transaction
    }

    function executeTransactionSimulation(
        uint256 index,
        address l2Sender,
        address to,
        uint256 l2Block,
        uint256 l1Block,
        uint256 l2Timestamp,
        uint256 value,
        bytes calldata data
    ) external {}

    function isSpent(uint256) external view returns (bool) {
        return false;
    }

    function calculateMerkleRoot(bytes32[] calldata proof, uint256 path, bytes32 item) external pure returns (bytes32) {
        return bytes32(0);
    }

    function postUpgradeInit() external {
        // post upgrade init
    }

    function calculateItemHash(
        address l2Sender,
        address to,
        uint256 l2Block,
        uint256 l1Block,
        uint256 l2Timestamp,
        uint256 value,
        bytes calldata data
    ) external pure returns (bytes32) {
        return bytes32(0);
    }
}
