// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.22;

import "@openzeppelin/contracts/security/Pausable.sol";

/**
 * @title Priority Pool
 * @notice Mocks contract for testing
 */
contract PriorityPoolMock is Pausable {
    bytes32 public merkleRoot;
    bytes32 public ipfsHash;
    uint256 public amountDistributed;
    uint256 public sharesAmountDistributed;

    uint256 public depositsSinceLastUpdate;

    bytes public lastPerformData;
    bool public upkeepNeeded;

    constructor(uint256 _depositsSinceLastUpdate) {
        depositsSinceLastUpdate = _depositsSinceLastUpdate;
    }

    function updateDistribution(
        bytes32 _merkleRoot,
        bytes32 _ipfsHash,
        uint256 _amountDistributed,
        uint256 _sharesAmountDistributed
    ) external {
        _unpause();

        amountDistributed = _amountDistributed;
        sharesAmountDistributed = _sharesAmountDistributed;
        merkleRoot = _merkleRoot;
        ipfsHash = _ipfsHash;
    }

    function checkUpkeep(bytes calldata) external view returns (bool, bytes memory) {
        return (upkeepNeeded, upkeepNeeded ? abi.encode(150 ether) : bytes(""));
    }

    function performUpkeep(bytes calldata _data) external {
        lastPerformData = _data;
    }

    function pauseForUpdate() external {
        _pause();
    }

    function setDepositsSinceLastUpdate(uint256 _depositsSinceLastUpdate) external {
        depositsSinceLastUpdate = _depositsSinceLastUpdate;
    }

    function setUpkeepNeeded(bool _upkeepNeeded) external {
        upkeepNeeded = _upkeepNeeded;
    }
}
