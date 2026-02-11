// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.22;

import "./base/VaultControllerStrategy.sol";
import "./interfaces/ICommunityVault.sol";

/**
 * @title Community Vault Controller Strategy
 * @notice Implemented strategy for managing multiple Chainlink community staking vaults
 */
contract CommunityVCS is VaultControllerStrategy {
    // min number of non-full vaults before a new batch is deployed
    uint128 public vaultDeploymentThreshold;
    // number of vaults to deploy when threshold is met
    uint128 public vaultDeploymentAmount;

    event SetVaultDeploymentParams(uint128 vaultDeploymentThreshold, uint128 vaultDeploymentAmount);

    error VaultsAboveThreshold();

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
     * @param _vaultDeploymentThreshold min number of non-full vaults before a new batch is deployed
     * @param _vaultDeploymentAmount number of vaults to deploy when threshold is met
     * @param _vaultDepositController address of vault deposit controller
     *
     */
    function initialize(
        address _token,
        address _stakingPool,
        address _stakeController,
        address _vaultImplementation,
        Fee[] memory _fees,
        uint256 _maxDepositSizeBP,
        uint256 _vaultMaxDeposits,
        uint128 _vaultDeploymentThreshold,
        uint128 _vaultDeploymentAmount,
        address _vaultDepositController
    ) public reinitializer(2) {
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
            vaultDeploymentThreshold = _vaultDeploymentThreshold;
            vaultDeploymentAmount = _vaultDeploymentAmount;
            _deployVaults(_vaultDeploymentAmount);
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
     * @notice Deposits tokens from the staking pool into vaults
     * @param _amount amount to deposit
     * @param _data encoded vault deposit order
     */
    function deposit(uint256 _amount, bytes calldata _data) external override onlyStakingPool {
        (, uint256 maxDeposits) = getVaultDepositLimits();

        // if vault deposit limit has changed in Chainlink staking contract, make adjustments
        if (maxDeposits > vaultMaxDeposits) {
            uint256 diff = maxDeposits - vaultMaxDeposits;
            uint256 totalVaults = globalVaultState.depositIndex;
            uint256 numVaultGroups = globalVaultState.numVaultGroups;
            uint256 vaultsPerGroup = totalVaults / numVaultGroups;
            uint256 remainder = totalVaults % numVaultGroups;

            for (uint256 i = 0; i < numVaultGroups; ++i) {
                uint256 numVaults = vaultsPerGroup;
                if (i < remainder) {
                    numVaults += 1;
                }

                vaultGroups[i].totalDepositRoom += uint128(numVaults * diff);
            }

            vaultMaxDeposits = maxDeposits;
        }

        if (vaultDepositController == address(0)) revert VaultDepositControllerNotSet();

        (bool success, ) = vaultDepositController.delegatecall(
            abi.encodeWithSelector(VaultDepositController.deposit.selector, _amount, _data)
        );

        if (!success) revert DepositFailed();
    }

    /**
     * @notice Claims Chanlink staking rewards from vaults
     * @param _vaults list if vault indexes to claim from
     * @param _minRewards min amount of rewards per vault required to claim
     */
    function claimRewards(
        uint256[] calldata _vaults,
        uint256 _minRewards
    ) external returns (uint256) {
        address receiver = address(this);
        uint256 balanceBefore = token.balanceOf(address(this));
        for (uint256 i = 0; i < _vaults.length; ++i) {
            ICommunityVault(address(vaults[_vaults[i]])).claimRewards(_minRewards, receiver);
        }
        uint256 balanceAfter = token.balanceOf(address(this));
        return balanceAfter - balanceBefore;
    }

    /**
     * @notice Returns the maximum amount of tokens this strategy can hold
     * @return maximum deposits
     */
    function getMaxDeposits() public view virtual override returns (uint256) {
        return stakeController.getMerkleRoot() == bytes32(0) ? super.getMaxDeposits() : 0;
    }

    /**
     * @notice Returns whether a new batch of vaults should be deployed
     * @return true if new batch should be deployed, false otherwise
     */
    function checkUpkeep(bytes calldata) external view returns (bool, bytes memory) {
        return (
            (vaults.length - globalVaultState.depositIndex) < vaultDeploymentThreshold,
            bytes("")
        );
    }

    /**
     * @notice Deploys a new batch of vaults
     */
    function performUpkeep(bytes calldata) external {
        if ((vaults.length - globalVaultState.depositIndex) >= vaultDeploymentThreshold)
            revert VaultsAboveThreshold();
        _deployVaults(vaultDeploymentAmount);
    }

    /**
     * @notice Deploys a new batch of vaults
     * @param _numVaults number of vaults to deploy
     */
    function addVaults(uint256 _numVaults) external onlyOwner {
        _deployVaults(_numVaults);
    }

    /**
     * @notice Sets the vault deployment parameters
     * @param _vaultDeploymentThreshold the min number of non-full vaults before a new batch is deployed
     * @param _vaultDeploymentAmount amount of vaults to deploy when threshold is met
     */
    function setVaultDeploymentParams(
        uint128 _vaultDeploymentThreshold,
        uint128 _vaultDeploymentAmount
    ) external onlyOwner {
        vaultDeploymentThreshold = _vaultDeploymentThreshold;
        vaultDeploymentAmount = _vaultDeploymentAmount;
        emit SetVaultDeploymentParams(_vaultDeploymentThreshold, _vaultDeploymentAmount);
    }

    /**
     * @notice Deploys new vaults
     * @param _numVaults number of vaults to deploy
     */
    function _deployVaults(uint256 _numVaults) internal {
        bytes memory data = abi.encodeWithSignature(
            "initialize(address,address,address,address,address)",
            address(token),
            address(this),
            address(stakeController),
            stakeController.getRewardVault(),
            delegateRegistry
        );
        for (uint256 i = 0; i < _numVaults; i++) {
            _deployVault(data);
        }
    }
}
