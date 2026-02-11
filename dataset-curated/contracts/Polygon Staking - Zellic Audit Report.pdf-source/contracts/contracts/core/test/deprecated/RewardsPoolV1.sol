// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.22;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

import "../../tokens/base/ERC677.sol";
import "../../interfaces/IERC677.sol";

/**
 * @title RewardsPool
 * @dev Handles rewards distribution of an asset based on a staking derivative token
 * that represents a user's staked balance
 */
contract RewardsPoolV1 is ERC677, ReentrancyGuard {
    using SafeERC20 for IERC677;

    IERC677 public stakingDerivative;
    IERC677 public rewardsToken;
    uint256 public rewardPerToken;

    mapping(address => uint256) public userRewardPerTokenPaid;

    event Withdrawn(address indexed user, uint256 amount);

    constructor(
        address _stakingDerivative,
        address _rewardsToken,
        string memory _tokenName,
        string memory _tokenSymbol
    ) ERC677(_tokenName, _tokenSymbol, 0) {
        rewardsToken = IERC677(_rewardsToken);
        stakingDerivative = IERC677(_stakingDerivative);
    }

    /**
     * @dev calculates a user's total unclaimed rewards (principal balance + newly earned rewards)
     * @param _account user to calculate rewards for
     * @return user's total unclaimed rewards
     **/
    function balanceOf(address _account) public view virtual override returns (uint256) {
        return
            (stakingDerivative.balanceOf(_account) *
                (rewardPerToken - userRewardPerTokenPaid[_account])) /
            1e18 +
            super.balanceOf(_account);
    }

    /**
     * @dev updates a user's principal reward balance
     * @param _account user to update for
     **/
    function updateReward(address _account) external nonReentrant {
        _updateReward(_account);
    }

    /**
     * @dev withdraws a user's earned rewards
     * @param _amount amount to withdraw
     **/
    function withdraw(uint256 _amount) public virtual nonReentrant {
        _withdraw(msg.sender, _amount);
        rewardsToken.safeTransfer(msg.sender, _amount);
    }

    /**
     * @dev updates rewardPerToken
     * @param _reward deposited reward amount
     **/
    function _updateRewardPerToken(uint256 _reward) internal {
        require(stakingDerivative.totalSupply() > 0, "Staked amount must be > 0");
        rewardPerToken = rewardPerToken + ((_reward * 1e18) / stakingDerivative.totalSupply());
    }

    /**
     * @dev updates a user's principal reward balance
     * @param _account user to update for
     **/
    function _updateReward(address _account) internal virtual {
        uint256 toMint = balanceOf(_account) - super.balanceOf(_account);
        if (toMint > 0) {
            _mint(_account, toMint);
        }
        userRewardPerTokenPaid[_account] = rewardPerToken;
    }

    /**
     * @dev performs accounting updates for a user withdrawal
     * @param _sender user to withdraw for
     * @param _amount amount to withdraw
     **/
    function _withdraw(address _sender, uint256 _amount) internal {
        _updateReward(_sender);
        _burn(_sender, _amount);
        emit Withdrawn(_sender, _amount);
    }

    /**
     * @dev transfers unclaimed rewards from one user to another
     * @param _from user to transfer from
     * @param _to user to transfer to
     * @param _amount amount to transfer
     **/
    function _transfer(address _from, address _to, uint256 _amount) internal virtual override {
        _updateReward(_from);
        super._transfer(_from, _to, _amount);
    }
}
