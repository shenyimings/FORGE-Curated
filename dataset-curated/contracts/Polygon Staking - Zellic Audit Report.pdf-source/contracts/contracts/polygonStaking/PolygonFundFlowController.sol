// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.22;

import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import "../core/interfaces/IWithdrawalPool.sol";
import "./interfaces/IPolygonStrategy.sol";
import "./interfaces/IPolygonVault.sol";

/**
 * @title Polygon Fund Flow Controller
 * @notice Manages deposits and withdrawals for Polygon staking vaults
 */
contract PolygonFundFlowController is UUPSUpgradeable, OwnableUpgradeable {
    // address of staking strategy
    IPolygonStrategy public strategy;
    // address of withdrawal pool
    IWithdrawalPool public withdrawalPool;

    // address authorized to deposit queued tokens into vaults
    address public depositController;

    // min number of seconds between unbonding calls
    uint64 public minTimeBetweenUnbonding;
    // time of last unbonding call
    uint64 public timeOfLastUnbond;

    event SetMinTimeBetweenUnbonding(uint64 minTimeBetweenUnbonding);

    error SenderNotAuthorized();
    error NoUnbondingNeeded();
    error InvalidAddress();

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initializes contract
     * @param _strategy address of staking strategy
     * @param _withdrawalPool address of withdrawal pool
     * @param _depositController address authorized to deposit queued tokens into vaults
     * @param _minTimeBetweenUnbonding min number of seconds between unbonding calls
     **/
    function initialize(
        address _strategy,
        address _withdrawalPool,
        address _depositController,
        uint64 _minTimeBetweenUnbonding
    ) public initializer {
        __UUPSUpgradeable_init();
        __Ownable_init();
        strategy = IPolygonStrategy(_strategy);
        withdrawalPool = IWithdrawalPool(_withdrawalPool);
        depositController = _depositController;
        minTimeBetweenUnbonding = _minTimeBetweenUnbonding;
    }

    /**
     * @notice Reverts if sender is not deposit controller
     */
    modifier onlyDepositController() {
        if (msg.sender != depositController) revert SenderNotAuthorized();
        _;
    }

    /**
     * @notice Returns whether tokens can be deposited
     * @return true if tokens can be deposited, false otherwise
     */
    function canDepositQueuedTokens() external view returns (bool) {
        return strategy.numVaultsUnbonding() == 0;
    }

    /**
     * @notice Deposits queued tokens into vaults
     * @param _vaultIds list of vaults to deposit into
     * @param _amounts list of amounts to deposit into each respective vault
     */
    function depositQueuedTokens(
        uint256[] calldata _vaultIds,
        uint256[] calldata _amounts
    ) external onlyDepositController {
        strategy.depositQueuedTokens(_vaultIds, _amounts);
    }

    /**
     * @notice Returns whether vaults should be unbonded
     * @return true if vaults should be unbonded, false otherwise
     */
    function shouldUnbondVaults() external view returns (bool) {
        uint256 queuedWithdrawals = withdrawalPool.getTotalQueuedWithdrawals();
        uint256 queuedDeposits = strategy.totalQueued();
        (, , uint256 validatorRemovalDeposits) = strategy.validatorRemoval();

        if (
            strategy.numVaultsUnbonding() != 0 ||
            block.timestamp < (timeOfLastUnbond + minTimeBetweenUnbonding) ||
            queuedWithdrawals <= (queuedDeposits + validatorRemovalDeposits)
        ) return false;

        return true;
    }

    /**
     * @notice Unbonds vaults
     */
    function unbondVaults() external {
        uint256 queuedWithdrawals = withdrawalPool.getTotalQueuedWithdrawals();
        uint256 queuedDeposits = strategy.totalQueued();
        (, , uint256 validatorRemovalDeposits) = strategy.validatorRemoval();

        if (
            strategy.numVaultsUnbonding() != 0 ||
            block.timestamp < (timeOfLastUnbond + minTimeBetweenUnbonding) ||
            queuedWithdrawals <= (queuedDeposits + validatorRemovalDeposits)
        ) revert NoUnbondingNeeded();

        uint256 toWithdraw = queuedWithdrawals - (queuedDeposits + validatorRemovalDeposits);
        strategy.unbond(toWithdraw);
        timeOfLastUnbond = uint64(block.timestamp);
    }

    /**
     * @notice Unbonds vaults
     * @dev used to rebalance deposits between vaults if necessary
     * @param _vaultIds list of vaults to unbond
     * @param _amounts list of amounts to unbond
     */
    function forceUnbondVaults(
        uint256[] calldata _vaultIds,
        uint256[] calldata _amounts
    ) external onlyDepositController {
        strategy.forceUnbond(_vaultIds, _amounts);
    }

    /**
     * @notice Returns whether vaults are unbonded and ready to be withdrawn from
     * @return true if vaults are ready for withdrawal, false otherwise
     * @return list of withdrawable vaults
     */
    function shouldWithdrawVaults() external view returns (bool, uint256[] memory) {
        uint256[] memory vaults = getWithdrawableVaults();
        return (vaults.length != 0, vaults);
    }

    /**
     * @notice Withdraws from vaults
     * @param _vaultIds list of vaults to withdraw from
     */
    function withdrawVaults(uint256[] calldata _vaultIds) external {
        strategy.unstakeClaim(_vaultIds);

        (bool upkeepNeeded, ) = withdrawalPool.checkUpkeep("");

        if (upkeepNeeded) {
            withdrawalPool.performUpkeep("");
        }
    }

    /**
     * @notice Restakes vault rewards
     * @param _vaultIds list of vaults to restake rewards for
     */
    function restakeRewards(uint256[] calldata _vaultIds) external {
        strategy.restakeRewards(_vaultIds);
    }

    /**
     * @notice Returns a list of total deposits for all vaults
     * @return list of deposit amounts
     */
    function getVaultDeposits() external view returns (uint256[] memory) {
        address[] memory vaults = strategy.getVaults();
        uint256[] memory deposits = new uint256[](vaults.length);

        for (uint256 i = 0; i < vaults.length; ++i) {
            deposits[i] = IPolygonVault(vaults[i]).getTotalDeposits();
        }

        return deposits;
    }

    /**
     * @notice Returns a list of unclaimed rewards for all vaults
     * @return list of reward amounts
     */
    function getVaultRewards() external view returns (uint256[] memory) {
        address[] memory vaults = strategy.getVaults();
        uint256[] memory rewards = new uint256[](vaults.length);

        for (uint256 i = 0; i < vaults.length; ++i) {
            rewards[i] = IPolygonVault(vaults[i]).getRewards();
        }

        return rewards;
    }

    /**
     * @notice Returns a list of currently unbonding vaults
     * @dev excludes vaults that are queued for removal
     * @return list of vaults
     */
    function getUnbondingVaults() external view returns (uint256[] memory) {
        address[] memory vaults = strategy.getVaults();
        bool[] memory vaultsUnbonding = new bool[](vaults.length);

        (bool isActive, uint256 validatorId, ) = strategy.validatorRemoval();
        uint256 skipIndex = isActive ? validatorId : type(uint256).max;
        uint256 numVaultsUnbonding;

        for (uint256 i = 0; i < vaults.length; ++i) {
            if (IPolygonVault(vaults[i]).isUnbonding() && i != skipIndex) {
                vaultsUnbonding[i] = true;
                ++numVaultsUnbonding;
            }
        }

        uint256[] memory ret = new uint256[](numVaultsUnbonding);
        uint256 numAdded;

        for (uint256 i = 0; i < vaultsUnbonding.length; ++i) {
            if (vaultsUnbonding[i]) {
                ret[numAdded] = i;
                ++numAdded;
            }
        }

        return ret;
    }

    /**
     * @notice Returns a list of currently withdrawable vaults
     * @dev excludes vaults that are queued for removal
     * @return list of vaults
     */
    function getWithdrawableVaults() public view returns (uint256[] memory) {
        address[] memory vaults = strategy.getVaults();
        bool[] memory vaultsWithdrawable = new bool[](vaults.length);

        (bool isActive, uint256 validatorId, ) = strategy.validatorRemoval();
        uint256 skipIndex = isActive ? validatorId : type(uint256).max;
        uint256 numVaultsWithdrawable;

        for (uint256 i = 0; i < vaults.length; ++i) {
            if (IPolygonVault(vaults[i]).isWithdrawable() && i != skipIndex) {
                vaultsWithdrawable[i] = true;
                ++numVaultsWithdrawable;
            }
        }

        uint256[] memory ret = new uint256[](numVaultsWithdrawable);
        uint256 numAdded;

        for (uint256 i = 0; i < vaultsWithdrawable.length; ++i) {
            if (vaultsWithdrawable[i]) {
                ret[numAdded] = i;
                ++numAdded;
            }
        }

        return ret;
    }

    /**
     * @notice Sets the address authorized to deposit queued tokens
     * @param _depositController address of deposit controller
     */
    function setDepositController(address _depositController) external onlyOwner {
        if (_depositController == address(0)) revert InvalidAddress();
        depositController = _depositController;
    }

    /**
     * @notice Sets the min time between unbonding
     * @param _minTimeBetweenUnbonding min time in seconds
     */
    function setMinTimeBetweenUnbonding(uint64 _minTimeBetweenUnbonding) external onlyOwner {
        minTimeBetweenUnbonding = _minTimeBetweenUnbonding;
        emit SetMinTimeBetweenUnbonding(_minTimeBetweenUnbonding);
    }

    /**
     * @dev Checks authorization for contract upgrades
     */
    function _authorizeUpgrade(address) internal override onlyOwner {}
}
