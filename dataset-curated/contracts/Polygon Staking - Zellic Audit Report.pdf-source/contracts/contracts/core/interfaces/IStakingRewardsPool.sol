// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.22;

import "./IERC677.sol";

interface IStakingRewardsPool is IERC677 {
    /**
     * @notice returns an account's share balance
     * @param _account account to return balance for
     * @return account's share balance
     **/
    function sharesOf(address _account) external view returns (uint256);

    /**
     * @notice returns the amount of shares that corresponds to a staked amount
     * @param _amount staked amount
     * @return amount of shares
     **/
    function getSharesByStake(uint256 _amount) external view returns (uint256);

    /**
     * @notice returns the amount of stake that corresponds to an amount of shares
     * @param _amount shares amount
     * @return amount of stake
     **/
    function getStakeByShares(uint256 _amount) external view returns (uint256);

    function totalShares() external view returns (uint256);

    function totalSupply() external view returns (uint256);

    function transferShares(address _recipient, uint256 _sharesAmount) external returns (bool);
}
