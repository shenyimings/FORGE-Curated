// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.22;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "../interfaces/IRewardsPoolController.sol";
import "../interfaces/IWrappedLST.sol";
import "./RewardsPool.sol";

/**
 * @title RewardsPoolWSD
 * @notice Handles reward distribution for a single wrapped liquid staking token
 * @dev rewards can only be positive (user balances can only increase)
 */
contract RewardsPoolWSD is RewardsPool {
    using SafeERC20 for IERC677;

    IWrappedLST public wsdToken;

    constructor(
        address _controller,
        address _token,
        address _wsdToken
    ) RewardsPool(_controller, _token) {
        wsdToken = IWrappedLST(_wsdToken);
    }

    /**
     * @notice returns an account's total unwrapped withdrawable rewards (principal balance + newly earned rewards)
     * @param _account account address
     * @return account's total unclaimed rewards
     **/
    function withdrawableRewards(address _account) public view override returns (uint256) {
        return wsdToken.getUnderlyingByWrapped(super.withdrawableRewards(_account));
    }

    /**
     * @notice returns an account's total wrapped withdrawable rewards (principal balance + newly earned rewards)
     * @param _account account address
     * @return account's total unclaimed rewards
     **/
    function withdrawableRewardsWrapped(address _account) public view returns (uint256) {
        return super.withdrawableRewards(_account);
    }

    /**
     * @notice distributes new rewards that have been deposited
     **/
    function distributeRewards() public override {
        if (controller.totalStaked() == 0) revert NothingStaked();

        uint256 balance = token.balanceOf(address(this));
        token.transferAndCall(address(wsdToken), balance, "0x");

        uint256 toDistribute = wsdToken.balanceOf(address(this)) - totalRewards;
        totalRewards += toDistribute;
        _updateRewardPerToken(toDistribute);

        emit DistributeRewards(msg.sender, controller.totalStaked(), balance);
    }

    /**
     * @notice updates an account's principal reward balance
     * @param _account account address
     **/
    function updateReward(address _account) public override {
        uint256 newRewards = withdrawableRewardsWrapped(_account) - userRewards[_account];
        if (newRewards > 0) {
            userRewards[_account] += newRewards;
        }
        userRewardPerTokenPaid[_account] = rewardPerToken;
    }

    /**
     * @notice withdraws rewards for an account
     * @param _account account address
     **/
    function _withdraw(address _account) internal override {
        uint256 toWithdraw = withdrawableRewardsWrapped(_account);
        uint256 toWithdrawUnwrapped = wsdToken.getUnderlyingByWrapped(toWithdraw);

        if (toWithdraw > 0) {
            updateReward(_account);
            userRewards[_account] -= toWithdraw;
            totalRewards -= toWithdraw;

            wsdToken.unwrap(toWithdraw);
            token.safeTransfer(_account, toWithdrawUnwrapped);

            emit Withdraw(_account, toWithdrawUnwrapped);
        }
    }
}
