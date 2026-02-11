// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.22;

interface IPriorityPool {
    enum PoolStatus {
        OPEN,
        DRAINING,
        CLOSED
    }

    function paused() external view returns (bool);

    function depositsSinceLastUpdate() external view returns (uint256);

    function poolStatus() external view returns (PoolStatus);

    function ipfsHash() external view returns (bytes32);

    function canWithdraw(
        address _account,
        uint256 _distributionAmount
    ) external view returns (uint256);

    function getQueuedTokens(
        address _account,
        uint256 _distributionAmount
    ) external view returns (uint256);

    function getLSDTokens(
        address _account,
        uint256 _distributionShareAmount
    ) external view returns (uint256);

    function deposit(uint256 _amount, bool _shouldQueue, bytes[] calldata _data) external;

    function withdraw(
        uint256 _amountToWithdraw,
        uint256 _amount,
        uint256 _sharesAmount,
        bytes32[] calldata _merkleProof,
        bool _shouldUnqueue,
        bool _shouldQueueWithdrawal,
        bytes[] calldata _data
    ) external;

    function claimLSDTokens(
        uint256 _amount,
        uint256 _sharesAmount,
        bytes32[] calldata _merkleProof
    ) external;

    function pauseForUpdate() external;

    function setPoolStatus(PoolStatus _status) external;

    function updateDistribution(
        bytes32 _merkleRoot,
        bytes32 _ipfsHash,
        uint256 _amountDistributed,
        uint256 _sharesAmountDistributed
    ) external;

    function executeQueuedWithdrawals(uint256 _amount, bytes[] calldata _data) external;

    function checkUpkeep(bytes calldata) external view returns (bool, bytes memory);

    function performUpkeep(bytes calldata _performData) external;
}
