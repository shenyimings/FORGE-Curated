// SPDX-License-Identifier: GPL-3.0

/*
    This file is part of the Enzyme Protocol.

    (c) Enzyme Foundation <security@enzyme.finance>

    For the full license information, please view the LICENSE
    file that was distributed with this source code.
*/

pragma solidity 0.8.19;

import {DispatcherOwnedBeacon} from "./DispatcherOwnedBeacon.sol";
import {IDispatcherOwnedBeaconFactory} from "./IDispatcherOwnedBeaconFactory.sol";

/// @title DispatcherOwnedBeaconFactory Contract
/// @author Enzyme Foundation <security@enzyme.finance>
/// @notice A factory for beacon proxy instances that also serves as the Dispatcher-owned beacon
contract DispatcherOwnedBeaconFactory is IDispatcherOwnedBeaconFactory, DispatcherOwnedBeacon {
    constructor(address _dispatcherAddress, address _implementationAddress)
        DispatcherOwnedBeacon(_dispatcherAddress, _implementationAddress)
    {}

    /// @notice Deploys a new proxy instance
    /// @param _constructData Encoded data to initialize the proxy instance
    /// @return proxyAddress_ The address of the deployed proxy
    function deployProxy(bytes calldata _constructData) external override returns (address proxyAddress_) {
        return __deployProxy({_constructData: _constructData});
    }
}
