// SPDX-License-Identifier: GPL-3.0

/*
    This file is part of the Enzyme Protocol.

    (c) Enzyme Foundation <security@enzyme.finance>

    For the full license information, please view the LICENSE
    file that was distributed with this source code.
*/

pragma solidity >=0.6.0 <0.9.0;

/// @title IGMXV2DataStore Interface
/// @author Enzyme Foundation <security@enzyme.finance>
interface IGMXV2DataStore {
    function getUint(bytes32 _key) external view returns (uint256 value_);

    function setUint(bytes32 _key, uint256 _value) external returns (uint256 value_);

    function getBytes32ValuesAt(bytes32 _setKey, uint256 _start, uint256 _end)
        external
        view
        returns (bytes32[] memory values_);

    function setAddress(bytes32 _key, address _value) external returns (address value_);

    function getAddress(bytes32 _key) external view returns (address value_);

    function setBool(bytes32 _key, bool _value) external returns (bool value_);
}
