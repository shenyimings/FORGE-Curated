// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { IAccessControl } from "../interfaces/IAccessControl.sol";
import { AccessControlEnumerableUpgradeable } from
    "@openzeppelin/contracts-upgradeable/access/extensions/AccessControlEnumerableUpgradeable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

/// @title AccessControl
/// @author kexley, @capLabs
/// @notice Granular access control for each function on each contract
contract AccessControl is IAccessControl, UUPSUpgradeable, AccessControlEnumerableUpgradeable {
    /// @notice Initialize the default admin
    /// @param _admin Default admin address
    function initialize(address _admin) external initializer {
        __UUPSUpgradeable_init();
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(role(this.grantAccess.selector, address(this)), _admin);
        _grantRole(role(this.revokeAccess.selector, address(this)), _admin);
    }

    /// @notice Check a specific method access is granted to an address
    /// @param _selector Function selector
    /// @param _contract Contract being called
    /// @param _caller Address to check role for
    function checkAccess(bytes4 _selector, address _contract, address _caller) external view {
        _checkRole(role(_selector, _contract), _caller);
    }

    /// @notice Grant access to a specific method on a contract
    /// @param _selector Function selector
    /// @param _contract Contract being called
    /// @param _address Address to grant role to
    function grantAccess(bytes4 _selector, address _contract, address _address) external {
        _checkRole(role(this.grantAccess.selector, address(this)), msg.sender);
        _grantRole(role(_selector, _contract), _address);
    }

    /// @notice Revoke access to a specific method on a contract
    /// @param _selector Function selector
    /// @param _contract Contract being called
    /// @param _address Address to revoke role from
    function revokeAccess(bytes4 _selector, address _contract, address _address) external {
        _checkRole(role(this.revokeAccess.selector, address(this)), msg.sender);
        _revokeRole(role(_selector, _contract), _address);
    }

    /// @notice Fetch role id for a function selector on a contract
    /// @param _selector Function selector
    /// @param _contract Contract being called
    /// @return roleId Role id
    function role(bytes4 _selector, address _contract) public pure returns (bytes32 roleId) {
        /// @dev: make the role id easier to read by humans
        /// selector: 0x40c10f19
        /// contract: 0x521291e5c6c2b8a98ad57ea5f165d25d0bf8f65a
        /// roleId: 0x40c10f190000000000000000521291e5c6c2b8a98ad57ea5f165d25d0bf8f65a
        roleId = bytes32(_selector) | bytes32(uint256(uint160(_contract)));
    }

    /// @dev Only admin can upgrade
    function _authorizeUpgrade(address) internal override onlyRole(DEFAULT_ADMIN_ROLE) { }
}
