// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

contract MockDAO {
    mapping(address => mapping(address => mapping(bytes32 => bool))) public permissions;

    function grant(address _where, address _who, bytes32 _permissionId) external {
        permissions[_where][_who][_permissionId] = true;
    }

    function revoke(address _where, address _who, bytes32 _permissionId) external {
        permissions[_where][_who][_permissionId] = false;
    }

    function hasPermission(
        address _where,
        address _who,
        bytes32 _permissionId,
        bytes memory
    )
        external
        view
        returns (bool)
    {
        return permissions[_where][_who][_permissionId];
    }
}
