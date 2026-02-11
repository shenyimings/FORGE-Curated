/*
    This file is part of the Enzyme Protocol.

    (c) Enzyme Foundation <security@enzyme.finance>

    For the full license information, please view the LICENSE
    file that was distributed with this source code.
*/

// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.6.0 <0.9.0;

/// @title IAliceWhitelistManager Interface
/// @author Enzyme Foundation <security@enzyme.finance>
interface IAliceWhitelistManager {
    function addAddress(address _userAddress) external;

    function owner() external returns (address owner_);
}
