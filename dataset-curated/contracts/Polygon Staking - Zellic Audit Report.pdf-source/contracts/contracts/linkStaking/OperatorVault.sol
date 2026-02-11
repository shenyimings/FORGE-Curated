// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.22;

import "@openzeppelin/contracts/utils/math/SafeCast.sol";

import "./base/Vault.sol";
import "./interfaces/IOperatorVCS.sol";
import "./interfaces/IOperatorStaking.sol";
import "./interfaces/IPFAlertsController.sol";

/**
 * @title Operator Vault
 * @notice Vault contract for depositing LINK collateral into the Chainlink operator staking controller -
 * each vault represents a single operator
 */
contract OperatorVault is Vault {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    address public operator;
    address public rewardsReceiver;
    IPFAlertsController public pfAlertsController;

    uint128 public trackedTotalDeposits;
    uint128 private unclaimedRewards;

    event AlertRaised();
    event WithdrawRewards(address indexed receiver, uint256 amount);
    event SetRewardsReceiver(address indexed rewardsReceiver);

    error OnlyOperator();
    error OnlyRewardsReceiver();
    error ZeroAddress();
    error OperatorAlreadySet();
    error OperatorNotRemoved();

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initializes contract
     * @param _token address of LINK token
     * @param _vaultController address of the strategy that controls this vault
     * @param _stakeController address of Chainlink operator staking contract
     * @param _rewardsController address of Chainlink staking rewards contract
     * @param _delegateRegistry address of delegate registry
     * @param _pfAlertsController address of Chainlink price feed alrts controller
     * @param _operator address of operator represented by this vault
     * @param _rewardsReceiver address authorized to claim rewards from this vault
     **/
    function initialize(
        address _token,
        address _vaultController,
        address _stakeController,
        address _rewardsController,
        address _delegateRegistry,
        address _pfAlertsController,
        address _operator,
        address _rewardsReceiver
    ) public reinitializer(3) {
        if (vaultController == address(0)) {
            __Vault_init(
                _token,
                _vaultController,
                _stakeController,
                _rewardsController,
                _delegateRegistry
            );
        } else {
            stakeController.migrate("");
            stakeController = IStaking(_stakeController);
            rewardsController = IStakingRewards(_rewardsController);
            trackedTotalDeposits = SafeCast.toUint128(getTotalDeposits());
        }
        pfAlertsController = IPFAlertsController(_pfAlertsController);
        rewardsReceiver = _rewardsReceiver;
        if (operator == address(0) && _operator != address(0)) {
            setOperator(_operator);
        }
    }

    /**
     * @notice Reverts if sender is not operator
     **/
    modifier onlyOperator() {
        if (msg.sender != operator) revert OnlyOperator();
        _;
    }

    /**
     * @notice Reverts if sender is not rewards receiver
     **/
    modifier onlyRewardsReceiver() {
        if (msg.sender != rewardsReceiver) revert OnlyRewardsReceiver();
        _;
    }

    /**
     * @notice Deposits tokens from the vault controller into the Chainlink staking contract
     * @param _amount amount to deposit
     */
    function deposit(uint256 _amount) external override onlyVaultController {
        trackedTotalDeposits += SafeCast.toUint128(_amount);
        token.safeTransferFrom(msg.sender, address(this), _amount);
        IERC677(address(token)).transferAndCall(address(stakeController), _amount, "");
    }

    /**
     * @notice Withdraws tokens from the Chainlink staking contract and sends them to the vault controller
     * @param _amount amount to withdraw
     */
    function withdraw(uint256 _amount) external override onlyVaultController {
        trackedTotalDeposits -= SafeCast.toUint128(_amount);
        stakeController.unstake(_amount);
        token.safeTransfer(vaultController, _amount);
    }

    /**
     * @notice Returns the principal balance of this contract in the Chainlink staking contract
     * @dev includes principal that was removed due to a removal of this operator in the Chainlink contract
     * @return principal balance
     */
    function getPrincipalDeposits() public view override returns (uint256) {
        return
            super.getPrincipalDeposits() +
            IOperatorStaking(address(stakeController)).getRemovedPrincipal(address(this));
    }

    /**
     * @notice Raises an alert in the Chainlink staking contract
     * @param _feed address of Chainlink feed to raise alert for
     */
    function raiseAlert(address _feed) external onlyOperator {
        uint256 prevBalance = token.balanceOf(address(this));

        pfAlertsController.raiseAlert(_feed);

        uint256 rewards = token.balanceOf(address(this)) - prevBalance;
        uint256 opRewards = (rewards * IOperatorVCS(vaultController).operatorRewardPercentage()) /
            10000;
        token.safeTransfer(vaultController, rewards - opRewards);

        emit AlertRaised();
    }

    /**
     * @notice Returns the total unclaimed operator rewards for this vault
     * @dev includes liquid staking tokens and asset tokens
     * @return total rewards
     */
    function getUnclaimedRewards() public view returns (uint256) {
        return unclaimedRewards + token.balanceOf(address(this));
    }

    /**
     * @notice Withdraws the unclaimed operator rewards for this vault
     */
    function withdrawRewards() external onlyRewardsReceiver {
        _withdrawRewards();
    }

    /**
     * @notice Returns the amount of rewards that will be earned by this vault on the next update
     * @return newly earned rewards
     */
    function getPendingRewards() public view returns (uint256) {
        int256 depositChange = int256(getTotalDeposits()) - int256(uint256(trackedTotalDeposits));

        if (depositChange > 0) {
            return
                (uint256(depositChange) *
                    IOperatorVCS(vaultController).operatorRewardPercentage()) / 10000;
        }

        return 0;
    }

    /**
     * @notice Updates the deposit and reward accounting for this vault
     * @dev will only pay out rewards if the vault is net positive when accounting for lost deposits
     * @param _minRewards min amount of rewards to claim (set 0 to skip reward claiming)
     * @param _rewardsReceiver address to receive claimed rewards (set if _minRewards > 0)
     * @return totalDeposits the current total deposits in this vault
     * @return principalDeposits the current principal deposits in this vault
     * @return rewards the rewards earned by this vault since the last update
     */
    function updateDeposits(
        uint256 _minRewards,
        address _rewardsReceiver
    ) external onlyVaultController returns (uint256, uint256, uint256) {
        uint256 principal = getPrincipalDeposits();
        uint256 rewards = getRewards();
        uint256 totalDeposits = principal + rewards;
        int256 depositChange = int256(totalDeposits) - int256(uint256(trackedTotalDeposits));

        uint256 opRewards;
        if (depositChange > 0) {
            opRewards =
                (uint256(depositChange) *
                    IOperatorVCS(vaultController).operatorRewardPercentage()) /
                10000;
            unclaimedRewards += SafeCast.toUint128(opRewards);
            trackedTotalDeposits = SafeCast.toUint128(totalDeposits);
        }

        if (_minRewards != 0 && rewards >= _minRewards) {
            rewardsController.claimReward();
            trackedTotalDeposits -= SafeCast.toUint128(rewards);
            totalDeposits -= rewards;
            token.safeTransfer(_rewardsReceiver, rewards);
        }

        return (totalDeposits, principal, opRewards);
    }

    /**
     * @notice Returns whether this vault has been removed as an operator from the Chainlink staking contract
     * @return true if operator has been removed, false otherwise
     */
    function isRemoved() public view override returns (bool) {
        return stakeController.isRemoved(address(this));
    }

    /**
     * @notice Withdraws tokens from the Chainlink staking contract and sends them to the vault controller
     * @dev updateDeposits must be called before calling this function
     * @dev used to withdraw remaining principal and rewards after operator has been removed
     * @dev will also send any unclaimed operator rewards to rewards receiver
     * @return total principal withdrawn
     * @return total rewards withdrawn
     */
    function exitVault() external onlyVaultController returns (uint256, uint256) {
        if (!isRemoved()) revert OperatorNotRemoved();

        uint256 opRewards = getUnclaimedRewards();
        if (opRewards != 0) _withdrawRewards();

        uint256 rewards = getRewards();
        if (rewards != 0) rewardsController.claimReward();

        uint256 principal = getPrincipalDeposits();
        if (principal != 0) stakeController.unstakeRemovedPrincipal();

        uint256 balance = token.balanceOf(address(this));
        if (balance != 0) token.safeTransfer(vaultController, balance);

        return (principal, rewards);
    }

    /**
     * @notice Sets the operator address if not already set
     * @dev only used for original vaults that are already deployed and don't have an operator set
     * @param _operator operator address
     */
    function setOperator(address _operator) public onlyOwner {
        if (operator != address(0)) revert OperatorAlreadySet();
        if (_operator == address(0)) revert ZeroAddress();
        operator = _operator;
    }

    /**
     * @notice Sets the rewards receiver
     * @dev this address is authorized to withdraw rewards for this vault and/or change the rewardsReceiver
     * to a new a address
     * @param _rewardsReceiver rewards receiver address
     */
    function setRewardsReceiver(address _rewardsReceiver) public {
        if (rewardsReceiver != address(0) && msg.sender != rewardsReceiver)
            revert OnlyRewardsReceiver();
        if (rewardsReceiver == address(0) && msg.sender != owner()) revert OnlyRewardsReceiver();
        if (_rewardsReceiver == address(0)) revert ZeroAddress();
        rewardsReceiver = _rewardsReceiver;
        emit SetRewardsReceiver(_rewardsReceiver);
    }

    /**
     * @notice Withdraws the unclaimed operator rewards for this vault
     */
    function _withdrawRewards() private {
        uint256 rewards = getUnclaimedRewards();
        uint256 balance = token.balanceOf(address(this));

        uint256 amountWithdrawn = IOperatorVCS(vaultController).withdrawOperatorRewards(
            rewardsReceiver,
            rewards - balance
        );
        unclaimedRewards -= SafeCast.toUint128(amountWithdrawn);

        if (balance != 0) {
            token.safeTransfer(rewardsReceiver, balance);
        }

        emit WithdrawRewards(rewardsReceiver, amountWithdrawn + balance);
    }
}
