// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {IBlockHashProver} from "src/contracts/interfaces/IBlockHashProver.sol";

contract MockProver is IBlockHashProver {
    function verifyTargetBlockHash(
        bytes32 homeBlockHash,
        bytes calldata /*input*/
    )
        external
        pure
        returns (bytes32 targetBlockHash)
    {
        return homeBlockHash;
    }

    function getTargetBlockHash(bytes calldata input) external pure returns (bytes32 targetBlockHash) {
        targetBlockHash = abi.decode(input, (bytes32));
    }

    function verifyStorageSlot(
        bytes32,
        /*targetBlockHash*/
        bytes calldata input
    )
        external
        pure
        returns (address account, uint256 slot, bytes32 value)
    {
        (account, slot, value) = abi.decode(input, (address, uint256, bytes32));
        return (account, slot, value);
    }

    function version() external pure returns (uint256) {
        return 1;
    }
}
