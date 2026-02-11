// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {
    AccessControlEnumerableUpgradeable
} from "@openzeppelin/contracts-upgradeable/access/extensions/AccessControlEnumerableUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

/**
 * @title AllowList
 * @notice Base contract providing allowlist functionality that can be inherited by other contracts
 * @dev Uses role-based access control where DEPOSIT_ROLE represents allowlist membership
 */
abstract contract AllowList is Initializable, AccessControlEnumerableUpgradeable {
    error NotAllowListed(address user);
    error AlreadyAllowListed(address user);
    error NotInAllowList(address user);

    bytes32 public constant DEPOSIT_ROLE = keccak256("DEPOSIT_ROLE");
    bytes32 public constant ALLOW_LIST_MANAGER_ROLE = keccak256("ALLOW_LIST_MANAGER_ROLE");

    bool public immutable ALLOW_LIST_ENABLED;

    event AllowListAdded(address indexed user);
    event AllowListRemoved(address indexed user);

    constructor(bool _allowListEnabled) {
        ALLOW_LIST_ENABLED = _allowListEnabled;
    }

    /**
     * @notice Add an address to the allowlist
     * @param _user Address to add to allowlist
     */
    function addToAllowList(address _user) external {
        _checkRole(ALLOW_LIST_MANAGER_ROLE, msg.sender);
        if (isAllowListed(_user)) revert AlreadyAllowListed(_user);

        grantRole(DEPOSIT_ROLE, _user);

        emit AllowListAdded(_user);
    }

    /**
     * @notice Remove an address from the allowlist
     * @param _user Address to remove from allowlist
     */
    function removeFromAllowList(address _user) external {
        _checkRole(ALLOW_LIST_MANAGER_ROLE, msg.sender);
        if (!isAllowListed(_user)) revert NotInAllowList(_user);

        revokeRole(DEPOSIT_ROLE, _user);

        emit AllowListRemoved(_user);
    }

    /**
     * @notice Check if an address is allowlisted
     * @param _user Address to check
     * @return bool True if allowlisted
     */
    function isAllowListed(address _user) public view returns (bool) {
        return hasRole(DEPOSIT_ROLE, _user);
    }

    /**
     * @notice Get the current allowlist size
     * @return uint256 Number of addresses in allowlist
     */
    function getAllowListSize() external view returns (uint256) {
        return getRoleMemberCount(DEPOSIT_ROLE);
    }

    /**
     * @notice Get all allowlisted addresses
     * @return address[] Array of allowlisted addresses
     */
    function getAllowListAddresses() external view returns (address[] memory) {
        return getRoleMembers(DEPOSIT_ROLE);
    }

    /**
     * @notice Internal function to check if caller is allowlisted when allowlist is enabled
     * @dev Reverts with NotAllowListed if allowlist is enabled and caller doesn't have DEPOSIT_ROLE
     */
    function _checkAllowList() internal view {
        if (ALLOW_LIST_ENABLED && !hasRole(DEPOSIT_ROLE, msg.sender)) {
            revert NotAllowListed(msg.sender);
        }
    }

    /**
     * @notice Initialize allowlist roles - should be called by inheriting contracts
     * @param _owner Address to grant admin and manager roles to
     */
    function _initializeAllowList(address _owner) internal onlyInitializing {
        _grantRole(ALLOW_LIST_MANAGER_ROLE, _owner);
        _setRoleAdmin(ALLOW_LIST_MANAGER_ROLE, DEFAULT_ADMIN_ROLE);
        _setRoleAdmin(DEPOSIT_ROLE, ALLOW_LIST_MANAGER_ROLE);
    }
}
