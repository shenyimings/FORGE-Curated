// SPDX-License-Identifier: CC0-1.0
pragma solidity 0.8.28;

import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/interfaces/IERC721.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import {INeuEntitlementV2} from "../interfaces/IEntitlementV2.sol";
import {INeuTokenV3} from "../interfaces/INeuV3.sol";

/**
 * @title NeuEntitlementV2
 * @author Lucas Neves (lneves.eth) for Studio V
 * @notice Manages entitlement contracts and checks user entitlements for Neulock.
 * @dev Upgradeable contract using OpenZeppelin's UUPS pattern. Handles entitlement contracts and integrates with NeuTokenV3.
 * @custom:security-contact security@studiov.tech
 */
contract NeuEntitlementV2 is
    Initializable,
    AccessControlUpgradeable,
    UUPSUpgradeable,
    INeuEntitlementV2
{
    using EnumerableSet for EnumerableSet.AddressSet;
    uint256 private constant _VERSION = 2;

    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    address[] private entitlementContracts; // Deprecated in V2
    EnumerableSet.AddressSet private _entitlementContracts;
    INeuTokenV3 private _neuContract;

    /**
     * @notice Disables initializers to prevent implementation contract from being initialized.
     * @dev This constructor is only used to disable initializers for the implementation contract.
     */
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initializes the contract with admin, upgrader, operator, and Neu contract addresses.
     * @dev Grants roles and adds the initial Neu contract as an entitlement contract.
     * @param defaultAdmin The address to be granted DEFAULT_ADMIN_ROLE.
     * @param upgrader The address to be granted UPGRADER_ROLE.
     * @param operator The address to be granted OPERATOR_ROLE.
     * @param neuContract The address of the NeuTokenV3 contract.
     *
     * Emits {EntitlementContractAdded} and {InitializedEntitlement} events.
     */
    function initialize(
        address defaultAdmin,
        address upgrader,
        address operator,
        address neuContract
    ) public initializer {
        __AccessControl_init();
        __UUPSUpgradeable_init();

        _grantRole(DEFAULT_ADMIN_ROLE, defaultAdmin);
        _grantRole(UPGRADER_ROLE, upgrader);
        _grantRole(OPERATOR_ROLE, operator);

        entitlementContracts.push(neuContract);

        emit EntitlementContractAdded(neuContract);
        emit InitializedEntitlement(_VERSION, defaultAdmin, upgrader, operator, neuContract);
    }

    /**
     * @notice Upgrades contract state to V2, migrating entitlement contracts to the new storage structure and setting the NEU contract.
     * @dev Only callable by addresses with UPGRADER_ROLE. Should be called after upgrading to V2.
     * @param neuContract The address of the NeuTokenV3 contract.
     *
     * Emits {InitializedEntitlementV2} event.
     */
    function initializeV2(address neuContract) public reinitializer(2) onlyRole(UPGRADER_ROLE) {
        uint256 existingContractsLength = entitlementContracts.length;

        _neuContract = INeuTokenV3(neuContract);

        for (uint256 i = 0; i < existingContractsLength; i++) {
            if (entitlementContracts[i] != neuContract) {
                // slither-disable-next-line unused-return (we only care about the side effect)
                _entitlementContracts.add(entitlementContracts[i]);
            }
        }

        emit InitializedEntitlementV2(neuContract);
    }

    /**
     * @notice Returns the address of an entitlement contract by index.
     * @dev Index 0 returns the NeuTokenV3 contract, subsequent indices return other entitlement contracts.
     * @param index The index of the entitlement contract.
     * @return The address of the entitlement contract at the given index.
     */
    function entitlementContractsV2(uint256 index) external view returns (address) {
        if (index == 0) {
            return address(_neuContract);
        }

        return _entitlementContracts.at(index - 1);
    }

    /**
     * @notice Returns the number of entitlement contracts.
     * @dev Includes the NeuTokenV3 contract.
     * @return The number of entitlement contracts.
     */
    function entitlementContractsLength() external view returns (uint256) {
        return _entitlementContracts.length() + 1;
    }

    /**
     * @notice Adds a new entitlement contract.
     * @dev Only callable by addresses with OPERATOR_ROLE. The contract must implement balanceOf().
     * @param entitlementContract The address of the entitlement contract to add.
     *
     * Emits {EntitlementContractAdded} event.
     *
     * Requirements:
     * - The contract must not be the NEU contract.
     * - The contract must not already be added.
     * - The contract must support balanceOf().
     */
    function addEntitlementContract(address entitlementContract) external onlyRole(OPERATOR_ROLE) override {
        require(entitlementContract != address(_neuContract), "Cannot add NEU contract");
        require(_entitlementContracts.add(entitlementContract), "Entitlement contract already added");

        // We won't check for the IERC721 interface, since any token that supports balanceOf() can be used
        // slither-disable-next-line unused-return (we don't need the return value, only to check if the function exists)
        try IERC721(entitlementContract).balanceOf(address(this)) {} catch {
            revert("Contract does not support balanceOf()");
        }

        emit EntitlementContractAdded(entitlementContract);
    }

    /**
     * @notice Removes an entitlement contract.
     * @dev Only callable by addresses with OPERATOR_ROLE.
     * @param entitlementContract The address of the entitlement contract to remove.
     *
     * Emits {EntitlementContractRemoved} event.
     *
     * Requirements:
     * - The contract must be present in the entitlement set.
     */
    function removeEntitlementContract(address entitlementContract) external onlyRole(OPERATOR_ROLE) override {
        require(_entitlementContracts.remove(entitlementContract), "Entitlement contract not found");

        emit EntitlementContractRemoved(entitlementContract);
    }

    /**
     * @notice Checks if a user has entitlement via any registered contract.
     * @dev Checks both NeuTokenV3 and all added entitlement contracts.
     * @param user The address of the user to check entitlement for.
     * @return True if the user has entitlement, false otherwise.
     */
    function hasEntitlement(address user) external view override returns (bool) {
        if (_callerHasNeuEntitlement(user)) {
            return true;
        }

        uint256 contractsLength = _entitlementContracts.length();

        for (uint256 i = 0; i < contractsLength; i++) {
            if (_callerHasContractEntitlement(user, _entitlementContracts.at(i))) {
                return true;
            }
        }

        return false;
    }

    /**
     * @notice Checks if a user has entitlement with a specific contract.
     * @dev Checks entitlement for either NeuTokenV3 or a specified entitlement contract.
     * @param user The address of the user to check entitlement for.
     * @param entitlementContract The address of the entitlement contract to check.
     * @return True if the user has entitlement with the specified contract, false otherwise.
     */
    function hasEntitlementWithContract(address user, address entitlementContract) external view override returns (bool) {
        if (entitlementContract == address(_neuContract)) {
            return _callerHasNeuEntitlement(user);
        }

        if (_entitlementContracts.contains(entitlementContract)) {
            return _callerHasContractEntitlement(user, entitlementContract);
        }

        return false;
    }

    /**
     * @notice Returns the list of entitlement contracts where the user has entitlement.
     * @dev Checks NeuTokenV3 and all added entitlement contracts for user entitlement.
     * @param user The address of the user to check entitlement for.
     * @return An array of addresses of entitlement contracts where the user has entitlement.
     */
    function userEntitlementContracts(address user) external view override returns (address[] memory) {
        uint256 contractsLength = _entitlementContracts.length();

        address[] memory userEntitlements = new address[](contractsLength + 1);
        uint256 count = 0;

        if (_callerHasNeuEntitlement(user)) {
            userEntitlements[0] = address(_neuContract);
            count++;
        }

        for (uint256 i = 0; i < contractsLength; i++) {
            address entitlementContract = _entitlementContracts.at(i);

            if (_callerHasContractEntitlement(user, entitlementContract)) {
                userEntitlements[count] = entitlementContract;
                count++;
            }
        }

        assembly {
            mstore(userEntitlements, count)
        }

        return userEntitlements;
    }

    function _callerHasContractEntitlement(address user, address contractAddress) private view returns (bool) {
        // slither-disable-next-line calls-loop (will only revert if contract has been upgraded and doesn't support balanceOf(); in this case, we don't want to fail silently)
        return IERC721(contractAddress).balanceOf(user) > 0;
    }

    function _callerHasNeuEntitlement(address user) private view returns (bool) {
        uint256 userNeuBalance = _neuContract.balanceOf(user);

        for (uint256 i = 0; i < userNeuBalance; i++) {
            uint256 tokenId = _neuContract.tokenOfOwnerByIndex(user, i);

            // slither-disable-next-line block-timestamp (with a granularity of days for the entitlement cooldown, we can tolerate miner manipulation)
            if (block.timestamp >= _neuContract.entitlementAfterTimestamps(tokenId)) {
                return true;
            }
        }

        return false;
    }

    /**
     * @notice Authorizes contract upgrades.
     * @dev Only addresses with UPGRADER_ROLE can upgrade the contract. Required by UUPS pattern.
     * @param newImplementation The address of the new contract implementation.
     */
    function _authorizeUpgrade(address newImplementation) internal onlyRole(UPGRADER_ROLE) override {}
}
