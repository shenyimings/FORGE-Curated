// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.22;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import "../../interfaces/IERC677.sol";

interface IOwnersRewardsPool is IERC20 {
    function updateReward(address _account) external;

    function depositReward(uint256 _reward) external;

    function withdraw(address _account) external;

    function withdraw() external;
}

interface IPoolAllowance is IERC20 {
    function mintAllowance(address _account, uint256 _amount) external;

    function burnAllowance(address _account, uint256 _amount) external;
}

/**
 * @title Pool Owners
 * @dev Handles owners token staking, allowance token distribution, & owners rewards assets
 */
contract PoolOwnersV1 is ReentrancyGuard, Ownable {
    using SafeERC20 for IERC677;

    IERC677 public stakingToken;
    uint256 public totalStaked;
    mapping(address => uint256) private stakedBalances;

    uint16 public totalRewardTokens;
    mapping(uint16 => address) public rewardTokens;
    mapping(address => address) public rewardPools;
    mapping(address => address) public allowanceTokens;
    mapping(address => mapping(address => uint256)) private mintedAllowanceTokens;

    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardsWithdrawn(address indexed user);
    event AllowanceMinted(address indexed user);
    event RewardTokenAdded(address indexed token, address allowanceToken, address rewardsPool);
    event RewardTokenRemoved(address indexed token);

    constructor(address _stakingToken) {
        stakingToken = IERC677(_stakingToken);
    }

    modifier updateRewards(address _account) {
        for (uint16 i = 0; i < totalRewardTokens; i++) {
            IOwnersRewardsPool(rewardPools[rewardTokens[i]]).updateReward(_account);
        }
        _;
    }

    /**
     * @dev returns a user's staked balance
     * @param _account user to return balance for
     * @return user's staked balance
     **/
    function balanceOf(address _account) public view returns (uint256) {
        return stakedBalances[_account];
    }

    /**
     * @dev returns how many allowance tokens have been minted for a user
     * @param _allowanceToken allowance token to return minted amount for
     * @param _account user to return minted amount for
     * @return total allowance tokens a user has minted
     **/
    function mintedAllowance(
        address _allowanceToken,
        address _account
    ) public view returns (uint256) {
        return mintedAllowanceTokens[_allowanceToken][_account];
    }

    /**
     * @dev returns total amount staked
     * @return total amount staked
     **/
    function totalSupply() public view returns (uint256) {
        return totalStaked;
    }

    /**
     * @dev ERC677 implementation that proxies staking
     * @param _sender of the token transfer
     * @param _value of the token transfer
     **/
    function onTokenTransfer(
        address _sender,
        uint256 _value,
        bytes calldata
    ) external nonReentrant {
        require(msg.sender == address(stakingToken), "Sender must be staking token");
        _stake(_sender, _value);
    }

    /**
     * @dev stakes owners tokens & mints staking allowance tokens in return
     * @param _amount amount to stake
     **/
    function stake(uint256 _amount) external nonReentrant {
        stakingToken.safeTransferFrom(msg.sender, address(this), _amount);
        _stake(msg.sender, _amount);
    }

    /**
     * @dev burns staking allowance tokens and withdraws staked owners tokens
     * @param _amount amount to withdraw
     **/
    function withdraw(uint256 _amount) public nonReentrant updateRewards(msg.sender) {
        stakedBalances[msg.sender] = stakedBalances[msg.sender] - _amount;
        totalStaked -= _amount;
        _burnAllowance(msg.sender);
        stakingToken.safeTransfer(msg.sender, _amount);
        emit Withdrawn(msg.sender, _amount);
    }

    /**
     * @dev withdraws user's earned rewards for a all assets
     **/
    function withdrawAllRewards() public nonReentrant {
        for (uint16 i = 0; i < totalRewardTokens; i++) {
            _withdrawReward(rewardTokens[i], msg.sender);
        }
        emit RewardsWithdrawn(msg.sender);
    }

    /**
     * @dev withdraws users earned rewards for all assets and withdraws their owners tokens
     **/
    function exit() external {
        withdraw(balanceOf(msg.sender));
        withdrawAllRewards();
    }

    /**
     * @dev mints a user's unclaimed allowance tokens (used if a new asset is added
     * after a user has already staked)
     **/
    function mintAllowance() external nonReentrant {
        _mintAllowance(msg.sender);
        emit AllowanceMinted(msg.sender);
    }

    /**
     * @dev adds a new asset
     * @param _token asset to add
     * @param _allowanceToken asset pool allowance token to add
     * @param _rewardPool asset reward pool to add
     **/
    function addRewardToken(
        address _token,
        address _allowanceToken,
        address _rewardPool
    ) external onlyOwner {
        require(rewardPools[_token] == address(0), "Reward token already exists");
        rewardTokens[totalRewardTokens] = _token;
        allowanceTokens[_token] = _allowanceToken;
        rewardPools[_token] = _rewardPool;
        totalRewardTokens++;
        emit RewardTokenAdded(_token, _allowanceToken, _rewardPool);
    }

    /**
     * @dev removes an existing asset
     * @param _index index of asset to remove
     **/
    function removeRewardToken(uint16 _index) external onlyOwner {
        require(_index < totalRewardTokens, "Reward token does not exist");
        address token = rewardTokens[_index];
        if (totalRewardTokens > 1) {
            rewardTokens[_index] = rewardTokens[totalRewardTokens - 1];
        }
        delete rewardTokens[totalRewardTokens - 1];
        delete allowanceTokens[token];
        delete rewardPools[token];
        totalRewardTokens--;
        emit RewardTokenRemoved(token);
    }

    /**
     * @dev stakes owners tokens & mints staking allowance tokens in return
     * @param _amount amount to stake
     **/
    function _stake(address _sender, uint256 _amount) private updateRewards(_sender) {
        stakedBalances[_sender] = stakedBalances[_sender] + _amount;
        totalStaked += _amount;
        _mintAllowance(_sender);
        emit Staked(_sender, _amount);
    }

    /**
     * @dev withdraws rewards for a specific asset & account
     * @param _token asset to withdraw
     * @param _account user to withdraw for
     **/
    function _withdrawReward(address _token, address _account) private {
        require(rewardPools[_token] != address(0), "Reward token does not exist");
        IOwnersRewardsPool(rewardPools[_token]).withdraw(_account);
    }

    /**
     * @dev mints allowance tokens based on a user's staked balance
     * @param _account user to mint tokens for
     **/
    function _mintAllowance(address _account) private {
        uint256 stakedAmount = balanceOf(_account);
        for (uint16 i = 0; i < totalRewardTokens; i++) {
            address token = allowanceTokens[rewardTokens[i]];
            uint256 minted = mintedAllowance(token, _account);
            if (minted < stakedAmount) {
                IPoolAllowance(token).mintAllowance(_account, stakedAmount - minted);
                mintedAllowanceTokens[token][_account] = stakedAmount;
            }
        }
    }

    /**
     * @dev burns allowance tokens based on a user's staked balance
     * @param _account user to burn tokens for
     **/
    function _burnAllowance(address _account) private {
        uint256 stakedAmount = balanceOf(_account);
        for (uint16 i = 0; i < totalRewardTokens; i++) {
            address token = allowanceTokens[rewardTokens[i]];
            uint256 minted = mintedAllowance(token, _account);
            if (minted > stakedAmount) {
                IPoolAllowance(token).burnAllowance(_account, minted - stakedAmount);
                mintedAllowanceTokens[token][_account] = stakedAmount;
            }
        }
    }
}
