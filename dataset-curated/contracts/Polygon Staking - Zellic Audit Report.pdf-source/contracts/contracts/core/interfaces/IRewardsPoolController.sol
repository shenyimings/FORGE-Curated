// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.22;

interface IRewardsPoolController {
    /**
     * @notice returns an account's stake balance for use by reward pools
     * controlled by this contract
     * @return account's balance
     */
    function staked(address _account) external view returns (uint256);

    /**
     * @notice returns the total staked amount for use by reward pools
     * controlled by this contract
     * @return total staked amount
     */
    function totalStaked() external view returns (uint256);

    /**
     * @notice adds a new token
     * @param _token token to add
     * @param _rewardsPool token rewards pool to add
     **/
    function addToken(address _token, address _rewardsPool) external;

    function distributeTokens(address[] memory _tokens) external;

    function withdrawRewards(address[] memory _tokens) external;
}
