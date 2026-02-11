// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {StorageSlot} from "@openzeppelin/contracts/utils/StorageSlot.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IBlockHashProver} from "./interfaces/IBlockHashProver.sol";
import {IBlockHashProverPointer} from "./interfaces/IBlockHashProverPointer.sol";

bytes32 constant BLOCK_HASH_PROVER_POINTER_SLOT = bytes32(uint256(keccak256("eip7888.pointer.slot")) - 1);

contract BlockHashProverPointer is IBlockHashProverPointer, Ownable {
    address internal _implementationAddress;

    error NonIncreasingVersion(uint256 newVersion, uint256 oldVersion);

    constructor(address _initialOwner) Ownable(_initialOwner) {}

    function implementationAddress() public view returns (address) {
        return _implementationAddress;
    }

    /// @notice Return the code hash of the latest version of the prover.
    function implementationCodeHash() public view returns (bytes32 codeHash) {
        codeHash = StorageSlot.getBytes32Slot(BLOCK_HASH_PROVER_POINTER_SLOT).value;
    }

    function setImplementationAddress(address _newImplementationAddress) external onlyOwner {
        if(implementationAddress() !=  address(0)) {
        uint256 newVersion = IBlockHashProver(_newImplementationAddress).version();
        uint256 oldVersion = IBlockHashProver(implementationAddress()).version();
        if (newVersion <= oldVersion) {
            revert NonIncreasingVersion(newVersion, oldVersion);
        }}
        _implementationAddress = _newImplementationAddress;
        _setCodeHash(_newImplementationAddress.codehash);
    }

    function _setCodeHash(bytes32 _codeHash) internal {
        StorageSlot.getBytes32Slot(BLOCK_HASH_PROVER_POINTER_SLOT).value = _codeHash;
    }
}
