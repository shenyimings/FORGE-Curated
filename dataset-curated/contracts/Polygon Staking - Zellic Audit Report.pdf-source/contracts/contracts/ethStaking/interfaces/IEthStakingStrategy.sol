// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.22;

interface IEthStakingStrategy {
    function nwlWithdraw(address _receiver, uint256 _amount) external;

    function depositEther(
        uint256 _nwlTotalValidatorCount,
        uint256 _wlTotalValidatorCount,
        uint256[] calldata _wlOperatorIds,
        uint256[] calldata _wlValidatorCounts
    ) external;
}
