/*
 * SPDX-License-Identifier:    MIT
 */

pragma solidity ^0.6.2;

import "../acl/IACL.sol";
import "../common/IVaultRecoverable.sol";


interface IKernelEvents {
    event SetApp(bytes32 indexed namespace, bytes32 indexed appId, address app);
}


// This should be an interface, but interfaces can't inherit yet :(
abstract contract IKernel is IKernelEvents, IVaultRecoverable {
    function acl() public virtual view returns (IACL);
    function hasPermission(address who, address where, bytes32 what, bytes memory how) public virtual view returns (bool);

    function setApp(bytes32 namespace, bytes32 appId, address app) public virtual;
    function getApp(bytes32 namespace, bytes32 appId) public virtual view returns (address);
}