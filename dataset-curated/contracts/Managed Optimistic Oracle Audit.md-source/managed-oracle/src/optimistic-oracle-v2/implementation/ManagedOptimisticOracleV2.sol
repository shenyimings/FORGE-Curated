// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import {AccessControlDefaultAdminRulesUpgradeable} from
    "@openzeppelin/contracts-upgradeable/access/extensions/AccessControlDefaultAdminRulesUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import {DisableableAddressWhitelistInterface} from "../../common/interfaces/DisableableAddressWhitelistInterface.sol";
import {MultiCaller} from "../../common/implementation/MultiCaller.sol";

import {OptimisticOracleV2} from "./OptimisticOracleV2.sol";

/**
 * @title Events emitted by the ManagedOptimisticOracleV2 contract.
 * @notice Contains events for request manager management, bond and liveness updates, and whitelists.
 */
abstract contract ManagedOptimisticOracleV2Events {
    event RequestManagerAdded(address indexed requestManager);
    event RequestManagerRemoved(address indexed requestManager);
    event MaximumBondUpdated(IERC20 indexed currency, uint256 newMaximumBond);
    event MinimumLivenessUpdated(uint256 newMinimumLiveness);
    event DefaultProposerWhitelistUpdated(address indexed newWhitelist);
    event RequesterWhitelistUpdated(address indexed newWhitelist);
    event CustomBondSet(
        bytes32 indexed managedRequestId,
        address requester,
        bytes32 indexed identifier,
        bytes ancillaryData,
        IERC20 indexed currency,
        uint256 bond
    );
    event CustomLivenessSet(
        bytes32 indexed managedRequestId,
        address indexed requester,
        bytes32 indexed identifier,
        bytes ancillaryData,
        uint256 customLiveness
    );
    event CustomProposerWhitelistSet(
        bytes32 indexed managedRequestId,
        address requester,
        bytes32 indexed identifier,
        bytes ancillaryData,
        address indexed newWhitelist
    );
}

/**
 * @title Managed Optimistic Oracle V2.
 * @notice Pre-DVM escalation contract that allows faster settlement and management of price requests.
 */
contract ManagedOptimisticOracleV2 is
    UUPSUpgradeable,
    ManagedOptimisticOracleV2Events,
    OptimisticOracleV2,
    AccessControlDefaultAdminRulesUpgradeable,
    MultiCaller
{
    struct MaximumBond {
        IERC20 currency;
        uint256 amount;
    }

    struct CustomBond {
        uint256 amount;
        bool isSet;
    }

    struct CustomLiveness {
        uint256 liveness;
        bool isSet;
    }

    struct InitializeParams {
        uint256 liveness; // default liveness applied to each price request.
        address finderAddress; // finder to use to get addresses of DVM contracts.
        address timerAddress; // address of the timer contract. Should be 0x0 in prod.
        address defaultProposerWhitelist; // address of the default whitelist.
        address requesterWhitelist; // address of the requester whitelist.
        MaximumBond[] maximumBonds; // array of maximum bonds for different currencies.
        uint256 minimumLiveness; // minimum liveness that can be overridden for a request.
        address regularAdmin; // regular admin, which is used for managing request managers and contract parameters.
        address upgradeAdmin; // contract upgrade admin, which also can manage the regular admin role.
    }

    // Regular admin role is used to manage request managers and set other default parameters.
    bytes32 public constant REGULAR_ADMIN = keccak256("REGULAR_ADMIN");

    // Request manager role is used to manage proposer whitelists, bonds, and liveness for individual requests.
    bytes32 public constant REQUEST_MANAGER = keccak256("REQUEST_MANAGER");

    // Default whitelist for proposers.
    DisableableAddressWhitelistInterface public defaultProposerWhitelist;
    DisableableAddressWhitelistInterface public requesterWhitelist;

    // Custom bonds set by request managers for specific request and currency combinations.
    mapping(bytes32 => mapping(IERC20 => CustomBond)) public customBonds;

    // Custom liveness values set by request managers for specific requests.
    mapping(bytes32 => CustomLiveness) public customLivenessValues;

    // Custom proposer whitelists set by request managers for specific requests.
    mapping(bytes32 => DisableableAddressWhitelistInterface) public customProposerWhitelists;

    // Admin controlled bounds limiting the changes that can be made by request managers.
    mapping(IERC20 => uint256) public maximumBonds; // Maximum bonds for a given currency.
    uint256 public minimumLiveness;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initializer.
     * @param params Initialization parameters, see InitializeParams struct for details.
     * @dev Struct parameter is used to overcome the stack too deep limitations in Solidity.
     */
    function initialize(InitializeParams calldata params) external initializer {
        __OptimisticOracleV2_init(params.liveness, params.finderAddress, params.timerAddress);
        __AccessControlDefaultAdminRules_init(3 days, params.upgradeAdmin); // Initialize DEFAULT_ADMIN_ROLE

        // Regular admin is managing the request manager role.
        // Contract upgrade admin retains the default admin role that can also manage the regular admin role.
        _grantRole(REGULAR_ADMIN, params.regularAdmin);
        _setRoleAdmin(REQUEST_MANAGER, REGULAR_ADMIN);

        _setDefaultProposerWhitelist(params.defaultProposerWhitelist);
        _setRequesterWhitelist(params.requesterWhitelist);
        for (uint256 i = 0; i < params.maximumBonds.length; i++) {
            _setMaximumBond(params.maximumBonds[i].currency, params.maximumBonds[i].amount);
        }
        _setMinimumLiveness(params.minimumLiveness);
    }

    /**
     * @dev Throws if called by any account other than the upgrade admin.
     */
    modifier onlyUpgradeAdmin() {
        _checkRole(DEFAULT_ADMIN_ROLE);
        _;
    }

    /**
     * @dev Throws if called by any account other than the regular admin.
     */
    modifier onlyRegularAdmin() {
        _checkRole(REGULAR_ADMIN);
        _;
    }

    /**
     * @dev Throws if called by any account other than the request manager.
     */
    modifier onlyRequestManager() {
        _checkRole(REQUEST_MANAGER);
        _;
    }

    /**
     * @notice Authorizes the upgrade of the contract.
     * @dev This is required for UUPSUpgradeable. Only the upgrade admin can authorize upgrades.
     * @param newImplementation address of the new implementation to upgrade to.
     */
    function _authorizeUpgrade(address newImplementation)
        internal
        override(OptimisticOracleV2, UUPSUpgradeable)
        onlyUpgradeAdmin
    {}

    /**
     * @notice Adds a request manager.
     * @dev Only callable by the regular admin (checked in grantRole of AccessControlUpgradeable).
     * @param requestManager address of the request manager to set.
     */
    function addRequestManager(address requestManager) external nonReentrant {
        grantRole(REQUEST_MANAGER, requestManager);
        emit RequestManagerAdded(requestManager);
    }

    /**
     * @notice Removes a request manager.
     * @dev Only callable by the regular admin (checked in revokeRole of AccessControlUpgradeable).
     * @param requestManager address of the request manager to remove.
     */
    function removeRequestManager(address requestManager) external nonReentrant {
        revokeRole(REQUEST_MANAGER, requestManager);
        emit RequestManagerRemoved(requestManager);
    }

    /**
     * @notice Sets the maximum bond that can be set for a request.
     * @dev This can be used to limit the bond amount that can be set by request managers, callable by the regular admin.
     * @param currency the ERC20 token used for bonding proposals and disputes. Must be approved for use with the DVM.
     * @param maximumBond new maximum bond amount.
     */
    function setMaximumBond(IERC20 currency, uint256 maximumBond) external nonReentrant onlyRegularAdmin {
        _setMaximumBond(currency, maximumBond);
    }

    /**
     * @notice Sets the minimum liveness that can be set for a request.
     * @dev This can be used to limit the liveness period that can be set by request managers, callable by the regular admin.
     * @param _minimumLiveness new minimum liveness period.
     */
    function setMinimumLiveness(uint256 _minimumLiveness) external nonReentrant onlyRegularAdmin {
        _setMinimumLiveness(_minimumLiveness);
    }

    /**
     * @notice Sets the default proposer whitelist.
     * @dev Only callable by the regular admin.
     * @param whitelist address of the whitelist to set.
     */
    function setDefaultProposerWhitelist(address whitelist) external nonReentrant onlyRegularAdmin {
        _setDefaultProposerWhitelist(whitelist);
    }

    /**
     * @notice Sets the requester whitelist.
     * @dev Only callable by the regular admin.
     * @param whitelist address of the whitelist to set.
     */
    function setRequesterWhitelist(address whitelist) external nonReentrant onlyRegularAdmin {
        _setRequesterWhitelist(whitelist);
    }

    /**
     * @notice Requests a new price.
     * @param identifier price identifier being requested.
     * @param timestamp timestamp of the price being requested.
     * @param ancillaryData ancillary data representing additional args being passed with the price request.
     * @param currency ERC20 token used for payment of rewards and fees. Must be approved for use with the DVM.
     * @param reward reward offered to a successful proposer. Will be pulled from the caller. Note: this can be 0,
     *               which could make sense if the contract requests and proposes the value in the same call or
     *               provides its own reward system.
     * @return totalBond default bond (final fee) + final fee that the proposer and disputer will be required to pay.
     * This can be changed with a subsequent call to setBond().
     */
    function requestPrice(
        bytes32 identifier,
        uint256 timestamp,
        bytes memory ancillaryData,
        IERC20 currency,
        uint256 reward
    ) public override returns (uint256 totalBond) {
        require(requesterWhitelist.isOnWhitelist(address(msg.sender)), "Requester not whitelisted");
        return super.requestPrice(identifier, timestamp, ancillaryData, currency, reward);
    }

    /**
     * @notice Set the proposal bond associated with a price request.
     * @dev This would also override any subsequent calls to setBond() by the requester.
     * @param requester sender of the initial price request.
     * @param identifier price identifier to identify the existing request.
     * @param ancillaryData ancillary data of the price being requested.
     * @param currency ERC20 token used for payment of rewards and fees. Must be approved for use with the DVM.
     * @param bond custom bond amount to set.
     */
    function requestManagerSetBond(
        address requester,
        bytes32 identifier,
        bytes memory ancillaryData,
        IERC20 currency,
        uint256 bond
    ) external nonReentrant onlyRequestManager {
        require(_getCollateralWhitelist().isOnWhitelist(address(currency)), "Unsupported currency");
        _validateBond(currency, bond);
        bytes32 managedRequestId = _getManagedRequestId(requester, identifier, ancillaryData);
        customBonds[managedRequestId][currency] = CustomBond({amount: bond, isSet: true});
        emit CustomBondSet(managedRequestId, requester, identifier, ancillaryData, currency, bond);
    }

    /**
     * @notice Sets a custom liveness value for the request. Liveness is the amount of time a proposal must wait before
     * being auto-resolved.
     * @dev This would also override any subsequent calls to setLiveness() by the requester.
     * @param requester sender of the initial price request.
     * @param identifier price identifier to identify the existing request.
     * @param ancillaryData ancillary data of the price being requested.
     * @param customLiveness new custom liveness.
     */
    function requestManagerSetCustomLiveness(
        address requester,
        bytes32 identifier,
        bytes memory ancillaryData,
        uint256 customLiveness
    ) external nonReentrant onlyRequestManager {
        _validateLiveness(customLiveness);
        bytes32 managedRequestId = _getManagedRequestId(requester, identifier, ancillaryData);
        customLivenessValues[managedRequestId] = CustomLiveness({liveness: customLiveness, isSet: true});
        emit CustomLivenessSet(managedRequestId, requester, identifier, ancillaryData, customLiveness);
    }

    /**
     * @notice Sets the proposer whitelist for a request.
     * @dev This can also be set in advance of the request as the timestamp is omitted from the mapping key derivation.
     * @param requester sender of the initial price request.
     * @param identifier price identifier to identify the existing request.
     * @param ancillaryData ancillary data of the price being requested.
     * @param whitelist address of the whitelist to set.
     */
    function requestManagerSetProposerWhitelist(
        address requester,
        bytes32 identifier,
        bytes memory ancillaryData,
        address whitelist
    ) external nonReentrant onlyRequestManager {
        bytes32 managedRequestId = _getManagedRequestId(requester, identifier, ancillaryData);
        customProposerWhitelists[managedRequestId] = DisableableAddressWhitelistInterface(whitelist);
        emit CustomProposerWhitelistSet(managedRequestId, requester, identifier, ancillaryData, whitelist);
    }

    /**
     * @notice Proposes a price value on another address' behalf. Note: this address will receive any rewards that come
     * from this proposal. However, any bonds are pulled from the caller.
     * @param proposer address to set as the proposer.
     * @param requester sender of the initial price request.
     * @param identifier price identifier to identify the existing request.
     * @param timestamp timestamp to identify the existing request.
     * @param ancillaryData ancillary data of the price being requested.
     * @param proposedPrice price being proposed.
     * @return totalBond the amount that's pulled from the caller's wallet as a bond. The bond will be returned to
     * the proposer once settled if the proposal is correct.
     */
    function proposePriceFor(
        address proposer,
        address requester,
        bytes32 identifier,
        uint256 timestamp,
        bytes memory ancillaryData,
        int256 proposedPrice
    ) public override returns (uint256 totalBond) {
        // Apply the custom bond and liveness overrides if set.
        Request storage request = _getRequest(requester, identifier, timestamp, ancillaryData);
        bytes32 managedRequestId = _getManagedRequestId(requester, identifier, ancillaryData);
        if (customBonds[managedRequestId][request.currency].isSet) {
            request.requestSettings.bond = customBonds[managedRequestId][request.currency].amount;
        }
        if (customLivenessValues[managedRequestId].isSet) {
            request.requestSettings.customLiveness = customLivenessValues[managedRequestId].liveness;
        }

        DisableableAddressWhitelistInterface whitelist =
            _getEffectiveProposerWhitelist(requester, identifier, ancillaryData);

        require(whitelist.isOnWhitelist(proposer), "Proposer not whitelisted");
        require(whitelist.isOnWhitelist(msg.sender), "Sender not whitelisted");
        return super.proposePriceFor(proposer, requester, identifier, timestamp, ancillaryData, proposedPrice);
    }

    /**
     * @notice Gets the custom proposer whitelist for a request.
     * @dev This omits the timestamp from the key derivation, so the whitelist might have been set in advance of the
     * request.
     * @param requester sender of the initial price request.
     * @param identifier price identifier to identify the existing request.
     * @param ancillaryData ancillary data of the price being requested.
     * @return AddressWhitelistInterface the custom proposer whitelist for the request or zero address if not set.
     */
    function getCustomProposerWhitelist(address requester, bytes32 identifier, bytes memory ancillaryData)
        external
        view
        returns (DisableableAddressWhitelistInterface)
    {
        return customProposerWhitelists[_getManagedRequestId(requester, identifier, ancillaryData)];
    }

    /**
     * @notice Returns the proposer whitelist and enforcement status for a given request.
     * @dev If no custom proposer whitelist is set for the request, the default proposer whitelist is used.
     * If whitelist enforcement is disabled, the returned proposer list will be empty and isEnforced will be false,
     * indicating that any address is allowed to propose.
     * @param requester The address that made or will make the price request.
     * @param identifier The identifier of the price request.
     * @param ancillaryData Additional data used to uniquely identify the request.
     * @return allowedProposers The list of addresses allowed to propose, if enforcement is enabled. Otherwise, an empty array.
     * @return isEnforced A boolean indicating whether whitelist enforcement is active for this request.
     */
    function getProposerWhitelistWithEnforcementStatus(
        address requester,
        bytes32 identifier,
        bytes memory ancillaryData
    ) external view returns (address[] memory allowedProposers, bool isEnforced) {
        DisableableAddressWhitelistInterface whitelist =
            _getEffectiveProposerWhitelist(requester, identifier, ancillaryData);
        isEnforced = whitelist.isEnforced();
        allowedProposers = isEnforced ? whitelist.getWhitelist() : new address[](0);
        return (allowedProposers, isEnforced);
    }

    /**
     * @notice Gets the managed request ID for a price request (without timestamp).
     * @dev This is just a helper function that offchain systems can use for tracking the indexed
     * CustomProposerWhitelistSet events.
     * @param requester sender of the initial price request.
     * @param identifier price identifier to identify the existing request.
     * @param ancillaryData ancillary data of the price being requested.
     * @return bytes32 the request ID for the managed request.
     */
    function getManagedRequestId(address requester, bytes32 identifier, bytes memory ancillaryData)
        external
        pure
        returns (bytes32)
    {
        return _getManagedRequestId(requester, identifier, ancillaryData);
    }

    /**
     * @notice Sets the maximum bond that can be set for a request.
     * @dev This can be used to limit the bond amount that can be set by request managers.
     * @param currency the ERC20 token used for bonding proposals and disputes. Must be approved for use with the DVM.
     * @param maximumBond new maximum bond amount for the given currency.
     */
    function _setMaximumBond(IERC20 currency, uint256 maximumBond) internal {
        require(_getCollateralWhitelist().isOnWhitelist(address(currency)), "Unsupported currency");
        maximumBonds[currency] = maximumBond;
        emit MaximumBondUpdated(currency, maximumBond);
    }

    /**
     * @notice Sets the minimum liveness that can be set for a request.
     * @dev This can be used to limit the liveness period that can be set by request managers.
     * @param _minimumLiveness new minimum liveness period.
     */
    function _setMinimumLiveness(uint256 _minimumLiveness) internal {
        minimumLiveness = _minimumLiveness;
        emit MinimumLivenessUpdated(_minimumLiveness);
    }

    /**
     * @notice Sets the default proposer whitelist.
     * @param whitelist address of the whitelist to set.
     */
    function _setDefaultProposerWhitelist(address whitelist) internal {
        require(whitelist != address(0), "Whitelist cannot be zero address");
        defaultProposerWhitelist = DisableableAddressWhitelistInterface(whitelist);
        emit DefaultProposerWhitelistUpdated(whitelist);
    }

    /**
     * @notice Sets the requester whitelist.
     * @param whitelist address of the whitelist to set.
     */
    function _setRequesterWhitelist(address whitelist) internal {
        require(whitelist != address(0), "Whitelist cannot be zero address");
        requesterWhitelist = DisableableAddressWhitelistInterface(whitelist);
        emit RequesterWhitelistUpdated(whitelist);
    }

    /**
     * @notice Gets the ID for a managed request.
     * @dev This omits the timestamp from the key derivation, so it can be used for managed requests in advance.
     * @param requester sender of the initial price request.
     * @param identifier price identifier to identify the existing request.
     * @param ancillaryData ancillary data of the price being requested.
     * @return bytes32 the ID for the managed request.
     */
    function _getManagedRequestId(address requester, bytes32 identifier, bytes memory ancillaryData)
        internal
        pure
        returns (bytes32)
    {
        return keccak256(abi.encodePacked(requester, identifier, ancillaryData));
    }

    /**
     * @notice Validates the bond amount.
     * @dev Reverts if the bond exceeds the maximum bond amount (controllable by the regular admin).
     * @param currency the ERC20 token used for bonding proposals and disputes. Must be approved for use with the DVM.
     * @param bond the bond amount to validate.
     */
    function _validateBond(IERC20 currency, uint256 bond) internal view {
        require(bond <= maximumBonds[currency], "Bond exceeds maximum bond");
    }

    /**
     * @notice Validates the liveness period.
     * @dev Reverts if the liveness period is less than the minimum liveness (controllable by the regular admin) or
     * above the maximum liveness (which is set in the parent contract).
     * @param liveness the liveness period to validate.
     */
    function _validateLiveness(uint256 liveness) internal view override {
        require(liveness >= minimumLiveness, "Liveness is less than minimum");
        super._validateLiveness(liveness);
    }

    /**
     * @notice Gets the effective proposer whitelist contract for a given request.
     * @dev Returns the custom proposer whitelist if set; otherwise falls back to the default. Timestamp is omitted from
     * the key derivation, so this can be used for checks before the request is made.
     * @param requester The address that made or will make the price request.
     * @param identifier The identifier of the price request.
     * @param ancillaryData Additional data used to uniquely identify the request.
     * @return whitelist The effective DisableableAddressWhitelistInterface for the request.
     */
    function _getEffectiveProposerWhitelist(address requester, bytes32 identifier, bytes memory ancillaryData)
        internal
        view
        returns (DisableableAddressWhitelistInterface whitelist)
    {
        whitelist = customProposerWhitelists[_getManagedRequestId(requester, identifier, ancillaryData)];
        if (address(whitelist) == address(0)) {
            whitelist = defaultProposerWhitelist;
        }
    }
}
