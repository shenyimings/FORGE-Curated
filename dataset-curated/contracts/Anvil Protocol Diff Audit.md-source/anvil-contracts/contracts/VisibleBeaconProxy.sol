// SPDX-License-Identifier: ISC
pragma solidity 0.8.25;

import "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";

/**
 * @notice Extends BeaconProxy to make the beacon address and implementation publicly accessible.
 */
// solc-ignore-next-line missing-receive
contract VisibleBeaconProxy is BeaconProxy {
    constructor(address beacon, bytes memory data) BeaconProxy(beacon, data) {}

    function getBeacon() public view returns (address) {
        return _getBeacon();
    }

    function getImplementation() public view returns (address) {
        return _implementation();
    }
}
