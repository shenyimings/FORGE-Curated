// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.22;

import "./base/VaultControllerStrategy.sol";
import "./interfaces/IOperatorVault.sol";

/**
 * @title Operator Vault Controller Strategy
 * @notice Implemented strategy for managing multiple Chainlink operator staking vaults
 */
contract OperatorVCS is VaultControllerStrategy {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    // basis point amount of an operator's earned rewards that they receive
    uint256 public operatorRewardPercentage;
    // total unclaimed operator LST rewards
    uint256 private unclaimedOperatorRewards;

    // used to check vault membership in this strategy
    mapping(address => bool) private vaultMapping;
    // list of vaults indexes that are queued for removal
    uint256[] private vaultsToRemove;
    // list of vaults indexes that have been removed
    uint256[] private removedVaults;

    event VaultAdded(address indexed operator, address vault);
    event WithdrawExtraRewards(address indexed receiver, uint256 amount);
    event SetOperatorRewardPercentage(uint256 rewardPercentage);

    error InvalidPercentage();
    error UnauthorizedToken();
    error NoExtraRewards();
    error OperatorNotRemoved();
    error VaultRemovalAlreadyQueued();
    error VaultAlreadyRemoved();

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initializes contract
     * @param _token address of LINK token
     * @param _stakingPool address of the staking pool that controls this strategy
     * @param _stakeController address of Chainlink staking contract
     * @param _vaultImplementation address of the implementation contract to use when deploying new vaults
     * @param _fees list of fees to be paid on rewards
     * @param _maxDepositSizeBP max basis point amount of the deposit room in the Chainlink staking contract
     * that can be deposited at once
     * @param _vaultMaxDeposits max number of tokens that a vault can hold
     * @param _operatorRewardPercentage basis point amount of an operator's earned rewards that they receive
     * @param _vaultDepositController address of vault deposit controller
     **/
    function initialize(
        address _token,
        address _stakingPool,
        address _stakeController,
        address _vaultImplementation,
        Fee[] memory _fees,
        uint256 _maxDepositSizeBP,
        uint256 _vaultMaxDeposits,
        uint256 _operatorRewardPercentage,
        address _vaultDepositController
    ) public reinitializer(4) {
        if (address(token) == address(0)) {
            __VaultControllerStrategy_init(
                _token,
                _stakingPool,
                _stakeController,
                _vaultImplementation,
                _fees,
                _maxDepositSizeBP,
                _vaultMaxDeposits,
                _vaultDepositController
            );

            if (_operatorRewardPercentage > 10000) revert InvalidPercentage();
            operatorRewardPercentage = _operatorRewardPercentage;
            globalVaultState = GlobalVaultState(5, 0, 0, 0);
        } else {
            globalVaultState = GlobalVaultState(5, 0, 0, uint64(maxDepositSizeBP + 1));
            maxDepositSizeBP = _maxDepositSizeBP;
            delete fundFlowController;
            vaultMaxDeposits = _vaultMaxDeposits;
        }

        for (uint64 i = 0; i < 5; ++i) {
            vaultGroups.push(VaultGroup(i, 0));
        }
    }

    /**
     * @notice ERC677 implementation to receive operator rewards
     * @dev rewards are paid in the stakingPool LST
     **/
    function onTokenTransfer(address, uint256, bytes calldata) external {
        if (msg.sender != address(stakingPool)) revert UnauthorizedToken();
    }

    /**
     * @notice Returns the total unclaimed operator rewards
     * @return total unclaimed operator rewards
     * @return total available operator rewards
     **/
    function getOperatorRewards() external view returns (uint256, uint256) {
        return (
            unclaimedOperatorRewards,
            IERC20Upgradeable(address(stakingPool)).balanceOf(address(this))
        );
    }

    /**
     * @notice Called by vaults to withdraw operator rewards
     * @param _receiver address to receive rewards
     * @param _amount amount to withdraw
     */
    function withdrawOperatorRewards(
        address _receiver,
        uint256 _amount
    ) external returns (uint256) {
        if (!vaultMapping[msg.sender]) revert SenderNotAuthorized();

        IERC20Upgradeable lsdToken = IERC20Upgradeable(address(stakingPool));
        uint256 withdrawableRewards = lsdToken.balanceOf(address(this));
        uint256 amountToWithdraw = _amount > withdrawableRewards ? withdrawableRewards : _amount;

        unclaimedOperatorRewards -= amountToWithdraw;
        lsdToken.safeTransfer(_receiver, amountToWithdraw);

        return amountToWithdraw;
    }

    /**
     * @notice Updates deposit accounting and calculates fees on newly earned rewards
     * @param _data encoded minRewards (uint256) - min amount of rewards required to claim (set 0 to skip reward claiming)
     * @return depositChange change in deposits since last update
     * @return receivers list of fee receivers
     * @return amounts list of fee amounts
     */
    function updateDeposits(
        bytes calldata _data
    )
        external
        override
        onlyStakingPool
        returns (int256 depositChange, address[] memory receivers, uint256[] memory amounts)
    {
        uint256 minRewards = _data.length == 0 ? 0 : abi.decode(_data, (uint256));
        uint256 newTotalDeposits = totalDeposits;
        uint256 newTotalPrincipalDeposits;
        uint256 vaultDeposits;
        uint256 operatorRewards;

        uint256 vaultCount = vaults.length;
        address receiver = address(this);
        for (uint256 i = 0; i < vaultCount; ++i) {
            (uint256 deposits, uint256 principal, uint256 rewards) = IOperatorVault(
                address(vaults[i])
            ).updateDeposits(minRewards, receiver);
            vaultDeposits += deposits;
            newTotalPrincipalDeposits += principal;
            operatorRewards += rewards;
        }

        uint256 balance = token.balanceOf(address(this));
        depositChange = int256(vaultDeposits + balance) - int256(totalDeposits);

        if (operatorRewards != 0) {
            receivers = new address[](1 + (depositChange > 0 ? fees.length : 0));
            amounts = new uint256[](receivers.length);
            receivers[0] = address(this);
            amounts[0] = operatorRewards;
            unclaimedOperatorRewards += operatorRewards;
        }

        if (depositChange > 0) {
            newTotalDeposits += uint256(depositChange);

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
        } else if (depositChange < 0) {
            newTotalDeposits -= uint256(depositChange * -1);
        }

        if (balance != 0) {
            token.safeTransfer(address(stakingPool), balance);
            newTotalDeposits -= balance;
        }

        totalDeposits = newTotalDeposits;
        totalPrincipalDeposits = newTotalPrincipalDeposits;
    }

    /**
     * @notice Returns the maximum amount of tokens this strategy can hold
     * @dev accounts for total current deposits + current additional vault space + current space in the Chainlink
     * staking contract + removed vaults
     * @return maximum deposits
     */
    function getMaxDeposits() public view override returns (uint256) {
        (, uint256 maxDeposits) = getVaultDepositLimits();
        uint256 totalRemovedDepositRoom;

        // account for vaults that have been removed from the Chainlink staking contract but not yet removed
        // from this contract
        if (vaultsToRemove.length != 0 || removedVaults.length != 0) {
            uint256 numVaults = vaults.length;
            for (uint256 i = 0; i < numVaults; ++i) {
                if (vaults[i].isRemoved()) {
                    totalRemovedDepositRoom += maxDeposits - vaults[i].getPrincipalDeposits();
                }
            }
        }

        return
            totalDeposits +
            (
                stakeController.isActive()
                    ? MathUpgradeable.min(
                        vaults.length *
                            maxDeposits -
                            totalPrincipalDeposits -
                            totalRemovedDepositRoom,
                        ((stakeController.getMaxPoolSize() - stakeController.getTotalPrincipal()) *
                            maxDepositSizeBP) / 10000
                    )
                    : 0
            );
    }

    /**
     * @notice Returns a list of all vaults queued for removal
     * @return list of vaults
     */
    function getVaultRemovalQueue() external view returns (uint256[] memory) {
        return vaultsToRemove;
    }

    /**
     * @notice Returns a list of all vaults that have been removed
     * @dev these vaults will be replaced when new operators are added
     * @return list of vaults
     */
    function getRemovedVaults() external view returns (uint256[] memory) {
        return removedVaults;
    }

    /**
     * @notice Queues a vault for removal
     * @dev a vault can only be queued for removal if the operator has been removed from the
     * Chainlink staking contract
     * @param _index index of vault
     */
    function queueVaultRemoval(uint256 _index) external {
        IVault vault = vaults[_index];

        if (!vault.isRemoved()) revert OperatorNotRemoved();
        for (uint256 i = 0; i < vaultsToRemove.length; ++i) {
            if (vaultsToRemove[i] == _index) revert VaultRemovalAlreadyQueued();
        }
        for (uint256 i = 0; i < removedVaults.length; ++i) {
            if (removedVaults[i] == _index) revert VaultAlreadyRemoved();
        }

        vaultsToRemove.push(_index);

        // update group accounting if vault is part of a group
        if (_index < globalVaultState.depositIndex) {
            uint256 group = _index % globalVaultState.numVaultGroups;
            uint256[] memory groups = new uint256[](1);
            groups[0] = group;
            fundFlowController.updateOperatorVaultGroupAccounting(groups);

            // if possible, remove vault right away
            if (vaults[_index].claimPeriodActive() || vaults[_index].getTotalDeposits() == 0) {
                removeVault(vaultsToRemove.length - 1);
            }
        }
    }

    /**
     * @notice Removes a vault that has been queued for removal
     * @dev withdraws all funds and marks vault as removed
     * @param _queueIndex index of vault in removal queue
     */
    function removeVault(uint256 _queueIndex) public {
        address vault = address(vaults[vaultsToRemove[_queueIndex]]);

        _updateStrategyRewards();
        (uint256 principalWithdrawn, uint256 rewardsWithdrawn) = IOperatorVault(vault).exitVault();

        totalDeposits -= principalWithdrawn + rewardsWithdrawn;
        totalPrincipalDeposits -= principalWithdrawn;

        removedVaults.push(vaultsToRemove[_queueIndex]);
        delete vaultMapping[vault];
        vaultsToRemove[_queueIndex] = vaultsToRemove[vaultsToRemove.length - 1];
        vaultsToRemove.pop();

        if (principalWithdrawn + rewardsWithdrawn != 0) {
            token.safeTransfer(address(stakingPool), token.balanceOf(address(this)));
        }
    }

    /**
     * @notice Manually unbonds a vault
     * @dev a vault can only be manually unbonded if the operator has been removed from the
     * Chainlink staking contract
     * @param _index index of vault
     */
    function unbondVault(uint256 _index) external onlyOwner {
        IVault vault = vaults[_index];
        if (!IVault(vault).isRemoved()) revert OperatorNotRemoved();
        vaults[_index].unbond();
    }

    /**
     * @notice Deploys a new vault and adds it to this strategy
     * @param _operator address of operator that the vault represents
     * @param _rewardsReceiver address authorized to claim rewards for the vault
     * @param _pfAlertsController address of the price feed alerts contract
     */
    function addVault(
        address _operator,
        address _rewardsReceiver,
        address _pfAlertsController
    ) external onlyOwner {
        bytes memory data = abi.encodeWithSignature(
            "initialize(address,address,address,address,address,address,address,address)",
            address(token),
            address(this),
            address(stakeController),
            stakeController.getRewardVault(),
            delegateRegistry,
            _pfAlertsController,
            _operator,
            _rewardsReceiver
        );
        _deployVault(data);

        address newVault = address(vaults[vaults.length - 1]);
        vaultMapping[newVault] = true;

        // replace a removed vault if there are any
        if (removedVaults.length != 0) {
            uint256 index = removedVaults[removedVaults.length - 1];
            vaults[index] = IVault(newVault);
            vaults.pop();
            removedVaults.pop();
            uint256 group = index % globalVaultState.numVaultGroups;
            vaultGroups[group].totalDepositRoom += uint128(vaultMaxDeposits);
        }

        emit VaultAdded(_operator, newVault);
    }

    /**
     * @notice Updates accounting for any number of vault groups
     * @dev used to correct minor accounting errors that result from the removal or slashing
     * of operators in the Chainlink staking contract
     * @param _vaultGroups list of vault groups to update
     * @param _totalDepositRoom list of totalDepositRoom corresponding to list of vault groups
     * @param _totalUnbonded total amount currently unbonded
     * @param _vaultMaxDeposits vault deposit limit as defined in Chainlink staking contract
     */
    function updateVaultGroupAccounting(
        uint256[] calldata _vaultGroups,
        uint256[] calldata _totalDepositRoom,
        uint256 _totalUnbonded,
        uint256 _vaultMaxDeposits
    ) external onlyFundFlowController {
        for (uint256 i = 0; i < _vaultGroups.length; ++i) {
            vaultGroups[_vaultGroups[i]].totalDepositRoom = uint128(_totalDepositRoom[i]);
        }

        if (_totalUnbonded != totalUnbonded) totalUnbonded = _totalUnbonded;
        if (_vaultMaxDeposits > vaultMaxDeposits) vaultMaxDeposits = _vaultMaxDeposits;
    }

    /**
     * @notice Sets a vault's operator address
     * @param _index index of vault
     * @param _operator address of operator that the vault represents
     */
    function setOperator(uint256 _index, address _operator) external onlyOwner {
        IOperatorVault(address(vaults[_index])).setOperator(_operator);
    }

    /**
     * @notice Sets the address authorized to claim rewards for a vault
     * @param _index index of vault
     * @param _rewardsReceiver address of rewards receiver for the vault
     */
    function setRewardsReceiver(uint256 _index, address _rewardsReceiver) external onlyOwner {
        IOperatorVault(address(vaults[_index])).setRewardsReceiver(_rewardsReceiver);
    }

    /**
     * @notice Sets the basis point amount of an operator's earned rewards that they receive
     * @dev stakingPool.updateStrategyRewards is called to credit all past operator rewards at
     * the old rate before the reward percentage changes
     * @param _operatorRewardPercentage basis point amount
     */
    function setOperatorRewardPercentage(uint256 _operatorRewardPercentage) public onlyOwner {
        if (_operatorRewardPercentage > 10000) revert InvalidPercentage();

        _updateStrategyRewards();

        operatorRewardPercentage = _operatorRewardPercentage;
        emit SetOperatorRewardPercentage(_operatorRewardPercentage);
    }
}
