// SPDX-License-Identifier: GPL-3.0

/*
    This file is part of the Enzyme Protocol.

    (c) Enzyme Foundation <security@enzyme.finance>

    For the full license information, please view the LICENSE
    file that was distributed with this source code.
*/

pragma solidity >=0.6.0 <0.9.0;

/// @title IGMXV2RoleStore Interface
/// @author Enzyme Foundation <security@enzyme.finance>
interface IGMXV2RoleStore {
    function hasRole(address _account, bytes32 _roleKey) external view returns (bool hasRole_);

    function getRoleMembers(bytes32 _roleKey, uint256 _start, uint256 _end)
        external
        view
        returns (address[] memory members_);
}
