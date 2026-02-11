// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.22;

import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

import "./base/StakingRewardsPool.sol";
import "./interfaces/IStrategy.sol";

/**
 * @title Staking Pool
 * @notice Allows users to stake asset tokens and receive liquid staking tokens 1:1, then deposits staked
 * asset tokens into strategy contracts
 */
contract StakingPool is StakingRewardsPool {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    struct Fee {
        // address to receive fee
        address receiver;
        // value of fee in basis points
        uint256 basisPoints;
    }

    // list of all strategies controlled by pool
    address[] private strategies;
    // total number of tokens staked in the pool
    uint256 public totalStaked;
    // max number of tokens that can sit in the pool outside of a strategy
    uint256 public unusedDepositLimit;

    // list of fees that are paid on rewards
    Fee[] private fees;

    // address of priority pool
    address public priorityPool;
    // address of rebase controller
    address public rebaseController;
    uint16 private poolIndex; // deprecated

    event UpdateStrategyRewards(
        address indexed account,
        uint256 totalStaked,
        int rewardsAmount,
        uint256 totalFees
    );
    event Burn(address indexed account, uint256 amount);
    event DonateTokens(address indexed sender, uint256 amount);

    error SenderNotAuthorized();
    error InvalidDeposit();
    error NothingStaked();

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initializes the contract
     * @param _token address of asset token
     * @param _liquidTokenName name of liquid staking token
     * @param _liquidTokenSymbol symbol of liquid staking token
     * @param _fees list of fees that are paid on rewards
     * @param _unusedDepositLimit max number of tokens that can sit in the pool outside of a strategy
     */
    function initialize(
        address _token,
        string memory _liquidTokenName,
        string memory _liquidTokenSymbol,
        Fee[] memory _fees,
        uint256 _unusedDepositLimit
    ) public initializer {
        __StakingRewardsPool_init(_token, _liquidTokenName, _liquidTokenSymbol);
        for (uint256 i = 0; i < _fees.length; i++) {
            fees.push(_fees[i]);
        }
        require(_totalFeesBasisPoints() <= 4000, "Total fees must be <= 40%");
        unusedDepositLimit = _unusedDepositLimit;
    }

    /**
     * @notice Reverts if sender is not priority pool
     */
    modifier onlyPriorityPool() {
        if (msg.sender != priorityPool) revert SenderNotAuthorized();
        _;
    }

    /**
     * @notice Returns a list of all strategies
     * @return list of strategies
     */
    function getStrategies() external view returns (address[] memory) {
        return strategies;
    }

    /**
     * @notice Returns a list of all fees
     * @return list of fees
     */
    function getFees() external view returns (Fee[] memory) {
        return fees;
    }

    /**
     * @notice Stakes asset tokens and mints liquid staking tokens
     * @dev will deposit unused deposits and new deposits into strategies
     * @param _account account to stake for
     * @param _amount amount to stake
     * @param _data list of deposit data passed to strategies
     **/
    function deposit(
        address _account,
        uint256 _amount,
        bytes[] calldata _data
    ) external onlyPriorityPool {
        require(strategies.length > 0, "Must be > 0 strategies to stake");

        uint256 startingBalance = token.balanceOf(address(this));

        if (_amount > 0) {
            token.safeTransferFrom(msg.sender, address(this), _amount);
            _depositLiquidity(_data);
            _mint(_account, _amount);
            totalStaked += _amount;
        } else {
            _depositLiquidity(_data);
        }

        uint256 endingBalance = token.balanceOf(address(this));
        if (endingBalance > startingBalance && endingBalance > unusedDepositLimit)
            revert InvalidDeposit();
    }

    /**
     * @notice Withdraws asset tokens and burns liquid staking tokens
     * @dev will withdraw from strategies if not enough liquidity
     * @param _account account to withdraw for
     * @param _receiver address to receive withdrawal
     * @param _amount amount to withdraw
     * @param _data list of withdrawal data passed to strategies
     **/
    function withdraw(
        address _account,
        address _receiver,
        uint256 _amount,
        bytes[] calldata _data
    ) external onlyPriorityPool {
        uint256 toWithdraw = _amount;
        if (_amount == type(uint256).max) {
            toWithdraw = balanceOf(_account);
        }

        uint256 balance = token.balanceOf(address(this));
        if (toWithdraw > balance) {
            _withdrawLiquidity(toWithdraw - balance, _data);
        }
        require(
            token.balanceOf(address(this)) >= toWithdraw,
            "Not enough liquidity available to withdraw"
        );

        _burn(_account, toWithdraw);
        totalStaked -= toWithdraw;
        token.safeTransfer(_receiver, toWithdraw);
    }

    /**
     * @notice Manually deposits asset tokens into a specific strategy
     * @param _index index of strategy
     * @param _amount amount to deposit
     * @param _data deposit data passed to strategy
     **/
    function strategyDeposit(
        uint256 _index,
        uint256 _amount,
        bytes calldata _data
    ) external onlyOwner {
        require(_index < strategies.length, "Strategy does not exist");
        IStrategy(strategies[_index]).deposit(_amount, _data);
    }

    /**
     * @notice Manually withdraws asset tokens from a strategy
     * @param _index index of strategy
     * @param _amount amount to withdraw
     * @param _data withdrawal data passed to strategy
     **/
    function strategyWithdraw(
        uint256 _index,
        uint256 _amount,
        bytes calldata _data
    ) external onlyOwner {
        require(_index < strategies.length, "Strategy does not exist");
        IStrategy(strategies[_index]).withdraw(_amount, _data);
    }

    /**
     * @notice Returns the maximum amount of tokens that the pool can hold
     * @return maximum deposit limit
     **/
    function getMaxDeposits() public view returns (uint256) {
        uint256 max;
        for (uint256 i = 0; i < strategies.length; i++) {
            uint strategyMax = IStrategy(strategies[i]).getMaxDeposits();
            if (strategyMax >= type(uint256).max - max) {
                return type(uint256).max;
            }
            max += strategyMax;
        }
        return max;
    }

    /**
     * @notice Returns the minimum amount of tokens that must remain in the pool
     * @return minimum deposit limit
     */
    function getMinDeposits() public view returns (uint256) {
        uint256 min;

        for (uint256 i = 0; i < strategies.length; i++) {
            IStrategy strategy = IStrategy(strategies[i]);
            min += strategy.getMinDeposits();
        }

        return min;
    }

    /**
     * @notice Returns the amount of unused asset tokens sitting in this pool outside a strategy
     * @dev these tokens earn no yield and will be deposited ASAP on the next call to _depositLiquidity
     * @return amount of unused tokens
     */
    function getUnusedDeposits() external view returns (uint256) {
        return token.balanceOf(address(this));
    }

    /**
     * @notice Returns the sum of available deposit room across all strategies
     * @dev does not account for unused deposits sitting in pool
     * @return strategy deposit room
     */
    function getStrategyDepositRoom() external view returns (uint256) {
        uint256 depositRoom;
        for (uint256 i = 0; i < strategies.length; ++i) {
            uint strategyDepositRoom = IStrategy(strategies[i]).canDeposit();
            if (strategyDepositRoom >= type(uint256).max - depositRoom) {
                return type(uint256).max;
            }
            depositRoom += strategyDepositRoom;
        }
        return depositRoom;
    }

    /**
     * @notice Returns the total available deposit room for this pool
     * @dev accounts for unused deposits sitting in pool
     * @return available deposit room
     */
    function canDeposit() external view returns (uint256) {
        uint256 max = getMaxDeposits();

        if (max <= totalStaked) {
            return 0;
        } else {
            return max - totalStaked;
        }
    }

    /**
     * @notice Returns the total available withdrawal room for this pool
     * @return available withdrawal room
     */
    function canWithdraw() external view returns (uint256) {
        uint256 min = getMinDeposits();

        if (min >= totalStaked) {
            return 0;
        } else {
            return totalStaked - min;
        }
    }

    /**
     * @notice Adds a new strategy
     * @param _strategy address of strategy
     **/
    function addStrategy(address _strategy) external onlyOwner {
        require(!_strategyExists(_strategy), "Strategy already exists");
        token.safeApprove(_strategy, type(uint256).max);
        strategies.push(_strategy);
    }

    /**
     * @notice Removes an existing strategy
     * @param _index index of strategy
     * @param _strategyUpdateData update data passed to strategy
     * @param _strategyWithdrawalData withdrawal data passed to strategy
     **/
    function removeStrategy(
        uint256 _index,
        bytes memory _strategyUpdateData,
        bytes calldata _strategyWithdrawalData
    ) external onlyOwner {
        require(_index < strategies.length, "Strategy does not exist");

        uint256[] memory idxs = new uint256[](1);
        idxs[0] = _index;
        _updateStrategyRewards(idxs, _strategyUpdateData);

        IStrategy strategy = IStrategy(strategies[_index]);
        uint256 totalStrategyDeposits = strategy.getTotalDeposits();
        if (totalStrategyDeposits > 0) {
            strategy.withdraw(totalStrategyDeposits, _strategyWithdrawalData);
        }

        for (uint256 i = _index; i < strategies.length - 1; i++) {
            strategies[i] = strategies[i + 1];
        }
        strategies.pop();
        token.safeApprove(address(strategy), 0);
    }

    /**
     * @notice Reorders strategies
     * @param _newOrder list containing strategy indexes in a new order
     **/
    function reorderStrategies(uint256[] calldata _newOrder) external onlyOwner {
        require(_newOrder.length == strategies.length, "newOrder.length must = strategies.length");

        address[] memory strategyAddresses = new address[](strategies.length);
        for (uint256 i = 0; i < strategies.length; i++) {
            strategyAddresses[i] = strategies[i];
        }

        for (uint256 i = 0; i < strategies.length; i++) {
            require(strategyAddresses[_newOrder[i]] != address(0), "all indices must be valid");
            strategies[i] = strategyAddresses[_newOrder[i]];
            strategyAddresses[_newOrder[i]] = address(0);
        }
    }

    /*
     * @notice Adds a new fee
     * @param _receiver receiver of fee
     * @param _feeBasisPoints fee in basis points
     **/
    function addFee(address _receiver, uint256 _feeBasisPoints) external onlyOwner {
        uint256[] memory strategyIdxs = new uint256[](strategies.length);
        for (uint256 i = 0; i < strategyIdxs.length; ++i) {
            strategyIdxs[i] = i;
        }
        _updateStrategyRewards(strategyIdxs, "");

        fees.push(Fee(_receiver, _feeBasisPoints));
        require(_totalFeesBasisPoints() <= 4000, "Total fees must be <= 40%");
    }

    /**
     * @notice Updates an existing fee
     * @param _index index of fee
     * @param _receiver receiver of fee
     * @param _feeBasisPoints fee in basis points
     **/
    function updateFee(
        uint256 _index,
        address _receiver,
        uint256 _feeBasisPoints
    ) external onlyOwner {
        require(_index < fees.length, "Fee does not exist");

        uint256[] memory strategyIdxs = new uint256[](strategies.length);
        for (uint256 i = 0; i < strategyIdxs.length; ++i) {
            strategyIdxs[i] = i;
        }
        _updateStrategyRewards(strategyIdxs, "");

        if (_feeBasisPoints == 0) {
            fees[_index] = fees[fees.length - 1];
            fees.pop();
        } else {
            fees[_index].receiver = _receiver;
            fees[_index].basisPoints = _feeBasisPoints;
        }

        require(_totalFeesBasisPoints() <= 4000, "Total fees must be <= 40%");
    }

    /**
     * @notice Returns the amount of rewards earned since the last call to updateStrategyRewards
     * @param _strategyIdxs indexes of strategies to sum rewards for
     * @return total rewards
     **/
    function getStrategyRewards(uint256[] calldata _strategyIdxs) external view returns (int256) {
        int256 totalRewards;

        for (uint256 i = 0; i < _strategyIdxs.length; i++) {
            IStrategy strategy = IStrategy(strategies[_strategyIdxs[i]]);
            totalRewards += strategy.getDepositChange();
        }

        return totalRewards;
    }

    /**
     * @notice Distributes rewards/fees based on balance changes in strategies since the last update
     * @param _strategyIdxs indexes of strategies to update rewards for
     * @param _data update data passed to each strategy
     **/
    function updateStrategyRewards(uint256[] memory _strategyIdxs, bytes memory _data) external {
        if (msg.sender != rebaseController && !_strategyExists(msg.sender))
            revert SenderNotAuthorized();
        _updateStrategyRewards(_strategyIdxs, _data);
    }

    /**
     * @notice Burns the senders liquid staking tokens, effectively donating their underlying stake to the pool
     * @param _amount amount to burn
     **/
    function burn(uint256 _amount) external {
        _burn(msg.sender, _amount);
        emit Burn(msg.sender, _amount);
    }

    /**
     * @notice Deposits asset tokens into the pool without minting liquid staking tokens,
     * effectively donating them to the pool
     * @param _amount amount to deposit
     **/
    function donateTokens(uint256 _amount) external {
        if (totalStaked == 0) revert NothingStaked();
        token.safeTransferFrom(msg.sender, address(this), _amount);
        totalStaked += _amount;
        emit DonateTokens(msg.sender, _amount);
    }

    /**
     * @notice Sets the maximum amount of unused deposits that can sit in the pool
     * @param _unusedDepositLimit maximum amount of unused deposits
     **/
    function setUnusedDepositLimit(uint256 _unusedDepositLimit) external onlyOwner {
        unusedDepositLimit = _unusedDepositLimit;
    }

    /**
     * @notice Sets the priority pool
     * @param _priorityPool address of priority pool
     **/
    function setPriorityPool(address _priorityPool) external onlyOwner {
        priorityPool = _priorityPool;
    }

    /**
     * @notice Sets the rebase controller
     * @dev this address has sole authority to update rewards
     * @param _rebaseController address of rebase controller
     **/
    function setRebaseController(address _rebaseController) external onlyOwner {
        rebaseController = _rebaseController;
    }

    /**
     * @notice Returns the total amount of asset tokens staked in the pool
     * @return the total staked amount
     */
    function _totalStaked() internal view override returns (uint256) {
        return totalStaked;
    }

    /**
     * @notice Deposits available liquidity into strategies
     * @dev deposits into strategies in ascending order, only moving to the next once the current is full
     * @param _data list of deposit data passed to strategies
     **/
    function _depositLiquidity(bytes[] calldata _data) private {
        uint256 toDeposit = token.balanceOf(address(this));
        if (toDeposit > 0) {
            for (uint256 i = 0; i < strategies.length; i++) {
                IStrategy strategy = IStrategy(strategies[i]);
                uint256 strategyCanDeposit = strategy.canDeposit();
                if (strategyCanDeposit >= toDeposit) {
                    strategy.deposit(toDeposit, _data[i]);
                    break;
                } else if (strategyCanDeposit > 0) {
                    strategy.deposit(strategyCanDeposit, _data[i]);
                    toDeposit = token.balanceOf(address(this));
                }
            }
        }
    }

    /**
     * @notice Withdraws liquidity from strategies
     * @dev withdraws from strategies in descending order only moving to the next once once the current is empty
     * @param _amount amount to withdraw
     * @param _data list of withdrawal data passed to strategies
     **/
    function _withdrawLiquidity(uint256 _amount, bytes[] calldata _data) private {
        uint256 toWithdraw = _amount;
        uint256 balance = token.balanceOf(address(this));

        for (uint256 i = strategies.length; i > 0; i--) {
            IStrategy strategy = IStrategy(strategies[i - 1]);
            uint256 strategyCanWithdrawdraw = strategy.canWithdraw();

            if (strategyCanWithdrawdraw >= toWithdraw) {
                strategy.withdraw(toWithdraw, _data[i - 1]);
                break;
            } else if (strategyCanWithdrawdraw > 0) {
                strategy.withdraw(strategyCanWithdrawdraw, _data[i - 1]);
                uint256 withdrawn = token.balanceOf(address(this)) - balance;
                balance += withdrawn;
                toWithdraw -= withdrawn;
            }
        }
    }

    /**
     * @notice Distributes rewards/fees based on balance changes in strategies since the last update
     * @param _strategyIdxs indexes of strategies to update rewards for
     * @param _data update data passed to each strategy
     **/
    function _updateStrategyRewards(uint256[] memory _strategyIdxs, bytes memory _data) private {
        int256 totalRewards;
        uint256 totalFeeAmounts;
        uint256 totalFeeCount;
        address[][] memory receivers = new address[][](strategies.length + 1);
        uint256[][] memory feeAmounts = new uint256[][](strategies.length + 1);

        // sum up rewards and fees across strategies
        for (uint256 i = 0; i < _strategyIdxs.length; ++i) {
            IStrategy strategy = IStrategy(strategies[_strategyIdxs[i]]);

            (
                int256 depositChange,
                address[] memory strategyReceivers,
                uint256[] memory strategyFeeAmounts
            ) = strategy.updateDeposits(_data);
            totalRewards += depositChange;

            if (strategyReceivers.length != 0) {
                receivers[i] = strategyReceivers;
                feeAmounts[i] = strategyFeeAmounts;
                totalFeeCount += receivers[i].length;
                for (uint256 j = 0; j < strategyReceivers.length; ++j) {
                    totalFeeAmounts += strategyFeeAmounts[j];
                }
            }
        }

        // update totalStaked if there was a net change in deposits
        if (totalRewards != 0) {
            totalStaked = uint256(int256(totalStaked) + totalRewards);
        }

        // calulate fees if net positive rewards were earned
        if (totalRewards > 0) {
            receivers[receivers.length - 1] = new address[](fees.length);
            feeAmounts[feeAmounts.length - 1] = new uint256[](fees.length);
            totalFeeCount += fees.length;

            for (uint256 i = 0; i < fees.length; i++) {
                receivers[receivers.length - 1][i] = fees[i].receiver;
                feeAmounts[feeAmounts.length - 1][i] =
                    (uint256(totalRewards) * fees[i].basisPoints) /
                    10000;
                totalFeeAmounts += feeAmounts[feeAmounts.length - 1][i];
            }
        }

        // safety check
        if (totalFeeAmounts >= totalStaked) {
            totalFeeAmounts = 0;
        }

        // distribute fees to receivers if there are any
        if (totalFeeAmounts > 0) {
            uint256 sharesToMint = (totalFeeAmounts * totalShares) /
                (totalStaked - totalFeeAmounts);
            _mintShares(address(this), sharesToMint);

            uint256 feesPaidCount;
            for (uint256 i = 0; i < receivers.length; i++) {
                for (uint256 j = 0; j < receivers[i].length; j++) {
                    if (feesPaidCount == totalFeeCount - 1) {
                        transferAndCallFrom(
                            address(this),
                            receivers[i][j],
                            balanceOf(address(this)),
                            "0x"
                        );
                    } else {
                        transferAndCallFrom(address(this), receivers[i][j], feeAmounts[i][j], "0x");
                        feesPaidCount++;
                    }
                }
            }
        }

        emit UpdateStrategyRewards(msg.sender, totalStaked, totalRewards, totalFeeAmounts);
    }

    /**
     * @notice Returns the sum of all fees
     * @return sum of fees in basis points
     **/
    function _totalFeesBasisPoints() private view returns (uint256) {
        uint256 totalFees;
        for (uint i = 0; i < fees.length; i++) {
            totalFees += fees[i].basisPoints;
        }
        return totalFees;
    }

    /**
     * @notice Returns whether or not a strategy exists
     * @param _strategy address of strategy
     * @return true if strategy exists, false otherwise
     **/
    function _strategyExists(address _strategy) private view returns (bool) {
        for (uint256 i = 0; i < strategies.length; i++) {
            if (strategies[i] == _strategy) {
                return true;
            }
        }
        return false;
    }
}
