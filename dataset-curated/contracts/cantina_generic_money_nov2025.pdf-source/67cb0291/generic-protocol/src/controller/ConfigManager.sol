// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

import { BaseController } from "./BaseController.sol";

/**
 * @title ConfigManager
 * @notice Abstract contract for managing controller configuration settings such safety buffers and rewards
 * @dev Inherits from BaseController and provides role-based configuration management functionality
 */
abstract contract ConfigManager is BaseController {
    /**
     *  @notice Role identifier for addresses authorized to manage controller configuration
     */
    bytes32 public constant CONFIG_MANAGER_ROLE = keccak256("CONFIG_MANAGER_ROLE");

    /**
     * @notice Emitted when the rewards collector address is updated
     */
    event RewardsCollectorUpdated(address indexed oldRewardsCollector, address indexed newRewardsCollector);
    /**
     * @notice Emitted when a reward asset is added or removed
     */
    event RewardAssetUpdated(address indexed asset, bool isReward);
    /**
     * @notice Emitted when the safety buffer yield deduction is updated
     */
    event SafetyBufferYieldDeductionUpdated(uint256 oldBuffer, uint256 newBuffer);
    /**
     * @notice Emitted when the maximum protocol rebalance slippage is updated
     */
    event MaxProtocolRebalanceSlippageUpdated(uint256 oldMaxSlippage, uint256 newMaxSlippage);

    /**
     * @notice Thrown when attempting to set the rewards collector to the zero address
     */
    error Config_RewardsCollectorZeroAddress();
    /**
     * @notice Thrown when attempting to set a reward asset to the zero address
     */
    error Config_RewardAssetZeroAddress();
    /**
     * @notice Thrown when attempting to set a max slippage that exceeds the maximum allowed
     */
    error Config_InvalidMaxSlippage();

    /**
     * @notice Internal initializer for the ConfigManager contract
     * @dev This function is called during contract initialization and is marked as onlyInitializing
     * to ensure it can only be called once during the initialization process
     */
    // forge-lint: disable-next-line(mixed-case-function)
    function __ConfigManager_init(address rewardsCollector_) internal onlyInitializing {
        require(rewardsCollector_ != address(0), Config_RewardsCollectorZeroAddress());
        rewardsCollector = rewardsCollector_;
    }

    /**
     * @notice Updates the address that receives rewards from yield optimization
     * @dev Only callable by addresses with CONFIG_MANAGER_ROLE
     * @param newRewardsCollector The new address to receive rewards
     */
    function setRewardsCollector(address newRewardsCollector) external onlyRole(CONFIG_MANAGER_ROLE) {
        require(newRewardsCollector != address(0), Config_RewardsCollectorZeroAddress());
        emit RewardsCollectorUpdated(rewardsCollector, newRewardsCollector);
        rewardsCollector = newRewardsCollector;
    }

    /**
     * @notice Adds or removes a token as an approved reward asset
     * @dev Only callable by addresses with CONFIG_MANAGER_ROLE
     * @param asset The address of the token to add or remove as a reward asset
     * @param isReward True to add as a reward asset, false to remove
     */
    function setRewardAsset(address asset, bool isReward) external onlyRole(CONFIG_MANAGER_ROLE) {
        require(asset != address(0), Config_RewardAssetZeroAddress());
        emit RewardAssetUpdated(asset, isReward);
        isRewardAsset[asset] = isReward;
    }

    /**
     * @notice Updates the safety buffer to a new value
     * @dev Only addresses with CONFIG_MANAGER_ROLE can call this function
     * @param newSafetyBufferYieldDeduction The new safety buffer amount to set
     */
    function setSafetyBufferYieldDeduction(uint256 newSafetyBufferYieldDeduction)
        external
        onlyRole(CONFIG_MANAGER_ROLE)
    {
        emit SafetyBufferYieldDeductionUpdated(safetyBufferYieldDeduction, newSafetyBufferYieldDeduction);
        safetyBufferYieldDeduction = newSafetyBufferYieldDeduction;
    }

    /**
     * @notice Updates the maximum allowable protocol rebalance slippage
     * @dev Only addresses with CONFIG_MANAGER_ROLE can call this function
     * @param newMaxSlippage The new maximum slippage in basis points (e.g., 100 = 1%)
     */
    function setMaxProtocolRebalanceSlippage(uint256 newMaxSlippage) external onlyRole(CONFIG_MANAGER_ROLE) {
        require(newMaxSlippage <= MAX_BPS, Config_InvalidMaxSlippage());
        emit MaxProtocolRebalanceSlippageUpdated(maxProtocolRebalanceSlippage, newMaxSlippage);
        // casting to 'uint16' is safe because 'newMaxSlippage' is guaranteed to be less than or equal to 'MAX_BPS'
        // forge-lint: disable-next-line(unsafe-typecast)
        maxProtocolRebalanceSlippage = uint16(newMaxSlippage);
    }
}
