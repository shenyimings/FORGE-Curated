// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

import { AccessControlUpgradeable } from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {
    ReentrancyGuardTransientUpgradeable
} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardTransientUpgradeable.sol";

import { IChainlinkAggregatorLike } from "../interfaces/IChainlinkAggregatorLike.sol";
import { ISwapper } from "../interfaces/ISwapper.sol";
import { IYieldDistributor } from "../interfaces/IYieldDistributor.sol";
import { IGenericShare } from "../interfaces/IGenericShare.sol";

/**
 * @title BaseController
 * @notice Base contract for controller implementations that provides common functionality
 * @dev This contract is designed to be deployed as an upgradeable proxy. Any future upgrades
 * MUST strictly adhere to the existing storage layout to prevent storage collisions.
 *
 * CRITICAL STORAGE LAYOUT REQUIREMENTS:
 * - Never change the order of existing state variables
 * - Never change the type of existing state variables
 * - Never remove existing state variables
 * - Only append new state variables at the end
 * - Be aware of storage packing when adding new variables
 * - Consider using storage gaps for future extensibility
 *
 * Violating these rules will corrupt the proxy's storage and may lead to:
 * - Loss of funds
 * - Incorrect contract behavior
 * - Permanent contract malfunction
 */
abstract contract BaseController is AccessControlUpgradeable, ReentrancyGuardTransientUpgradeable {
    /**
     * @notice Maximum basis points value representing 100%
     */
    uint256 public constant MAX_BPS = 10_000;

    /**
     * @notice Indicates whether the protocol is currently paused
     * @dev When true, prevents certain operations like deposits and withdrawals
     */
    bool public paused;

    /**
     * @notice Flag to skip the safety buffer check during the next rebalance operation
     * @dev This is a temporary override to allow emergency rebalancing even if the safety buffer condition is not met
     */
    bool public skipNextRebalanceSafetyBufferCheck;

    /**
     * @notice Share token contract for controlled vaults
     * @dev Manages the issuance and burning of share tokens representing ownership stakes in controlled vaults
     */
    IGenericShare internal _share;

    /**
     * @notice Configuration structure for asset price feeds
     * @dev Encapsulates the oracle feed and its staleness parameters
     * @param feed The Chainlink-compatible price feed aggregator interface
     * @param heartbeat Maximum time in seconds between price updates before data is considered stale
     */
    struct PriceFeed {
        IChainlinkAggregatorLike feed;
        uint24 heartbeat;
    }

    /**
     * @notice Mapping of asset addresses to their configured price feeds
     * @dev Each asset is assumed to have a corresponding {asset}/USD price feed
     */
    mapping(address asset => PriceFeed) public priceFeeds;

    /**
     * @notice Configuration parameters for individual vaults
     * @dev Defines operational limits and risk parameters for vault management
     * @param maxCapacity Maximum total value that can be deposited into the vault (in asset units)
     * @param minProportionality Minimum proportion of total protocol assets this vault should maintain (in basis
     * points)
     * @param maxProportionality Maximum proportion of total protocol assets this vault can hold (in basis points)
     */
    struct VaultSettings {
        uint224 maxCapacity;
        uint16 minProportionality;
        uint16 maxProportionality;
    }

    /**
     * @notice Mapping of vault addresses to their configuration settings
     * @dev Stores operational parameters for each registered vault including capacity and proportionality limits
     */
    mapping(address vault => VaultSettings) public vaultSettings;

    /**
     * @notice Mapping of asset addresses to their designated main vaults
     */
    mapping(address asset => address) internal _vaultFor;

    /**
     * @notice Linked list implementation for efficient vault management
     * @dev Structure: SENTINEL_VAULTS -> Vault1 -> Vault2 -> ... -> SENTINEL_VAULTS
     */
    mapping(address vault => address nextVault) internal _vaults;

    /**
     * @notice Total number of vaults currently registered in the system
     * @dev Maintained separately for efficient count queries without requiring linked list traversal
     */
    uint8 internal _vaultsCount;

    /**
     * @notice Maximum allowable slippage during protocol-level rebalancing operations (in basis points)
     * @dev This slippage threshold applies to the entire backing value of the protocol, not just the
     * individual rebalancing amounts. It serves as a safety mechanism to prevent excessive value
     * loss during rebalancing activities across all protocol assets.
     */
    uint16 public maxProtocolRebalanceSlippage;

    /**
     * @notice Address that collects rewards generated from yield optimization strategies
     * @dev Rewards collected here can be reinvested or distributed as per protocol governance decisions.
     */
    address public rewardsCollector;

    /**
     * @notice Mapping of token addresses to their approval status as reward tokens
     * @dev When true, indicates the token is allowed to be transferred from vaults as rewards
     */
    mapping(address => bool) public isRewardAsset;

    /**
     * @notice Token swapping component for rebalancing operations
     * @dev Used to execute token swaps for rebalancing and yield optimization operations
     */
    ISwapper internal _swapper;

    /**
     * @notice Yield distribution manager for protocol earnings
     * @dev Handles the distribution of generated yields to appropriate recipients and fee collection
     */
    IYieldDistributor internal _yieldDistributor;

    /**
     * @notice The absolute amount deducted from yield distributions as a safety buffer
     * @dev This value is subtracted from the total yield before distribution to users
     * to maintain protocol stability and cover potential losses or unexpected events.
     * The deduction helps ensure the protocol remains solvent during volatile market conditions.
     */
    uint256 public safetyBufferYieldDeduction;

    /**
     * @notice Reserved storage space to allow for layout changes in the future.
     */
    uint256[50] private __gap;
}
