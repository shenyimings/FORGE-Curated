// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.22;

import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

import "./interfaces/IVaultControllerStrategy.sol";
import "./interfaces/IOperatorVCS.sol";
import "./interfaces/IVault.sol";
import "./interfaces/IOperatorVault.sol";

/**
 * @title Fund Flow Controller
 * @notice Manages deposits and withdrawals for Chainlink staking vaults in the OperatorVCS and CommunityVCS
 */
contract FundFlowController is UUPSUpgradeable, OwnableUpgradeable {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    // address of operator vcs
    IVaultControllerStrategy public operatorVCS;
    // address of community vcs
    IVaultControllerStrategy public communityVCS;

    // duration of the unbonding period in the Chainlink staking contract
    uint64 public unbondingPeriod;
    // duration of the claim period in the Chainlink staking contract
    uint64 public claimPeriod;

    // total number of vault groups
    uint64 public numVaultGroups;
    // index of current unbonded vault group
    uint64 public curUnbondedVaultGroup;
    // time that each vault group was last unbonded
    uint256[] public timeOfLastUpdateByGroup;

    // address of LINK token
    address public linkToken;
    // address of reward receiver for non LINK vault rewards
    address public nonLINKRewardReceiver;

    error SenderNotAuthorized();
    error NoUpdateNeeded();
    error InvalidToken();

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initializes contract
     * @param _operatorVCS address of OperatorVCS
     * @param _communityVCS address of CommunityVCS
     * @param _linkToken address of LINK token
     * @param _nonLINKRewardReceiver address of reward receiver for non LINK vault rewards
     * @param _unbondingPeriod unbonding period as set in Chainlink staking contract
     * @param _claimPeriod claim period as set in Chainlink staking contract
     * @param _numVaultGroups total number of vault groups
     */
    function initialize(
        address _operatorVCS,
        address _communityVCS,
        address _linkToken,
        address _nonLINKRewardReceiver,
        uint64 _unbondingPeriod,
        uint64 _claimPeriod,
        uint64 _numVaultGroups
    ) public reinitializer(2) {
        if (address(operatorVCS) == address(0)) {
            __UUPSUpgradeable_init();
            __Ownable_init();
            operatorVCS = IVaultControllerStrategy(_operatorVCS);
            communityVCS = IVaultControllerStrategy(_communityVCS);
            unbondingPeriod = _unbondingPeriod;
            claimPeriod = _claimPeriod;
            numVaultGroups = _numVaultGroups;
            for (uint256 i = 0; i < _numVaultGroups; ++i) {
                timeOfLastUpdateByGroup.push(0);
            }
        }

        linkToken = _linkToken;
        nonLINKRewardReceiver = _nonLINKRewardReceiver;
    }

    /**
     * @notice Returns encoded vault deposit order for each strategy
     * @dev return data should be passed to the priority pool when depositing into the staking pool
     * @param _toDeposit amount to deposit
     * @return list of encoded vault deposit data
     */
    function getDepositData(uint256 _toDeposit) external view returns (bytes[] memory) {
        uint256 toDeposit = 2 * _toDeposit;
        bytes[] memory depositData = new bytes[](2);

        (
            uint64[] memory opVaultDepositOrder,
            uint256 opVaultsTotalToDeposit
        ) = _getVaultDepositOrder(operatorVCS, toDeposit);
        depositData[0] = abi.encode(opVaultDepositOrder);

        if (opVaultsTotalToDeposit < toDeposit) {
            (uint64[] memory comVaultDepositOrder, ) = _getVaultDepositOrder(
                communityVCS,
                toDeposit - opVaultsTotalToDeposit
            );
            depositData[1] = abi.encode(comVaultDepositOrder);
        } else {
            depositData[1] = abi.encode(new uint64[](0));
        }

        return depositData;
    }

    /**
     * @notice Returns encoded vault withdrawal order for each strategy
     * @dev return data should be passed to the priority pool when withdrawing from the staking pool
     * @param _toWithdraw amount to withdraw
     * @return list of encoded vault withdrawal data
     */
    function getWithdrawalData(uint256 _toWithdraw) external view returns (bytes[] memory) {
        uint256 toWithdraw = 2 * _toWithdraw;
        bytes[] memory withdrawalData = new bytes[](2);

        (
            uint64[] memory comVaultWithdrawalOrder,
            uint256 comVaultsTotalToWithdraw
        ) = _getVaultWithdrawalOrder(communityVCS, toWithdraw);
        withdrawalData[1] = abi.encode(comVaultWithdrawalOrder);

        if (comVaultsTotalToWithdraw < toWithdraw) {
            (uint64[] memory opVaultWithdrawalOrder, ) = _getVaultWithdrawalOrder(
                operatorVCS,
                toWithdraw - comVaultsTotalToWithdraw
            );
            withdrawalData[0] = abi.encode(opVaultWithdrawalOrder);
        } else {
            withdrawalData[0] = abi.encode(new uint64[](0));
        }

        return withdrawalData;
    }

    /**
     * @notice Returns whether claim period is active
     * @dev funds can only be withdrawn while the claim period is active
     * @return true of claim period is active, false otherwise
     */
    function claimPeriodActive() external view returns (bool) {
        uint256 claimPeriodStart = timeOfLastUpdateByGroup[curUnbondedVaultGroup] + unbondingPeriod;
        uint256 claimPeriodEnd = claimPeriodStart + claimPeriod;

        return block.timestamp >= claimPeriodStart && block.timestamp <= claimPeriodEnd;
    }

    /**
     * @notice Returns whether vault groups should be updated
     * @return true if vault groups should be updated, false otherwise
     */
    function shouldUpdateVaultGroups() external view returns (bool) {
        uint256 curUnbondedGroup = curUnbondedVaultGroup;
        uint256 nextUnbondedGroup = _getNextGroup(curUnbondedGroup, numVaultGroups);

        // claim period must be concluded for current group
        if (
            timeOfLastUpdateByGroup[nextUnbondedGroup] != 0 &&
            block.timestamp <=
            timeOfLastUpdateByGroup[curUnbondedGroup] + unbondingPeriod + claimPeriod
        ) return false;

        // vault group unbonding must be properly spaced out with a full claim period between each group
        // (only applies to the first cycle through the vault groups)
        if (
            curUnbondedGroup != 0 &&
            timeOfLastUpdateByGroup[curUnbondedGroup] == 0 &&
            block.timestamp <= timeOfLastUpdateByGroup[curUnbondedGroup - 1] + claimPeriod
        ) return false;

        // unbonding period must be concluded for next group
        if (block.timestamp < timeOfLastUpdateByGroup[nextUnbondedGroup] + unbondingPeriod)
            return false;

        return true;
    }

    /**
     * @notice  Executes a vault group update
     * @dev re-unbonds all vaults in the current vault group and increments the current vault group
     * to the next one which will have just entered the claim period
     * @dev an update is needed once per claim period right after the claim period expires for the
     * current vault group
     */
    function updateVaultGroups() external {
        uint256 curUnbondedGroup = curUnbondedVaultGroup;
        uint256 nextUnbondedGroup = _getNextGroup(curUnbondedGroup, numVaultGroups);

        // claim period must be concluded for current group
        if (
            timeOfLastUpdateByGroup[nextUnbondedGroup] != 0 &&
            block.timestamp <=
            timeOfLastUpdateByGroup[curUnbondedGroup] + unbondingPeriod + claimPeriod
        ) revert NoUpdateNeeded();

        // vault group unbonding must be properly spaced out with a full claim period between each group
        // (only applies to the first cycle through the vault groups)
        if (
            curUnbondedGroup != 0 &&
            timeOfLastUpdateByGroup[curUnbondedGroup] == 0 &&
            block.timestamp <= timeOfLastUpdateByGroup[curUnbondedGroup - 1] + claimPeriod
        ) revert NoUpdateNeeded();

        // unbonding period must be concluded for next group
        if (block.timestamp < timeOfLastUpdateByGroup[nextUnbondedGroup] + unbondingPeriod)
            revert NoUpdateNeeded();

        (
            uint256[] memory curGroupOpVaultsToUnbond,
            uint256 curGroupOpVaultsTotalDepositRoom,
            uint256 nextGroupOpVaultsTotalUnbonded
        ) = _getVaultUpdateData(operatorVCS, nextUnbondedGroup);

        (
            uint256[] memory curGroupComVaultsToUnbond,
            uint256 curGroupComVaultsTotalDepositRoom,
            uint256 nextGroupComVaultsTotalUnbonded
        ) = _getVaultUpdateData(communityVCS, nextUnbondedGroup);

        operatorVCS.updateVaultGroups(
            curGroupOpVaultsToUnbond,
            curGroupOpVaultsTotalDepositRoom,
            nextUnbondedGroup,
            nextGroupOpVaultsTotalUnbonded
        );
        communityVCS.updateVaultGroups(
            curGroupComVaultsToUnbond,
            curGroupComVaultsTotalDepositRoom,
            nextUnbondedGroup,
            nextGroupComVaultsTotalUnbonded
        );

        timeOfLastUpdateByGroup[curUnbondedGroup] = uint64(block.timestamp);
        curUnbondedVaultGroup = uint64(nextUnbondedGroup);
    }

    /**
     * @notice Calculates and updates totalDepositRoom and totalUnbonded for a list of operator vault groups
     * @dev used to correct minor accounting errors that result from the removal or slashing
     * of operators in the Chainlink staking contract
     * @param _vaultGroups list of vault groups
     */
    function updateOperatorVaultGroupAccounting(uint256[] calldata _vaultGroups) external {
        address[] memory vaults = operatorVCS.getVaults();
        (, uint256 maxDeposits) = operatorVCS.getVaultDepositLimits();
        (, , , uint64 depositIndex) = operatorVCS.globalVaultState();

        uint256[] memory totalDepositRoom = new uint256[](_vaultGroups.length);
        uint256 totalUnbonded = operatorVCS.totalUnbonded();

        for (uint256 i = 0; i < _vaultGroups.length; ++i) {
            (uint256 depositRoom, ) = _getTotalDepositRoom(
                vaults,
                numVaultGroups,
                _vaultGroups[i],
                maxDeposits,
                depositIndex
            );
            totalDepositRoom[i] = depositRoom;

            if (_vaultGroups[i] == curUnbondedVaultGroup) {
                totalUnbonded = _getTotalUnbonded(
                    vaults,
                    numVaultGroups,
                    _vaultGroups[i],
                    depositIndex
                );
            }
        }

        IOperatorVCS(address(operatorVCS)).updateVaultGroupAccounting(
            _vaultGroups,
            totalDepositRoom,
            totalUnbonded,
            maxDeposits
        );
    }

    /**
     * @notice Delegates to an address for a group of vaults
     * @param _vaults list of vault addresses to delegate for
     * @param _to address to delegate to
     * @param _rights rights to grant
     * @param _enable whether to enable to revoke delegation
     */
    function delegateVaults(
        address[] calldata _vaults,
        address _to,
        bytes32 _rights,
        bool _enable
    ) external onlyOwner {
        for (uint256 i = 0; i < _vaults.length; ++i) {
            IVault(_vaults[i]).delegate(_to, _rights, _enable);
        }
    }

    /**
     * @notice Withdraws non LINK token rewards from a group of vaults
     * @param _vaults list of vault addresses to withdraw from
     * @param _tokens list of tokens to withdraw
     */
    function withdrawTokenRewards(address[] calldata _vaults, address[] calldata _tokens) external {
        for (uint256 i = 0; i < _vaults.length; ++i) {
            IVault(_vaults[i]).withdrawTokenRewards(_tokens);
        }

        for (uint256 i = 0; i < _tokens.length; ++i) {
            IERC20Upgradeable rewardToken = IERC20Upgradeable(_tokens[i]);
            if (address(rewardToken) == linkToken) revert InvalidToken();
            uint256 balance = rewardToken.balanceOf(address(this));
            if (balance != 0) rewardToken.safeTransfer(nonLINKRewardReceiver, balance);
        }
    }

    /**
     * @notice Sets the address of reward receiver for non LINK vault rewards
     * @param _nonLINKRewardReceiver address of reward receiver
     */
    function setNonLINKRewardReceiver(address _nonLINKRewardReceiver) external onlyOwner {
        nonLINKRewardReceiver = _nonLINKRewardReceiver;
    }

    /**
     * @notice Returns the vault deposit order for a strategy
     * @param _vcs strategy
     * @param _toDeposit amount to deposit
     * @return vault deposit order
     * @return total deposit space across returned vaults
     */
    function _getVaultDepositOrder(
        IVaultControllerStrategy _vcs,
        uint256 _toDeposit
    ) internal view returns (uint64[] memory, uint256) {
        address[] memory vaults = _vcs.getVaults();
        if (vaults.length == 0) return (new uint64[](0), 0);

        uint256[] memory depositRoom = new uint256[](numVaultGroups);

        for (uint256 i = 0; i < numVaultGroups; ++i) {
            (, uint256 totalDepositRoom) = _vcs.vaultGroups(i);
            depositRoom[i] = totalDepositRoom;
        }

        (, , uint64 groupDepositIndex, uint64 maxVaultIndex) = _vcs.globalVaultState();
        uint256 maxDeposits = _vcs.vaultMaxDeposits();
        // sort groups in descending order from most deposit room to least deposit room
        uint256[] memory groupDepositOrder = _sortIndexesDescending(depositRoom);

        uint256[] memory vaultDepositOrder = new uint256[](vaults.length);
        uint256 totalVaultsAdded;
        uint256 totalDepositsAdded;

        // deposits continue with the vault they left off at during the previous call regardless of group deposit order
        if (groupDepositIndex < maxVaultIndex) {
            vaultDepositOrder[0] = groupDepositIndex;
            ++totalVaultsAdded;
            (uint256 withdrawalIndex, ) = _vcs.vaultGroups(groupDepositIndex % numVaultGroups);
            uint256 deposits = IVault(vaults[groupDepositIndex]).getPrincipalDeposits();
            if (
                deposits != maxDeposits && (groupDepositIndex != withdrawalIndex || deposits == 0)
            ) {
                totalDepositsAdded += maxDeposits - deposits;
            }
        }

        // iterate through groups in group deposit order filling each vault and group entirely before moving onto the next
        for (uint256 i = 0; i < numVaultGroups; ++i) {
            (uint256 withdrawalIndex, ) = _vcs.vaultGroups(groupDepositOrder[i]);

            for (uint256 j = groupDepositOrder[i]; j < maxVaultIndex; j += numVaultGroups) {
                uint256 deposits = IVault(vaults[j]).getPrincipalDeposits();
                if (j != groupDepositIndex && deposits != maxDeposits) {
                    vaultDepositOrder[totalVaultsAdded] = j;
                    ++totalVaultsAdded;
                    // only count deposit room if withdrawalIndex is not equal to the current vault
                    if (j != withdrawalIndex || deposits == 0)
                        totalDepositsAdded += maxDeposits - deposits;
                    if (totalDepositsAdded >= _toDeposit) break;
                }
            }

            if (totalDepositsAdded >= _toDeposit) break;
        }

        if (totalDepositsAdded == 0) return (new uint64[](0), 0);

        uint64[] memory vaultDepositOrderFormatted = new uint64[](totalVaultsAdded);
        for (uint256 i = 0; i < totalVaultsAdded; ++i) {
            vaultDepositOrderFormatted[i] = uint64(vaultDepositOrder[i]);
        }

        return (vaultDepositOrderFormatted, totalDepositsAdded);
    }

    /**
     * @notice Returns the vaut withdrawal order for a strategy
     * @param _vcs strategy
     * @param _toWithdraw amount to withdraw
     * @return vault withdrawal order
     * @return total withdrawal space across returned vaults
     */
    function _getVaultWithdrawalOrder(
        IVaultControllerStrategy _vcs,
        uint256 _toWithdraw
    ) internal view returns (uint64[] memory, uint256) {
        address[] memory vaults = _vcs.getVaults();
        (, , , uint64 maxVaultIndex) = _vcs.globalVaultState();
        (uint64 withdrawalIndex, ) = _vcs.vaultGroups(curUnbondedVaultGroup);

        uint256[] memory vaultWithdrawalOrder = new uint256[](vaults.length);
        uint256 totalVaultsAdded;
        uint256 totalWithdrawsAdded;

        // withdrawals continue with the vault they left off at during the previous call when the current
        // group was unbonded
        if (withdrawalIndex < maxVaultIndex) {
            vaultWithdrawalOrder[0] = withdrawalIndex;
            ++totalVaultsAdded;
            totalWithdrawsAdded += IVault(vaults[withdrawalIndex]).getPrincipalDeposits();
        }

        // iterate through vaults in the current unbonded group emptying each entirely before moving onto the next
        for (uint256 i = curUnbondedVaultGroup; i < maxVaultIndex; i += numVaultGroups) {
            IVault vault = IVault(vaults[i]);
            uint256 deposits = vault.getPrincipalDeposits();

            if (i != withdrawalIndex && deposits != 0 && vault.claimPeriodActive()) {
                vaultWithdrawalOrder[totalVaultsAdded] = i;
                totalWithdrawsAdded += deposits;
                totalVaultsAdded++;
            }

            if (totalWithdrawsAdded >= _toWithdraw) break;
        }

        if (totalWithdrawsAdded == 0) return (new uint64[](0), 0);

        uint64[] memory vaultWithdrawalOrderFormatted = new uint64[](totalVaultsAdded);
        for (uint256 i = 0; i < totalVaultsAdded; ++i) {
            vaultWithdrawalOrderFormatted[i] = uint64(vaultWithdrawalOrder[i]);
        }

        return (vaultWithdrawalOrderFormatted, totalWithdrawsAdded);
    }

    /**
     * @notice Returns data needed to execute a vault group update for a strategy
     * @param _vcs strategy
     * @param _nextUnbondedVaultGroup index of next unbonded vault group
     * @return list of vaults to unbond in current vault group
     * @return total deposit room across all vaults in current vault group
     * @return total unbonded across all vaults in next vault group
     */
    function _getVaultUpdateData(
        IVaultControllerStrategy _vcs,
        uint256 _nextUnbondedVaultGroup
    ) internal view returns (uint256[] memory, uint256, uint256) {
        address[] memory vaults = _vcs.getVaults();
        (, , , uint64 depositIndex) = _vcs.globalVaultState();

        (
            uint256 curGroupTotalDepositRoom,
            uint256[] memory curGroupVaultsToUnbond
        ) = _getTotalDepositRoom(
                vaults,
                numVaultGroups,
                curUnbondedVaultGroup,
                _vcs.vaultMaxDeposits(),
                depositIndex
            );

        uint256 nextGroupTotalUnbonded = _getTotalUnbonded(
            vaults,
            numVaultGroups,
            _nextUnbondedVaultGroup,
            depositIndex
        );

        return (curGroupVaultsToUnbond, curGroupTotalDepositRoom, nextGroupTotalUnbonded);
    }

    /**
     * @notice Returns the total deposit room and a list of non-empty vaults for a vault group
     * @param _vaults list of all vaults
     * @param _numVaultGroups total number of vault groups
     * @param _vaultGroup index of vault group
     * @param _vaultMaxDeposits max deposits per vault
     * @param _depositIndex global deposit index
     * @return total deposit room
     * @return list of non-empty vaults
     */
    function _getTotalDepositRoom(
        address[] memory _vaults,
        uint256 _numVaultGroups,
        uint256 _vaultGroup,
        uint256 _vaultMaxDeposits,
        uint256 _depositIndex
    ) internal view returns (uint256, uint256[] memory) {
        uint256 totalDepositRoom;
        uint256 numNonEmptyVaults;
        uint256[] memory nonEmptyVaults = new uint256[](_vaults.length);

        for (uint256 i = _vaultGroup; i < _depositIndex; i += _numVaultGroups) {
            if (IVault(_vaults[i]).isRemoved()) continue;

            uint256 principalDeposits = IVault(_vaults[i]).getPrincipalDeposits();
            totalDepositRoom += _vaultMaxDeposits - principalDeposits;
            if (principalDeposits != 0) {
                nonEmptyVaults[numNonEmptyVaults] = i;
                numNonEmptyVaults++;
            }
        }

        uint256[] memory nonEmptyVaultsFormatted = new uint256[](numNonEmptyVaults);
        for (uint256 i = 0; i < numNonEmptyVaults; ++i) {
            nonEmptyVaultsFormatted[i] = nonEmptyVaults[i];
        }

        return (totalDepositRoom, nonEmptyVaultsFormatted);
    }

    /**
     * @notice Returns the total amount currently unbonded for a vault group
     * @param _vaults list of all vaults
     * @param _numVaultGroups total number of vault groups
     * @param _vaultGroup index of vault group
     * @param _depositIndex global deposit index
     * @return total unbonded
     */
    function _getTotalUnbonded(
        address[] memory _vaults,
        uint256 _numVaultGroups,
        uint256 _vaultGroup,
        uint256 _depositIndex
    ) internal view returns (uint256) {
        uint256 totalUnbonded;

        for (uint256 i = _vaultGroup; i < _depositIndex; i += _numVaultGroups) {
            if (!IVault(_vaults[i]).claimPeriodActive() || IVault(_vaults[i]).isRemoved()) continue;

            totalUnbonded += IVault(_vaults[i]).getPrincipalDeposits();
        }

        return totalUnbonded;
    }

    /**
     * @notice Returns the index of the next vault group
     * @param _curGroup index of current vault group
     * @param _numGroups total number of vault groups
     */
    function _getNextGroup(uint256 _curGroup, uint256 _numGroups) internal pure returns (uint256) {
        return _curGroup == _numGroups - 1 ? 0 : _curGroup + 1;
    }

    /**
     * @notice Sorts a list of values in descending order and returns the correspodning list of indexes
     * sorted in the same order
     * @param _values list of values
     * @return sorted list of indexes
     */
    function _sortIndexesDescending(
        uint256[] memory _values
    ) internal pure returns (uint256[] memory) {
        uint256 n = _values.length;

        uint256[] memory indexes = new uint256[](n);
        for (uint256 i = 0; i < n; ++i) {
            indexes[i] = i;
        }

        for (uint256 i = 0; i < n - 1; ++i) {
            for (uint256 j = 0; j < n - i - 1; ++j) {
                if (_values[j] < _values[j + 1]) {
                    (_values[j], _values[j + 1]) = (_values[j + 1], _values[j]);
                    (indexes[j], indexes[j + 1]) = (indexes[j + 1], indexes[j]);
                }
            }
        }

        return indexes;
    }

    /**
     * @dev Checks authorization for contract upgrades
     */
    function _authorizeUpgrade(address) internal override onlyOwner {}
}
