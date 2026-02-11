// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import "../../contracts/interfaces/IAccessControl.sol";

contract MockAccessControl is IAccessControl {
    function initialize(address _admin) external {
        // Initialize the admin
    }

    function checkAccess(bytes4 _selector, address _contract, address _caller) external view {
        // Always ok
    }

    function grantAccess(bytes4 _selector, address _contract, address _caller) external {
        // Do nothing, access is always granted
    }

    function revokeAccess(bytes4 _selector, address _contract, address _caller) external {
        // Do nothing, access is always granted
    }

    function role(bytes4 _selector, address _contract) external pure returns (bytes32 roleId) {
        // Always okay
    }
}
