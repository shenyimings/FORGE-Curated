// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @author philogy <https://github.com/philogy>
interface IHookAddressMiner {
    function mineAngstromHookAddress(address owner) external view returns (bytes32);
}
