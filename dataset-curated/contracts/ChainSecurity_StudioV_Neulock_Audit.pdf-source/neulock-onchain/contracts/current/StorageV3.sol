// SPDX-License-Identifier: CC0-1.0
pragma solidity 0.8.28;

import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/utils/Base64.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

import {INeuStorageV3} from "../interfaces/INeuStorageV3.sol";
import {INeuV3, INeuTokenV3} from "../interfaces/INeuV3.sol";
import {INeuEntitlementV2} from "../interfaces/IEntitlementV2.sol";

/**
 * @title NeuStorageV3
 * @notice This contract manages user data storage with entitlement checks for Neulock.
 * @dev Implements upgradeable storage using OpenZeppelin's UUPS and AccessControl patterns.
 *
 * @custom:author Lucas Neves (lneves.eth) for Studio V
 * @custom:security-contact security@studiov.tech
 */
contract NeuStorageV3 is
    Initializable,
    AccessControlUpgradeable,
    UUPSUpgradeable,
    INeuStorageV3
{
    uint256 private constant _VERSION = 3;

    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");

    INeuTokenV3 private _neuContract;
    mapping(address => bytes) private _userdata;
    INeuEntitlementV2 private _entitlementContract;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initializes the contract with the default admin, upgrader, and NeuContract.
     * @dev Initializes the AccessControl and UUPSUpgradeable contracts.
     * @param defaultAdmin The address of the default admin.
     * @param upgrader The address of the upgrader.
     * @param neuContractAddress The address of the NeuContract.
     *
     * Emits {InitializedStorage} event with the contract version, default admin, upgrader, and NeuContract address.
     */
    function initialize(
        address defaultAdmin,
        address upgrader,
        address neuContractAddress
    ) public initializer {
        __AccessControl_init();
        __UUPSUpgradeable_init();

        _grantRole(DEFAULT_ADMIN_ROLE, defaultAdmin);
        _grantRole(UPGRADER_ROLE, upgrader);

        _neuContract = INeuTokenV3(neuContractAddress);

        emit InitializedStorage(_VERSION, defaultAdmin, upgrader, neuContractAddress);
    }

    /**
     * @notice Initializes the contract with the entitlement contract address.
     * @dev Only callable by an account with UPGRADER_ROLE.
     * @param entitlementContractAddress The address of the entitlement contract.
     *
     * Emits {InitializedStorageV2} event with the entitlement contract address.
     */
    function initializeV2(address entitlementContractAddress) public reinitializer(2) onlyRole(UPGRADER_ROLE) {
        _entitlementContract = INeuEntitlementV2(entitlementContractAddress);

        emit InitializedStorageV2(entitlementContractAddress);
    }

    /**
     * @notice Saves data associated with a given token ID and sends ETH to increase sponsor points.
     * @dev Requires that the caller has entitlement.
     * @param tokenId The ID of the token for which to increase sponsor points.
     * @param data The data to be saved.
     *
     * Requirements:
     * - The caller must have entitlement.
     * - The caller must send a non-zero amount of ETH.
     */
    function saveData(uint256 tokenId, bytes memory data) external payable {
        require(_entitlementContract.hasEntitlement(msg.sender), "Caller does not have entitlement");

        _saveData(data);

        if (msg.value > 0) {
            // slither-disable-next-line unused-return (we make this call only for the side effect)
            _neuContract.increaseSponsorPoints{value: msg.value}(tokenId);
        }
    }

    /**
     * @notice Saves data associated with a given entitlement contract.
     * @dev Requires that the caller has entitlement with the specified contract.
     * @param entitlementContract The address of the entitlement contract.
     * @param data The data to be saved.
     *
     * Requirements:
     * - The caller must have entitlement with the specified contract.
     */
    function saveDataV3(address entitlementContract, bytes memory data) external {
        require(_entitlementContract.hasEntitlementWithContract(msg.sender, entitlementContract), "Caller does not have entitlement");

        _saveData(data);
    }

    /**
     * @notice Retrieves data associated with a given owner.
     * @dev Returns the data stored for the specified owner.
     * @param owner The address of the owner whose data is to be retrieved.
     * @return The data associated with the owner.
     */
    function retrieveData(address owner) external view returns (bytes memory) {
        return _userdata[owner];
    }

    /**
     * @notice Saves data for the caller.
     * @dev Stores the provided data in the caller's storage and emits an event.
     * @param data The data to be saved.
     *
     * Emits {DataSavedV3} event with the caller's address and the saved data.
     */
    function _saveData(bytes memory data) private {
        _userdata[msg.sender] = data;

        emit DataSavedV3(msg.sender, data);
    }

    /**
     * @notice Authorizes contract upgrades.
     * @dev Only callable by an account with UPGRADER_ROLE.
     * @param newImplementation The address of the new implementation contract.
     */
    function _authorizeUpgrade(address newImplementation)
        internal
        onlyRole(UPGRADER_ROLE)
        override
    {}
}
