// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.22;

import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

import "../core/base/Strategy.sol";

/**
 * @title L2 Strategy
 * @notice Strategy that accepts deposits on L2 (Metis) and sends them to L1 (Ethereum) to be staked
 */
contract L2Strategy is Strategy {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    struct Fee {
        // address to receive fee
        address receiver;
        // value of fee in basis points
        uint256 basisPoints;
    }

    // address of L2 Transmitter
    address public l2Transmitter;

    // maximum amount of deposits this strategy can hold
    uint256 private maxDeposits;
    // list of fees to be paid on rewards
    Fee[] private fees;

    // total deposits across L2 and L1 strategies
    uint256 private totalDeposits;
    // total tokens queued for deposit onto L1
    uint256 private totalQueuedTokens;

    // total deposits in L1 Strategy
    uint256 public l1TotalDeposits;
    // total tokens in transit to L1
    uint256 public tokensInTransitToL1;
    // total tokens in transit from L1
    uint256 public tokensInTransitFromL1;

    // amount of operator rewards to mint on the next update
    uint256 private operatorRewardsToMint;
    // total amount of unclaimed operator reward shares
    uint256 private totalOperatorRewardShares;
    // maps address to unclaimed operator reward shares
    mapping(address => uint256) private operatorRewardShares;

    error FeesTooLarge();
    error SenderNotAuthorized();
    error InsufficientLiquidity();
    error ExceedsTokensInTransitFromL1();
    error NoRewards();

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initializes contract
     * @param _token address of METIS token
     * @param _stakingPool address of the staking pool that controls this strategy
     * @param _fees list of fees to be paid on rewards
     * @param _maxDeposits maximum amount of deposits this strategy can hold
     **/
    function initialize(
        address _token,
        address _stakingPool,
        Fee[] memory _fees,
        uint256 _maxDeposits
    ) public initializer {
        __Strategy_init(_token, _stakingPool);

        for (uint256 i = 0; i < _fees.length; ++i) {
            fees.push(_fees[i]);
        }
        if (_totalFeesBasisPoints() > 3000) revert FeesTooLarge();

        maxDeposits = _maxDeposits;
    }

    /**
     * @notice Reverts if sender is not L2 Transmitter
     **/
    modifier onlyL2Transmitter() {
        if (msg.sender != l2Transmitter) revert SenderNotAuthorized();
        _;
    }

    /**
     * @notice Deposits tokens into this strategy from the staking pool
     * @param _amount amount to deposit
     */
    function deposit(uint256 _amount, bytes calldata) external onlyStakingPool {
        token.safeTransferFrom(msg.sender, address(this), _amount);
        totalDeposits += _amount;
        totalQueuedTokens += _amount;
    }

    /**
     * @notice Withdraws tokens from this strategy to the staking pool
     * @param _amount amount to withdraw
     */
    function withdraw(uint256 _amount, bytes calldata) external onlyStakingPool {
        if (_amount > totalQueuedTokens) revert InsufficientLiquidity();

        token.safeTransfer(msg.sender, _amount);

        totalDeposits -= _amount;
        uint256 balance = token.balanceOf(address(this));
        if (totalQueuedTokens != balance) totalQueuedTokens = balance;
    }

    /**
     * @notice ERC677 implementation to receive operator rewards
     * @dev rewards are paid in the stakingPool LST
     **/
    function onTokenTransfer(address, uint256, bytes calldata) external {
        if (msg.sender != address(stakingPool)) revert SenderNotAuthorized();
    }

    /**
     * @notice Returns the total unclaimed operator rewards
     * @return unclaimed operator rewards
     */
    function getTotalOperatorRewards() external view returns (uint256) {
        return stakingPool.getStakeByShares(totalOperatorRewardShares);
    }

    /**
     * @notice Returns the unclaimed operator rewards for an account
     * @return unclaimed operator rewards
     */
    function getOperatorRewards(address _account) external view returns (uint256) {
        return stakingPool.getStakeByShares(operatorRewardShares[_account]);
    }

    /**
     * @notice Withdraws operator rewards for the sender
     */
    function withdrawOperatorRewards() external {
        uint256 rewardShares = operatorRewardShares[msg.sender];
        if (rewardShares == 0) revert NoRewards();

        totalOperatorRewardShares -= rewardShares;
        delete operatorRewardShares[msg.sender];

        stakingPool.transfer(msg.sender, stakingPool.getStakeByShares(rewardShares));
    }

    /**
     * @notice Returns the total amount of queued tokens
     * @return total queued tokens
     */
    function getTotalQueuedTokens() external view returns (uint256) {
        return totalQueuedTokens;
    }

    /**
     * @notice Returns the deposit change since deposits were last updated
     * @dev deposit change could be positive or negative depending on reward rate and whether
     * any slashing occurred
     * @return deposit change
     */
    function getDepositChange() public view returns (int) {
        return
            int256(
                l1TotalDeposits +
                    tokensInTransitToL1 +
                    tokensInTransitFromL1 +
                    token.balanceOf(address(this))
            ) - int256(totalDeposits);
    }

    /**
     * @notice Updates deposit accounting and calculates fees on newly earned rewards
     * @return depositChange change in deposits since last update
     * @return receivers list of fee receivers
     * @return amounts list of fee amounts
     */
    function updateDeposits(
        bytes calldata
    )
        external
        onlyStakingPool
        returns (int256 depositChange, address[] memory receivers, uint256[] memory amounts)
    {
        depositChange = getDepositChange();

        if (operatorRewardsToMint != 0) {
            receivers = new address[](1 + (depositChange > 0 ? fees.length : 0));
            amounts = new uint256[](receivers.length);
            receivers[0] = address(this);
            amounts[0] = operatorRewardsToMint;
            operatorRewardsToMint = 0;
        }

        if (depositChange > 0) {
            if (receivers.length == 0) {
                receivers = new address[](fees.length);
                amounts = new uint256[](receivers.length);

                for (uint256 i = 0; i < receivers.length; ++i) {
                    receivers[i] = fees[i].receiver;
                    amounts[i] = (uint256(depositChange) * fees[i].basisPoints) / 10000;
                }
            } else {
                for (uint256 i = 1; i < receivers.length; ++i) {
                    receivers[i] = fees[i - 1].receiver;
                    amounts[i] = (uint256(depositChange) * fees[i - 1].basisPoints) / 10000;
                }
            }
        }

        uint256 balance = token.balanceOf(address(this));

        totalDeposits = l1TotalDeposits + tokensInTransitToL1 + tokensInTransitFromL1 + balance;

        if (totalQueuedTokens != balance) totalQueuedTokens = balance;
    }

    /**
     * @notice Handles incoming update from L1
     * @param _totalDeposits total deposits currently in L1 Strategy
     * @param _tokensInTransitFromL1 amount of tokens sent from L1 since last update
     * @param _tokensReceivedAtL1 amount of tokens received at L1 since last update
     * @param _opRewardReceivers list of operator reward receiver addresses
     * @param _opRewardAmounts list of newly earned operator reward amounts corresponding to receivers
     */
    function handleUpdateFromL1(
        uint256 _totalDeposits,
        uint256 _tokensInTransitFromL1,
        uint256 _tokensReceivedAtL1,
        address[] calldata _opRewardReceivers,
        uint256[] calldata _opRewardAmounts
    ) external onlyL2Transmitter {
        l1TotalDeposits = _totalDeposits;
        tokensInTransitFromL1 += _tokensInTransitFromL1;
        tokensInTransitToL1 -= _tokensReceivedAtL1 >= tokensInTransitToL1
            ? tokensInTransitToL1
            : _tokensReceivedAtL1;

        uint256 totalRewards;
        for (uint256 i = 0; i < _opRewardReceivers.length; ++i) {
            totalRewards += _opRewardAmounts[i];
        }

        operatorRewardsToMint = totalRewards;
        _updateStrategyRewards();

        uint256 totalRewardShares;
        for (uint256 i = 0; i < _opRewardReceivers.length; ++i) {
            if (_opRewardAmounts[i] == 0) continue;
            uint256 rewardShares = stakingPool.getSharesByStake(_opRewardAmounts[i]);
            operatorRewardShares[_opRewardReceivers[i]] += rewardShares;
            totalRewardShares += rewardShares;
        }

        totalOperatorRewardShares += totalRewardShares;
    }

    /**
     * @notice Handles incoming tokens from L1
     * @param _amount amount received
     */
    function handleIncomingTokensFromL1(uint256 _amount) external onlyL2Transmitter {
        if (_amount > tokensInTransitFromL1) revert ExceedsTokensInTransitFromL1();
        tokensInTransitFromL1 -= _amount;
        totalQueuedTokens += _amount;
        token.safeTransferFrom(msg.sender, address(this), _amount);
    }

    /**
     * @notice Handles outgoing tokens to L1
     * @param _amount amount to send
     */
    function handleOutgoingTokensToL1(uint256 _amount) external onlyL2Transmitter {
        tokensInTransitToL1 += _amount;
        totalQueuedTokens -= _amount;
        token.safeTransfer(msg.sender, _amount);
    }

    /**
     * @notice Returns the total amount of deposits as tracked in this strategy
     * @return total deposits
     */
    function getTotalDeposits() public view override returns (uint256) {
        return totalDeposits;
    }

    /**
     * @notice Returns the maximum amount of deposits this strategy can hold
     * @return maximum deposits
     */
    function getMaxDeposits() public view override returns (uint256) {
        return maxDeposits;
    }

    /**
     * @notice Returns the minimum amount of deposits that must remain this strategy
     * @return minimum deposits
     */
    function getMinDeposits() public view virtual override returns (uint256) {
        return l1TotalDeposits + tokensInTransitToL1 + tokensInTransitFromL1;
    }

    /**
     * @notice Returns a list of all fees and fee receivers
     * @return list of fees
     */
    function getFees() external view returns (Fee[] memory) {
        return fees;
    }

    /**
     * @notice Adds a new fee
     * @dev L2Transmitter::executeUpdate should be called right before calling this function
     * @param _receiver receiver of fee
     * @param _feeBasisPoints fee in basis points
     **/
    function addFee(address _receiver, uint256 _feeBasisPoints) external onlyOwner {
        _updateStrategyRewards();
        fees.push(Fee(_receiver, _feeBasisPoints));
        if (_totalFeesBasisPoints() > 3000) revert FeesTooLarge();
    }

    /**
     * @notice Updates an existing fee
     * @dev L2Transmitter::executeUpdate should be called right before calling this function
     * @param _index index of fee
     * @param _receiver receiver of fee
     * @param _feeBasisPoints fee in basis points
     **/
    function updateFee(
        uint256 _index,
        address _receiver,
        uint256 _feeBasisPoints
    ) external onlyOwner {
        _updateStrategyRewards();

        if (_feeBasisPoints == 0) {
            fees[_index] = fees[fees.length - 1];
            fees.pop();
        } else {
            fees[_index].receiver = _receiver;
            fees[_index].basisPoints = _feeBasisPoints;
        }

        if (_totalFeesBasisPoints() > 3000) revert FeesTooLarge();
    }

    /**
     * @notice Sets the maximum amount of deposits this strategy can hold
     * @param _maxDeposits maximum deposits
     */
    function setMaxDeposits(uint256 _maxDeposits) external onlyOwner {
        maxDeposits = _maxDeposits;
    }

    /**
     * @notice Sets the address of the l2 transmitter
     * @param _l2Transmitter address of l2 transmitter
     */
    function setL2Transmitter(address _l2Transmitter) external onlyOwner {
        l2Transmitter = _l2Transmitter;
    }

    /**
     * @notice Updates rewards for all strategies controlled by the staking pool
     * @dev called before fees are changed to credit any past rewards at the old rate
     */
    function _updateStrategyRewards() private {
        address[] memory strategies = stakingPool.getStrategies();
        uint256[] memory strategyIdxs = new uint256[](strategies.length);
        for (uint256 i = 0; i < strategies.length; ++i) {
            strategyIdxs[i] = i;
        }
        stakingPool.updateStrategyRewards(strategyIdxs, "");
    }

    /**
     * @notice Returns the sum of all fees
     * @return sum of fees in basis points
     **/
    function _totalFeesBasisPoints() private view returns (uint256) {
        uint256 totalFees;
        for (uint i = 0; i < fees.length; ++i) {
            totalFees += fees[i].basisPoints;
        }
        return totalFees;
    }
}
