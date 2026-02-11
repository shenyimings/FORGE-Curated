// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.22;

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/math/MathUpgradeable.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import "../../core/interfaces/IERC677.sol";
import "../../core/base/Strategy.sol";
import "../interfaces/IVault.sol";
import "../interfaces/IStaking.sol";
import "../interfaces/IFundFlowController.sol";

struct Fee {
    // address to recieve fee
    address receiver;
    // value of fee in basis points
    uint256 basisPoints;
}

struct VaultGroup {
    // index of next vault in the group to be withdrawn from
    uint64 withdrawalIndex;
    // total deposit room across all vaults in the group
    uint128 totalDepositRoom;
}

struct GlobalVaultState {
    // total number of groups
    uint64 numVaultGroups;
    // index of the current unbonded group
    uint64 curUnbondedVaultGroup;
    // index of next vault to receive deposits across all groups
    uint64 groupDepositIndex;
    // index of next non-group vault to receive deposits
    uint64 depositIndex;
}

error InvalidVaultIds();
error InsufficientTokensUnbonded();

/**
 * @title Vault Deposit Controller
 * @notice Handles deposits and withdrawals for VaultControllerStrategy through delegatecall
 * @dev this contract was required to avoid exceeding the contract size limit
 */
contract VaultDepositController is Strategy {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    // address of Chainlink staking contract
    IStaking public stakeController;
    // list of fees that are paid on rewards
    Fee[] internal fees;

    // address of vault implementation contract to be used when adding new vaults
    address public vaultImplementation;

    // list of all vaults controlled by this strategy
    IVault[] internal vaults;
    // total number of tokens staked in this strategy
    uint256 internal totalDeposits;
    // total number of tokens staked through this strategy as principal in the Chainlink staking contract
    uint256 public totalPrincipalDeposits;

    // max basis point amount of the deposit room in the Chainlink staking contract that can be deposited at once
    uint256 public maxDepositSizeBP;

    // address of fund flow controller
    IFundFlowController public fundFlowController;
    // total number of tokens currently unbonded in the Chainlink staking contract
    uint256 public totalUnbonded;

    // list of vault groups
    VaultGroup[] public vaultGroups;
    // global state across all vault groups
    GlobalVaultState public globalVaultState;
    // max number of tokens that a vault can hold
    uint256 public vaultMaxDeposits;

    /**
     * @notice Deposits tokens from the staking pool into vaults
     * @dev called by VaultControllerStrategy using delegatecall
     * @param _amount amount to deposit
     * @param _data encoded vault deposit order
     */
    function deposit(uint256 _amount, bytes calldata _data) external {
        token.safeTransferFrom(msg.sender, address(this), _amount);

        (uint256 minDeposits, uint256 maxDeposits) = getVaultDepositLimits();

        uint64[] memory vaultIds = abi.decode(_data, (uint64[]));

        uint256 deposited = _depositToVaults(_amount, minDeposits, maxDeposits, vaultIds);

        totalDeposits += deposited;
        totalPrincipalDeposits += deposited;

        if (deposited < _amount) {
            token.safeTransfer(address(stakingPool), _amount - deposited);
        }
    }

    /**
     * @notice Withdraws tokens from vaults and sends them to staking pool
     * @dev called by VaultControllerStrategy using delegatecall
     * @param _amount amount to withdraw
     * @param _data encoded vault withdrawal order
     */
    function withdraw(uint256 _amount, bytes calldata _data) external {
        if (!fundFlowController.claimPeriodActive() || _amount > totalUnbonded)
            revert InsufficientTokensUnbonded();

        GlobalVaultState memory globalState = globalVaultState;
        uint64[] memory vaultIds = abi.decode(_data, (uint64[]));
        VaultGroup memory group = vaultGroups[globalState.curUnbondedVaultGroup];

        // withdrawals must continue with the vault they left off at during the previous call
        if (vaultIds[0] != group.withdrawalIndex) revert InvalidVaultIds();

        uint256 toWithdraw = _amount;
        uint256 unbondedRemaining = totalUnbonded;
        (uint256 minDeposits, ) = getVaultDepositLimits();

        for (uint256 i = 0; i < vaultIds.length; ++i) {
            // vault must be a member of the current unbonded group
            if (vaultIds[i] % globalState.numVaultGroups != globalState.curUnbondedVaultGroup)
                revert InvalidVaultIds();

            group.withdrawalIndex = uint64(vaultIds[i]);
            IVault vault = vaults[vaultIds[i]];
            uint256 deposits = vault.getPrincipalDeposits();

            if (deposits != 0 && vault.claimPeriodActive() && !vault.isRemoved()) {
                if (toWithdraw > deposits) {
                    vault.withdraw(deposits);
                    unbondedRemaining -= deposits;
                    toWithdraw -= deposits;
                } else if (deposits - toWithdraw > 0 && deposits - toWithdraw < minDeposits) {
                    // cannot leave a vault with less than minimum deposits
                    vault.withdraw(deposits);
                    unbondedRemaining -= deposits;
                    break;
                } else {
                    vault.withdraw(toWithdraw);
                    unbondedRemaining -= toWithdraw;
                    break;
                }
            }
        }

        uint256 totalWithdrawn = totalUnbonded - unbondedRemaining;

        token.safeTransfer(msg.sender, totalWithdrawn);

        totalDeposits -= totalWithdrawn;
        totalPrincipalDeposits -= totalWithdrawn;
        totalUnbonded = unbondedRemaining;

        group.totalDepositRoom += uint128(totalWithdrawn);
        vaultGroups[globalVaultState.curUnbondedVaultGroup] = group;
    }

    /**
     * @notice Deposits tokens into vaults
     * @param _toDeposit amount to deposit
     * @param _minDeposits minimum amount of deposits that a vault can hold
     * @param _maxDeposits minimum amount of deposits that a vault can hold
     * @param _vaultIds list of vaults to deposit into
     */
    function _depositToVaults(
        uint256 _toDeposit,
        uint256 _minDeposits,
        uint256 _maxDeposits,
        uint64[] memory _vaultIds
    ) private returns (uint256) {
        uint256 toDeposit = _toDeposit;
        uint256 totalRebonded;
        GlobalVaultState memory globalState = globalVaultState;
        VaultGroup[] memory groups = vaultGroups;

        // deposits must continue with the vault they left off at during the previous call
        if (_vaultIds.length != 0 && _vaultIds[0] != globalState.groupDepositIndex)
            revert InvalidVaultIds();

        // deposit into vaults in the order specified in _vaultIds
        for (uint256 i = 0; i < _vaultIds.length; ++i) {
            uint256 vaultIndex = _vaultIds[i];
            // vault must be a member of a group
            if (vaultIndex >= globalState.depositIndex) revert InvalidVaultIds();

            IVault vault = vaults[vaultIndex];
            uint256 groupIndex = vaultIndex % globalState.numVaultGroups;
            VaultGroup memory group = groups[groupIndex];
            uint256 deposits = vault.getPrincipalDeposits();
            uint256 canDeposit = _maxDeposits - deposits;

            globalState.groupDepositIndex = uint64(vaultIndex);

            // if vault is empty and equal to withdrawal index, increment withdrawal index to the next vault in the group
            if (deposits == 0 && vaultIndex == group.withdrawalIndex) {
                group.withdrawalIndex += uint64(globalState.numVaultGroups);
                if (group.withdrawalIndex >= globalState.depositIndex) {
                    group.withdrawalIndex = uint64(groupIndex);
                }
            }

            if (canDeposit != 0 && vaultIndex != group.withdrawalIndex && !vault.isRemoved()) {
                if (deposits < _minDeposits && toDeposit < (_minDeposits - deposits)) {
                    break;
                }

                // unbonded funds are rebonded if the vault receives deposits
                if (vault.claimPeriodActive()) {
                    totalRebonded += deposits;
                }

                if (toDeposit > canDeposit) {
                    vault.deposit(canDeposit);
                    toDeposit -= canDeposit;
                    group.totalDepositRoom -= uint128(canDeposit);
                } else {
                    vault.deposit(toDeposit);
                    group.totalDepositRoom -= uint128(toDeposit);
                    toDeposit = 0;
                    break;
                }
            }
        }

        globalVaultState = globalState;

        // update vault groups if state was changed
        for (uint256 i = 0; i < globalState.numVaultGroups; ++i) {
            VaultGroup memory group = vaultGroups[i];
            if (
                group.withdrawalIndex != groups[i].withdrawalIndex ||
                group.totalDepositRoom != groups[i].totalDepositRoom
            ) {
                vaultGroups[i] = groups[i];
            }
        }

        if (totalRebonded != 0) totalUnbonded -= totalRebonded;
        if (toDeposit == 0 || toDeposit < _minDeposits) return _toDeposit - toDeposit;

        // cannot be more than 1 vault worth of deposit room in each group (or 2 in current unbonded group)
        for (uint256 i = 0; i < globalState.numVaultGroups; ++i) {
            if (
                (i != globalState.curUnbondedVaultGroup &&
                    groups[i].totalDepositRoom >= _maxDeposits) ||
                (i == globalState.curUnbondedVaultGroup &&
                    groups[i].totalDepositRoom >= 2 * _maxDeposits)
            ) {
                return _toDeposit - toDeposit;
            }
        }

        // deposit into additional vaults that don't yet belong to a group
        uint256 numVaults = vaults.length;
        uint256 i = globalState.depositIndex;

        while (i < numVaults) {
            IVault vault = vaults[i];
            uint256 deposits = vault.getPrincipalDeposits();
            uint256 canDeposit = _maxDeposits - deposits;

            if (vault.isRemoved()) {
                ++i;
                continue;
            }

            // cannot leave a vault with less than minimum deposits
            if (deposits < _minDeposits && toDeposit < (_minDeposits - deposits)) {
                break;
            }

            if (toDeposit > canDeposit) {
                vault.deposit(canDeposit);
                toDeposit -= canDeposit;
            } else {
                vault.deposit(toDeposit);
                if (toDeposit < canDeposit) {
                    toDeposit = 0;
                    break;
                }
                toDeposit = 0;
            }

            ++i;
        }

        globalVaultState.depositIndex = uint64(i);

        return _toDeposit - toDeposit;
    }

    /**
     * @notice Returns the vault deposit limits for vaults controlled by this strategy
     * @return minimum amount of deposits that a vault can hold
     * @return maximum amount of deposits that a vault can hold
     */
    function getVaultDepositLimits() public view returns (uint256, uint256) {
        return stakeController.getStakerLimits();
    }

    // remaining functions are required to satisfy the strategy interface

    function updateDeposits(
        bytes calldata _data
    )
        external
        returns (int256 depositChange, address[] memory receivers, uint256[] memory amounts)
    {}

    function getTotalDeposits() public view override returns (uint256) {}

    function getMaxDeposits() public view override returns (uint256) {}

    function getMinDeposits() public view override returns (uint256) {}

    function getDepositChange() external view returns (int256) {}
}

/**
 * @title Vault Controller Strategy
 * @notice Base strategy for managing multiple Chainlink staking vaults
 */
abstract contract VaultControllerStrategy is Strategy {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    // address of Chainlink staking contract
    IStaking public stakeController;
    // list of fees that are paid on rewards
    Fee[] internal fees;

    // address of vault implementation contract to be used when deploying new vaults
    address public vaultImplementation;

    // list of all vaults controlled by this strategy
    IVault[] internal vaults;
    // total number of tokens staked in this strategy
    uint256 internal totalDeposits;
    // total number of tokens staked through this strategy as principal in the Chainlink staking contract
    uint256 public totalPrincipalDeposits;

    // max basis point amount of the deposit room in the Chainlink staking contract that can be deposited at once
    uint256 public maxDepositSizeBP;

    // address of fund flow controller
    IFundFlowController public fundFlowController;
    // total number of tokens currently unbonded in the Chainlink staking contract
    uint256 public totalUnbonded;

    // list of vault groups
    VaultGroup[] public vaultGroups;
    // global state across all vault groups
    GlobalVaultState public globalVaultState;
    // max number of tokens that a vault can hold
    uint256 public vaultMaxDeposits;

    // address of vault deposit controller
    address public vaultDepositController;
    // address of delegate registry
    address public delegateRegistry;

    // storage gap for upgradeability
    uint256[3] private __gap;

    event UpgradedVaults(uint256[] vaults);
    event SetMaxDepositSizeBP(uint256 maxDepositSizeBP);
    event SetVaultImplementation(address vaultImplementation);

    error FeesTooLarge();
    error InvalidBasisPoints();
    error SenderNotAuthorized();
    error InvalidWithdrawalIndexes();
    error DepositFailed();
    error WithdrawalFailed();
    error VaultDepositControllerNotSet();

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
     * @param _vaultDepositController address of vault deposit controller
     **/
    function __VaultControllerStrategy_init(
        address _token,
        address _stakingPool,
        address _stakeController,
        address _vaultImplementation,
        Fee[] memory _fees,
        uint256 _maxDepositSizeBP,
        uint256 _vaultMaxDeposits,
        address _vaultDepositController
    ) public onlyInitializing {
        __Strategy_init(_token, _stakingPool);

        stakeController = IStaking(_stakeController);

        vaultImplementation = _vaultImplementation;

        for (uint256 i = 0; i < _fees.length; ++i) {
            fees.push(_fees[i]);
        }
        if (_totalFeesBasisPoints() > 3000) revert FeesTooLarge();

        if (_maxDepositSizeBP > 10000) revert InvalidBasisPoints();
        maxDepositSizeBP = _maxDepositSizeBP;

        vaultMaxDeposits = _vaultMaxDeposits;
        vaultDepositController = _vaultDepositController;
    }

    /**
     * @notice Reverts if sender is not fund flow controller
     */
    modifier onlyFundFlowController() {
        if (msg.sender != address(fundFlowController)) revert SenderNotAuthorized();
        _;
    }

    /**
     * @notice Returns a list of all vaults controlled by this contract
     * @return list of vault addresses
     */
    function getVaults() external view returns (IVault[] memory) {
        return vaults;
    }

    /**
     * @notice Deposits tokens from the staking pool into vaults
     * @param _amount amount to deposit
     * @param _data encoded vault deposit order
     */
    function deposit(uint256 _amount, bytes calldata _data) external virtual onlyStakingPool {
        if (vaultDepositController == address(0)) revert VaultDepositControllerNotSet();

        (bool success, ) = vaultDepositController.delegatecall(
            abi.encodeWithSelector(VaultDepositController.deposit.selector, _amount, _data)
        );

        if (!success) revert DepositFailed();
    }

    /**
     * @notice Withdraws tokens from vaults and sends them to staking pool
     * @param _amount amount to withdraw
     * @param _data encoded vault withdrawal order
     */
    function withdraw(uint256 _amount, bytes calldata _data) external onlyStakingPool {
        if (vaultDepositController == address(0)) revert VaultDepositControllerNotSet();

        (bool success, ) = vaultDepositController.delegatecall(
            abi.encodeWithSelector(VaultDepositController.withdraw.selector, _amount, _data)
        );

        if (!success) revert WithdrawalFailed();
    }

    /**
     * @notice Executes a vault group update
     * @dev re-unbonds all vaults in the current vault group and increments the current vault group
     * to the next one which will have just entered the claim period
     * @param _curGroupVaultsToUnbond list of vaults to unbond in current vault group
     * @param _curGroupTotalDepositRoom total deposit room across all vaults in current vault group
     * @param _nextGroup index of next vault group
     * @param _nextGroupTotalUnbonded total unbonded across all vaults in next vault group
     */
    function updateVaultGroups(
        uint256[] calldata _curGroupVaultsToUnbond,
        uint256 _curGroupTotalDepositRoom,
        uint256 _nextGroup,
        uint256 _nextGroupTotalUnbonded
    ) external onlyFundFlowController {
        for (uint256 i = 0; i < _curGroupVaultsToUnbond.length; ++i) {
            vaults[_curGroupVaultsToUnbond[i]].unbond();
        }

        vaultGroups[globalVaultState.curUnbondedVaultGroup].totalDepositRoom = uint128(
            _curGroupTotalDepositRoom
        );
        globalVaultState.curUnbondedVaultGroup = uint64(_nextGroup);
        totalUnbonded = _nextGroupTotalUnbonded;
    }

    /**
     * @notice Returns the deposit change since deposits were last updated
     * @dev deposit change could be positive or negative depending on reward rate and whether
     * any slashing occurred
     * @return deposit change
     */
    function getDepositChange() public view virtual returns (int) {
        uint256 totalBalance = token.balanceOf(address(this));
        for (uint256 i = 0; i < vaults.length; ++i) {
            totalBalance += vaults[i].getTotalDeposits();
        }
        return int(totalBalance) - int(totalDeposits);
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
        virtual
        onlyStakingPool
        returns (int256 depositChange, address[] memory receivers, uint256[] memory amounts)
    {
        depositChange = getDepositChange();
        uint256 newTotalDeposits = totalDeposits;

        if (depositChange > 0) {
            newTotalDeposits += uint256(depositChange);

            receivers = new address[](fees.length);
            amounts = new uint256[](fees.length);

            for (uint256 i = 0; i < fees.length; ++i) {
                receivers[i] = fees[i].receiver;
                amounts[i] = (uint256(depositChange) * fees[i].basisPoints) / 10000;
            }
        } else if (depositChange < 0) {
            newTotalDeposits -= uint256(depositChange * -1);
        }

        uint256 balance = token.balanceOf(address(this));
        if (balance != 0) {
            token.safeTransfer(address(stakingPool), balance);
            newTotalDeposits -= balance;
        }

        totalDeposits = newTotalDeposits;
    }

    /**
     * @notice Returns the total amount of deposits as tracked in this strategy
     * @return total deposits
     */
    function getTotalDeposits() public view override returns (uint256) {
        return totalDeposits;
    }

    /**
     * @notice Returns the maximum amount of tokens this strategy can hold
     * @dev accounts for total current deposits + current additional vault space + current space in the Chainlink
     * staking contract
     * @return maximum deposits
     */
    function getMaxDeposits() public view virtual override returns (uint256) {
        (, uint256 maxDeposits) = getVaultDepositLimits();
        return
            totalDeposits +
            (
                stakeController.isActive()
                    ? MathUpgradeable.min(
                        vaults.length * maxDeposits - totalPrincipalDeposits,
                        ((stakeController.getMaxPoolSize() - stakeController.getTotalPrincipal()) *
                            maxDepositSizeBP) / 10000
                    )
                    : 0
            );
    }

    /**
     * @notice Returns the minimum amount of tokens that must remain in this strategy
     * @return minimum deposits
     */
    function getMinDeposits() public view virtual override returns (uint256) {
        return
            fundFlowController.claimPeriodActive() ? totalDeposits - totalUnbonded : totalDeposits;
    }

    /**
     * @notice Returns the vault deposit limits for vaults controlled by this strategy
     * @return minimum amount of deposits that a vault can hold
     * @return maximum amount of deposits that a vault can hold
     */
    function getVaultDepositLimits() public view returns (uint256, uint256) {
        return stakeController.getStakerLimits();
    }

    /**
     * @notice Manually sets the withdrawal index for each vault group
     * @param _withdrawalIndexes list of withdrawal indexes for each vault group
     */
    function setWithdrawalIndexes(uint64[] calldata _withdrawalIndexes) external onlyOwner {
        uint256 numVaultGroups = globalVaultState.numVaultGroups;
        for (uint256 i = 0; i < numVaultGroups; ++i) {
            if (_withdrawalIndexes[i] % numVaultGroups != i) revert InvalidWithdrawalIndexes();
            vaultGroups[i].withdrawalIndex = _withdrawalIndexes[i];
        }
    }

    /**
     * @notice Upgrades vaults to a new implementation contract
     * @param _vaults list of vault indexes to upgrade
     * @param _data list of encoded function calls to be executed for each vault after upgrade
     */
    function upgradeVaults(uint256[] calldata _vaults, bytes[] memory _data) external onlyOwner {
        for (uint256 i = 0; i < _vaults.length; ++i) {
            if (_data[i].length == 0) {
                vaults[_vaults[i]].upgradeTo(vaultImplementation);
            } else {
                vaults[_vaults[i]].upgradeToAndCall(vaultImplementation, _data[i]);
            }
        }
        emit UpgradedVaults(_vaults);
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
     * @dev stakingPool.updateStrategyRewards is called to credit all past fees at
     * the old rate before the percentage changes
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
     * @dev stakingPool.updateStrategyRewards is called to credit all past fees at
     * the old rate before the percentage changes
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
     * @notice Sets the basis point amount of the remaing deposit room in the Chainlink staking contract
     * that can be deposited at once
     * @param _maxDepositSizeBP basis point amount
     */
    function setMaxDepositSizeBP(uint256 _maxDepositSizeBP) external onlyOwner {
        if (_maxDepositSizeBP > 10000) revert InvalidBasisPoints();
        maxDepositSizeBP = _maxDepositSizeBP;
        emit SetMaxDepositSizeBP(_maxDepositSizeBP);
    }

    /**
     * @notice Sets a new vault implementation contract to be used when deploying/upgrading vaults
     * @param _vaultImplementation address of implementation contract
     */
    function setVaultImplementation(address _vaultImplementation) external onlyOwner {
        vaultImplementation = _vaultImplementation;
        emit SetVaultImplementation(_vaultImplementation);
    }

    /**
     * @notice Sets the fund flow controller
     * @dev this address is authorized to unbond tokens in the Chainlink staking contract
     * @param _fundFlowController address of fund flow controller
     */
    function setFundFlowController(address _fundFlowController) external onlyOwner {
        fundFlowController = IFundFlowController(_fundFlowController);
    }

    /**
     * @notice Sets the vault deposit controller
     * @dev this contract handles depositing into vaults through delegatecall
     * @param _vaultDepositController address of vault deposit controller
     */
    function setVaultDepositController(address _vaultDepositController) external onlyOwner {
        vaultDepositController = _vaultDepositController;
    }

    /**
     * @notice Sets the delegate registry
     * @param _delegateRegistry address of delegate registry
     */
    function setDelegateRegistry(address _delegateRegistry) external onlyOwner {
        delegateRegistry = _delegateRegistry;
    }

    /**
     * @notice Deploys a new vault and adds it to this strategy
     * @param _data optional encoded function call to be executed after deployment
     */
    function _deployVault(bytes memory _data) internal {
        address vault = address(new ERC1967Proxy(vaultImplementation, _data));
        token.safeApprove(vault, type(uint256).max);
        vaults.push(IVault(vault));
    }

    /**
     * @notice Updates rewards for all strategies controlled by the staking pool
     * @dev called before fees are changed to credit any past rewards at the old rate
     */
    function _updateStrategyRewards() internal {
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
