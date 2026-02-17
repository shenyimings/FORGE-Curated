// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { IAccess } from "../interfaces/IAccess.sol";
import { IAccessControl } from "../interfaces/IAccessControl.sol";

import { AccessStorageUtils } from "../storage/AccessStorageUtils.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

/// @title Access
/// @author kexley, @capLabs
/// @notice Inheritable access
contract Access is IAccess, Initializable, AccessStorageUtils {
    /// @dev Initialize the access control address
    /// @param _accessControl Access control address
    function __Access_init(address _accessControl) internal onlyInitializing {
        __Access_init_unchained(_accessControl);
    }

    /// @dev Initialize unchained
    /// @param _accessControl Access control address
    function __Access_init_unchained(address _accessControl) internal onlyInitializing {
        getAccessStorage().accessControl = _accessControl;
    }

    /// @dev Check caller has permissions for a function, revert if call is not allowed
    /// @param _selector Function selector
    modifier checkAccess(bytes4 _selector) {
        _checkAccess(_selector);
        _;
    }

    /// @dev Check caller has access to a function, revert overwise
    /// @param _selector Function selector
    function _checkAccess(bytes4 _selector) internal view {
        IAccessControl(getAccessStorage().accessControl).checkAccess(_selector, address(this), msg.sender);
    }
}
