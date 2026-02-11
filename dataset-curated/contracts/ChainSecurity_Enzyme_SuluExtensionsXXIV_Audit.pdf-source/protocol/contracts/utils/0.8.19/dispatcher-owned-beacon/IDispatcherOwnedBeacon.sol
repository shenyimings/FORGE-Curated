// SPDX-License-Identifier: GPL-3.0

/*
    This file is part of the Enzyme Protocol.
    (c) Enzyme Foundation <security@enzyme.finance>
    For the full license information, please view the LICENSE
    file that was distributed with this source code.
*/

pragma solidity >=0.6.0 <0.9.0;

/// @title IDispatcherOwnedBeacon Interface
/// @author Enzyme Foundation <security@enzyme.finance>
interface IDispatcherOwnedBeacon {
    function getOwner() external view returns (address owner_);

    // From OpenZeppelin's IBeacon interface (which is only scoped in OZ to >=0.8.0)
    function implementation() external view returns (address implementation_);

    function setImplementation(address _nextImplementation) external;
}
