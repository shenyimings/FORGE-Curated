// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.22;

interface IL2Strategy {
    function handleIncomingTokensFromL1(uint256 _amount) external;

    function handleOutgoingTokensToL1(uint256 _amount) external;

    function tokensInTransitFromL1() external view returns (uint256);

    function getTotalQueuedTokens() external view returns (uint256);

    function handleUpdateFromL1(
        uint256 _totalDeposits,
        uint256 _tokensInTransitFromL1,
        uint256 _tokensReceivedAtL1,
        address[] calldata _opRewardReceivers,
        uint256[] calldata _opRewardAmounts
    ) external;
}
