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

    function getBytes32ValuesAt(bytes32 _setKey, uint256 _start, uint256 _end)
        external
        view
        returns (bytes32[] memory values_);
}
