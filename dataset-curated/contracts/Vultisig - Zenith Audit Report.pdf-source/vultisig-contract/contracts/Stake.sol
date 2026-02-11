// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./interfaces/IERC1363Spender.sol";
import "./StakeSweeper.sol";

/**
 * @title Stake
 * @dev Contract for staking VULT tokens that distributes USDC rewards
 * Adapted from Sushiswap's Masterchef rewardDebt methodology
 * Users can deposit tokens in one transaction using approveAndCall
 * and claim their USDC rewards pro-rata to their stake.
 * Owner can withdraw unclaimed USDC and extra staking tokens.
 */
contract Stake is IERC1363Spender, ReentrancyGuard, Ownable {
    using SafeERC20 for IERC20;

    // ================= Events =================
    event Deposited(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardClaimed(address indexed user, uint256 amount);
    event ForceWithdrawn(address indexed user, uint256 amount);
    event RewardsUpdated(uint256 newAccRewardPerShare, uint256 rewardAmount);
    event OwnerWithdrawnRewards(uint256 amount);
    event OwnerWithdrawnExtraTokens(uint256 amount);
    event TokenSwept(address indexed token, uint256 amountIn, uint256 amountOut);
    event SweeperSet(address indexed sweeper);
    event Migrated(address indexed user, address indexed newContract, uint256 amount);
    event RewardDecayFactorSet(uint256 newFactor);
    event MinRewardUpdateDelaySet(uint256 newDelay);
    event Reinvested(address indexed user, uint256 rewardAmount, uint256 stakingTokensReceived);
    event MinOutPercentageSet(uint8 percentage);

    // ================= State Variables =================
    /// @notice User staking information
    struct UserInfo {
        uint256 amount; // How many tokens the user has staked
        uint256 rewardDebt; // Reward debt as per Masterchef logic
    }

    /// @notice Scaling factor for reward per share calculations
    uint128 constant REWARD_DECAY_FACTOR_SCALING = 1e26;

    /// @notice VULT token being staked
    IERC20 public immutable stakingToken;

    /// @notice USDC token for rewards
    IERC20 public immutable rewardToken;

    /// @notice Sweeper contract for sweeping tokens
    StakeSweeper public sweeper;

    /// @notice Accumulated reward tokens per share, scaled by REWARD_DECAY_FACTOR_SCALING
    uint256 public accRewardPerShare;

    /// @notice Last processed reward balance
    uint256 public lastRewardBalance;

    /// @notice Total tokens staked
    uint256 public totalStaked;

    /// @notice Last time rewards were updated
    uint256 public lastRewardUpdateTime;

    /// @notice Decay factor for releasing rewards (default is 10 = 10%)
    uint256 public rewardDecayFactor = 10;

    /// @notice Minimum time between reward updates in seconds (default is 1 day)
    uint256 public minRewardUpdateDelay = 1 days;

    /// @notice Mapping of user address to their staking info
    mapping(address => UserInfo) public userInfo;

    /**
     * @dev Constructor sets the staking and reward tokens
     * @param _stakingToken Address of the ERC20 token that can be staked (VULT)
     * @param _rewardToken Address of the ERC20 token used for rewards (USDC)
     */
    constructor(address _stakingToken, address _rewardToken) Ownable(msg.sender) {
        require(_stakingToken != address(0), "Stake: staking token is the zero address");
        require(_rewardToken != address(0), "Stake: reward token is the zero address");

        stakingToken = IERC20(_stakingToken);
        rewardToken = IERC20(_rewardToken);
    }

    /**
     * @dev Update reward variables with current token balances
     * Must be called before any deposit or withdrawal
     * Includes decay function to gradually release rewards
     */
    function updateRewards() public {
        _updateRewards();
    }

    /**
     * @dev Internal function to handle reward updates based on configured parameters
     * The owner can configure minRewardUpdateDelay and rewardDecayFactor to control behavior
     */
    function _updateRewards() internal {
        if (totalStaked == 0) {
            lastRewardUpdateTime = block.timestamp;
            return;
        }

        uint256 currentRewardBalance = rewardToken.balanceOf(address(this));
        bool timeDelayMet = (block.timestamp >= lastRewardUpdateTime + minRewardUpdateDelay);

        // If there are new rewards and enough time has passed (or delay is set to 0)
        if (currentRewardBalance > lastRewardBalance && (timeDelayMet || minRewardUpdateDelay == 0)) {
            uint256 totalNewRewards = currentRewardBalance - lastRewardBalance;

            // Apply decay factor (if decay factor is 1, all rewards are released)
            uint256 releasedRewards = rewardDecayFactor == 1 ? totalNewRewards : totalNewRewards / rewardDecayFactor;

            // Update accRewardPerShare based on released rewards
            // Scaled by REWARD_DECAY_FACTOR_SCALING to avoid precision loss when dividing small numbers
            accRewardPerShare += (releasedRewards * REWARD_DECAY_FACTOR_SCALING) / totalStaked;

            // Update the last reward balance - only account for released rewards
            lastRewardBalance += releasedRewards;

            // Update the last update time
            lastRewardUpdateTime = block.timestamp;

            emit RewardsUpdated(accRewardPerShare, releasedRewards);
        }
    }

    /**
     * @dev Returns pending rewards for a user
     * @param _user Address of the user
     * @return Pending reward amount
     */
    function pendingRewards(address _user) public view returns (uint256) {
        UserInfo storage user = userInfo[_user];
        if (user.amount == 0 || totalStaked == 0) {
            return 0;
        }

        uint256 currentRewardBalance = rewardToken.balanceOf(address(this));
        uint256 additionalRewards = 0;
        uint256 newAccRewardPerShare = accRewardPerShare;

        // Check if there are additional rewards
        if (currentRewardBalance > lastRewardBalance && totalStaked > 0) {
            uint256 totalNewRewards = currentRewardBalance - lastRewardBalance;

            // Apply decay and time check based on configured parameters
            if (block.timestamp >= lastRewardUpdateTime + minRewardUpdateDelay || minRewardUpdateDelay == 0) {
                // Apply decay - only consider a fraction of the new rewards unless decay factor is 1
                additionalRewards = rewardDecayFactor == 1 ? totalNewRewards : totalNewRewards / rewardDecayFactor;
            }

            if (additionalRewards > 0) {
                newAccRewardPerShare += (additionalRewards * REWARD_DECAY_FACTOR_SCALING) / totalStaked;
            }
        }

        // Calculate pending rewards using the formula:
        return (user.amount * newAccRewardPerShare) / REWARD_DECAY_FACTOR_SCALING - user.rewardDebt;
    }

    /**
     * @dev Internal function to handle deposits, used by both normal deposits and approveAndCall
     * @param _depositor Address transferring the tokens (may be different from _user in some cases)
     * @param _user Address to attribute the deposit to
     * @param _amount Amount of tokens to deposit
     */
    function _deposit(address _depositor, address _user, uint256 _amount) internal {
        // Update reward variables
        updateRewards();

        // Get user info
        UserInfo storage user = userInfo[_user];

        // Transfer tokens from the depositor to this contract
        stakingToken.safeTransferFrom(_depositor, address(this), _amount);

        // Update user staking amount
        user.amount += _amount;
        totalStaked += _amount;

        // Update user reward debt
        user.rewardDebt = (user.amount * accRewardPerShare) / REWARD_DECAY_FACTOR_SCALING;

        emit Deposited(_user, _amount);
    }

    /**
     * @dev Allows an approved sender to deposit tokens on behalf of another user
     * This is particularly useful for migration between staking contracts
     * Sender must approve tokens first
     * @param _user Address of the user to attribute the deposit to
     * @param _amount Amount of tokens to deposit
     * @return Amount of tokens deposited
     */
    function depositForUser(address _user, uint256 _amount) public nonReentrant returns (uint256) {
        require(_amount > 0, "Stake: amount must be greater than 0");
        require(_user != address(0), "Stake: user is the zero address");

        _deposit(msg.sender, _user, _amount);
        return _amount;
    }

    /**
     * @dev Allows a user to deposit tokens without using approveAndCall
     * User must approve tokens first
     * @param amount Amount of tokens to deposit
     * @return Amount of tokens deposited
     */
    function deposit(uint256 amount) external returns (uint256) {
        // Simply call depositForUser with msg.sender as the user
        return depositForUser(msg.sender, amount);
    }

    /**
     * @dev Claims USDC rewards for the caller
     * @return Amount of rewards claimed
     */
    function claim() public nonReentrant returns (uint256) {
        return _claim(msg.sender);
    }

    /**
     * @dev Internal function for claiming rewards
     * This is used by functions that already have nonReentrant modifier
     * @param _recipient Address to receive the claimed rewards
     * @return Amount of rewards claimed
     */
    function _claim(address _recipient) internal returns (uint256) {
        // Update rewards first to ensure all pending rewards are accounted for
        updateRewards();

        // Claim rewards internally and get the amount
        uint256 rewardAmount = _claimRewards(msg.sender);

        if (rewardAmount > 0) {
            // Transfer the tokens to the recipient
            rewardToken.safeTransfer(_recipient, rewardAmount);
            emit RewardClaimed(msg.sender, rewardAmount);
        }

        return rewardAmount;
    }

    /**
     * @dev Internal function to handle token withdrawals
     * @param _user Address of the user withdrawing tokens
     * @param _amount Amount of tokens to withdraw
     * @param _shouldClaimRewards Whether to claim rewards before withdrawing
     */
    function _withdraw(address _user, uint256 _amount, bool _shouldClaimRewards) internal {
        UserInfo storage user = userInfo[_user];
        require(user.amount >= _amount, "Stake: insufficient balance");

        // Claim rewards if requested
        if (_shouldClaimRewards) {
            _claim(_user);
        } else {
            // If not claiming rewards, still update reward variables
            updateRewards();
        }

        // Update user staking amount
        user.amount -= _amount;
        totalStaked -= _amount;

        // Update reward debt
        user.rewardDebt = (user.amount * accRewardPerShare) / REWARD_DECAY_FACTOR_SCALING;

        // Transfer staking tokens back to the user
        stakingToken.safeTransfer(_user, _amount);
    }

    /**
     * @dev Allows a user to withdraw their staked tokens after claiming rewards
     * @param amount Amount of tokens to withdraw
     */
    function withdraw(uint256 amount) external nonReentrant {
        require(amount > 0, "Stake: amount must be greater than 0");

        _withdraw(msg.sender, amount, true);
        emit Withdrawn(msg.sender, amount);
    }

    /**
     * @dev Emergency withdraw without claiming rewards
     * @param amount Amount of tokens to withdraw
     */
    function forceWithdraw(uint256 amount) external nonReentrant {
        require(amount > 0, "Stake: amount must be greater than 0");

        _withdraw(msg.sender, amount, false);
        emit ForceWithdrawn(msg.sender, amount);
    }

    /**
     * @dev Implementation of IERC1363Spender onApprovalReceived to handle approveAndCall
     * This function is called when a user calls approveAndCall on the token contract
     * @param owner The address which called approveAndCall function and approved the tokens
     * @param value The amount of tokens to be spent
     * @return bytes4 The function selector to confirm the transaction is accepted
     */
    function onApprovalReceived(address owner, uint256 value, bytes calldata /* data */ )
        external
        override
        returns (bytes4)
    {
        require(msg.sender == address(stakingToken), "Stake: caller is not the staking token");
        require(value > 0, "Stake: amount must be greater than 0");

        _deposit(owner, owner, value);

        // Return the function selector to confirm transaction was accepted
        return IERC1363Spender.onApprovalReceived.selector;
    }

    /**
     * @dev Migrates user's entire stake to a new staking contract
     * This function will:
     * 1. Claim all pending rewards first
     * 2. Withdraw all staked tokens
     * 3. Approve the new staking contract to spend the tokens
     * 4. Use depositForUser in the new contract to deposit on behalf of the user
     * All in a single transaction
     * @param _newStakingContract Address of the new Stake contract to migrate to
     * @return migratedAmount Amount of tokens migrated to the new contract
     */
    function migrate(address _newStakingContract) external nonReentrant returns (uint256) {
        require(_newStakingContract != address(0), "Stake: new contract is the zero address");
        require(_newStakingContract != address(this), "Stake: cannot migrate to self");

        address userAddress = msg.sender;

        // Ensure the target is a valid Stake contract with the same staking token
        Stake newStakingContract = Stake(_newStakingContract);
        require(
            address(newStakingContract.stakingToken()) == address(stakingToken), "Stake: incompatible staking token"
        );

        // Get user's current staked amount
        UserInfo storage user = userInfo[userAddress];
        uint256 stakedAmount = user.amount;
        require(stakedAmount > 0, "Stake: no tokens to migrate");

        // 1. Claim all pending rewards
        _claim(userAddress);

        // 2. Withdraw all staked tokens
        // Update user staking amount
        user.amount = 0;
        totalStaked -= stakedAmount;

        // Update reward debt
        user.rewardDebt = 0;

        // 3. Approve the new contract to spend our tokens (staking tokens are now in this contract)
        stakingToken.approve(_newStakingContract, stakedAmount);

        // 4. Call depositForUser on the new contract to deposit directly with proper attribution
        bool migrationSuccess = false;
        try newStakingContract.depositForUser(userAddress, stakedAmount) {
            migrationSuccess = true;
        } catch {
            // If the depositForUser call fails, we need to transfer tokens back to the user
            migrationSuccess = false;
        }

        if (!migrationSuccess) {
            // If migration failed, return tokens to the user's wallet
            stakingToken.safeTransfer(userAddress, stakedAmount);
        }

        // Clear the approval regardless of outcome
        stakingToken.approve(_newStakingContract, 0);

        // Emit events for withdrawal and migration
        emit Withdrawn(userAddress, stakedAmount);
        emit Migrated(userAddress, _newStakingContract, stakedAmount);

        return stakedAmount;
    }

    /**
     * @dev Sets the sweeper contract
     * @param _sweeper The address of the sweeper contract to use
     */
    function setSweeper(address _sweeper) external onlyOwner {
        require(_sweeper != address(0), "Stake: sweeper is the zero address");
        sweeper = StakeSweeper(_sweeper);
        emit SweeperSet(_sweeper);
    }

    /**
     * @dev Sets the reward decay factor - determines what fraction of new rewards are released
     * e.g. factor of 10 means 1/10 (10%) of rewards are released each update
     * Setting factor to 1 releases all rewards at once (no decay)
     * @param _newFactor The new decay factor (must be at least 1)
     */
    function setRewardDecayFactor(uint256 _newFactor) external onlyOwner {
        require(_newFactor > 0, "Stake: decay factor must be greater than 0");
        rewardDecayFactor = _newFactor;
        emit RewardDecayFactorSet(_newFactor);
    }

    /**
     * @dev Sets the minimum time between reward updates
     * Setting to 0 means rewards can be updated at any time
     * @param _newDelay The new minimum delay in seconds
     */
    function setMinRewardUpdateDelay(uint256 _newDelay) external onlyOwner {
        minRewardUpdateDelay = _newDelay;
        emit MinRewardUpdateDelaySet(_newDelay);
    }

    /**
     * @dev Returns the staked amount for a user
     * @param _user Address of the user
     * @return The amount of tokens staked
     */
    function userAmount(address _user) external view returns (uint256) {
        return userInfo[_user].amount;
    }

    /**
     * @dev Sweeps a token from the contract and swaps it into the reward token using the sweeper contract
     * @param _token Address of the token to sweep (can't be staking or reward token)
     * @return The amount of reward tokens received from the swap
     */
    function sweep(address _token) external nonReentrant returns (uint256) {
        require(address(sweeper) != address(0), "Stake: sweeper not set");
        require(_token != address(stakingToken), "Stake: cannot sweep staking token");
        require(_token != address(rewardToken), "Stake: cannot sweep reward token");

        // Get the token balance
        IERC20 token = IERC20(_token);
        uint256 balance = token.balanceOf(address(this));
        require(balance > 0, "Stake: no tokens to sweep");

        // Transfer the token to the sweeper
        token.safeTransfer(address(sweeper), balance);

        // Execute the swap using our internal swap function
        uint256 amountOut = sweeper.sweep(_token, address(this));

        // Update the lastRewardBalance to account for the new rewards
        updateRewards();

        // Emit the sweep event
        emit TokenSwept(_token, balance, amountOut);

        return amountOut;
    }

    /**
     * @dev Reinvests a user's rewards back into their stake
     * 1. Claims rewards to this contract
     * 2. Swaps reward tokens for staking tokens using Uniswap
     * 3. Adds the new staking tokens to the user's stake
     * @return stakingTokensReceived The amount of staking tokens received and reinvested
     */
    function reinvest() external nonReentrant returns (uint256) {
        require(address(sweeper) != address(0), "Stake: sweeper not set");

        address userAddress = msg.sender;

        // Step 1: Update rewards to ensure all pending rewards are accounted for
        updateRewards();

        // Step 2: Check if user has pending rewards to reinvest
        UserInfo storage user = userInfo[userAddress];
        uint256 pending = (user.amount * accRewardPerShare) / REWARD_DECAY_FACTOR_SCALING - user.rewardDebt;
        require(pending > 0, "Stake: no rewards to reinvest");

        // Step 3: Claim rewards internally
        uint256 rewardAmount = _claimRewards(userAddress);

        // Emit RewardClaimed event
        emit RewardClaimed(userAddress, rewardAmount);

        // Transfer reward token to sweeper
        rewardToken.safeTransfer(address(sweeper), rewardAmount);

        // Check staking token balance before reinvest
        uint256 stakingTokenBalanceBefore = stakingToken.balanceOf(address(this));

        // Execute swap from reward tokens to staking tokens
        sweeper.reinvest(address(stakingToken), address(this));

        // Check staking token balance after reinvest
        uint256 stakingTokenBalanceAfter = stakingToken.balanceOf(address(this));

        uint256 stakingTokenBalanceDelta = stakingTokenBalanceAfter - stakingTokenBalanceBefore;

        require(stakingTokenBalanceDelta > 0, "Stake: swap did not yield any staking tokens");

        // Step 4: Re-use deposit logic to add tokens to user's stake
        // No need to transfer tokens as they're already in this contract

        // Update user staking amount
        user.amount += stakingTokenBalanceDelta;
        totalStaked += stakingTokenBalanceDelta;

        // Update user reward debt
        user.rewardDebt = (user.amount * accRewardPerShare) / REWARD_DECAY_FACTOR_SCALING;

        emit Deposited(userAddress, stakingTokenBalanceDelta);
        emit Reinvested(userAddress, rewardAmount, stakingTokenBalanceDelta);

        return stakingTokenBalanceDelta;
    }

    /**
     * @dev Internal function to claim rewards for a user
     * @param _user Address of the user claiming rewards
     * @return rewardAmount Amount of rewards claimed
     */
    function _claimRewards(address _user) internal returns (uint256) {
        UserInfo storage user = userInfo[_user];
        uint256 pending = (user.amount * accRewardPerShare) / REWARD_DECAY_FACTOR_SCALING - user.rewardDebt;

        if (pending == 0) {
            return 0;
        }

        // Check if we have enough reward token balance
        uint256 currentRewardBalance = rewardToken.balanceOf(address(this));
        uint256 rewardAmount = pending > currentRewardBalance ? currentRewardBalance : pending;

        // Important: Update lastRewardBalance to track that these tokens are being claimed
        lastRewardBalance -= rewardAmount;

        // Update reward debt to reflect that rewards have been claimed
        user.rewardDebt = (user.amount * accRewardPerShare) / REWARD_DECAY_FACTOR_SCALING;

        return rewardAmount;
    }
}
