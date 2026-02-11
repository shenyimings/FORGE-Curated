// SPDX-License-Identifier: MIT
pragma solidity >=0.7.6 <0.9;

import {IERC1967} from "@openzeppelin/contracts/interfaces/IERC1967.sol";


interface IUUPSUpgradeable is IERC1967 {
    /**
     * Upgrade proxy to new implementation.
     */
    function upgradeTo(address _newImplementation) external;

    /**
     * Upgrade proxy to new implementation and call an initialization method (via delegatecall).
     * @param _newImplementation the new implementation address
     * @param _initializeCall abi encoded call of some initialization method (as created by `abi.encodeCall`);
     *   if empty string is passed, no call is made
     */
    function upgradeToAndCall(address _newImplementation, bytes memory _initializeCall) external payable;
}
