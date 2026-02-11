// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.10;

import {AccessControlEnumerableUpgradeable} from "openzeppelin-contracts-upgradeable/access/AccessControlEnumerableUpgradeable.sol";
import {Initializable} from "openzeppelin-contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "openzeppelin-contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {WhitelistAccess} from "./WhitelistAccess.sol";

/**
 * @title Whitelist
 * @dev Whitelist contract with UUPS upgradeability pattern
 */
contract Whitelist is 
    Initializable, 
    AccessControlEnumerableUpgradeable, 
    UUPSUpgradeable,
    WhitelistAccess 
{
    // Constants
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant WHITELISTED_ROLE = keccak256("WHITELISTED_ROLE");
    
    // State variables
    bool private _active;
    
    // Events
    event WhitelistActivated(address admin);
    event WhitelistDeactivated(address admin);
    event WhitelistUpgraded(address implementation);

    /**
     * @dev Prevent implementation contract from being initialized
     */
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() initializer {}

    /**
     * @dev Initializer function, used instead of constructor for upgradeable contracts
     * @param admin Address to be assigned admin roles
     */
    function initialize(address admin) public initializer {
        __AccessControlEnumerable_init();
        __UUPSUpgradeable_init();

        // Grant roles to the admin
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(ADMIN_ROLE, admin);
        
        // Set active state to true
        _active = true;
    }

    /**
     * @dev Restricts function to admin only
     */
    modifier onlyAdmin() {
        require(
            hasRole(ADMIN_ROLE, msg.sender),
            "WhitelistAccess: caller does not have the ADMIN_ROLE"
        );
        _;
    }

    /**
     * @dev Restricts function to whitelisted users only
     */
    modifier onlyWhitelisted() {
        require(
            hasRole(WHITELISTED_ROLE, msg.sender), 
            "WhitelistAccess: caller does not have the WHITELISTED_ROLE role"
        );
        _;
    }

    // External functions

    /**
     * @notice Check if the whitelist is active
     * @return Boolean indicating if the whitelist is active
     */
    function isActive() external view override returns (bool) {
        return _active;
    }
    
    /**
     * @notice Activate the whitelist, enforcing whitelist checks
     * @dev Can only be called by an admin
     */
    function activate() external onlyAdmin {
        _active = true;
        emit WhitelistActivated(msg.sender);
    }
    
    /**
     * @notice Deactivate the whitelist, allowing all accounts to pass checks
     * @dev Can only be called by an admin
     */
    function deactivate() external onlyAdmin {
        _active = false;
        emit WhitelistDeactivated(msg.sender);
    }

    // Public functions

    /**
     * @notice Add a new admin
     * @param account Address to grant admin role to
     */
    function addAdmin(address account) public onlyAdmin {
        _grantRole(ADMIN_ROLE, account);
    }

    /**
     * @notice Remove an admin
     * @param account Address to revoke admin role from
     */
    function removeAdmin(address account) public onlyAdmin {
        _revokeRole(ADMIN_ROLE, account);
    }

    /**
     * @notice Add an address to the whitelist
     * @param account Address to whitelist
     */
    function addWhitelisted(address account) public onlyAdmin {
        _grantRole(WHITELISTED_ROLE, account);
    }

    /**
     * @notice Remove an address from the whitelist
     * @param account Address to remove from whitelist
     */
    function removeWhitelisted(address account) public onlyAdmin {
        _revokeRole(WHITELISTED_ROLE, account);
    }

    /**
     * @notice Check if an account is whitelisted
     * @param account The address to check
     * @return Boolean indicating if the address is whitelisted
     */
    function isWhitelisted(address account) public view override returns (bool) {
        return hasRole(WHITELISTED_ROLE, account);
    }

    /**
     * @notice Check if an account is an admin
     * @param account The address to check
     * @return Boolean indicating if the address is an admin
     */
    function isAdmin(address account) public view returns (bool) {
        return hasRole(ADMIN_ROLE, account);
    }

    /**
     * @dev Function that should revert when `msg.sender` is not authorized to upgrade the contract.
     * Called by {upgradeTo} and {upgradeToAndCall}.
     * @param newImplementation The address of the new implementation contract
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyRole(ADMIN_ROLE) {
        emit WhitelistUpgraded(newImplementation);
    }

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[49] private __gap;
}
