// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import { EnumerableSet } from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import { MultiSig } from "packages/onesig-evm/contracts/MultiSig.sol";

contract MultiSigHarness is MultiSig {
    using EnumerableSet for EnumerableSet.AddressSet;

    error IndexOutOfBoundsError(uint256 index);

    constructor(address[] memory _signers, uint256 _threshold) MultiSig(_signers, _threshold) {}

    function getSigner(uint256 _index) external view returns (address signer) {
        signer = signerSet.at(_index);
    }

    function recoverSignerForIndex(
        bytes32 _digest,
        bytes calldata _signatures,
        uint256 _index
    ) public view returns (address signer) {
        // Each signature is 65 bytes (r=32, s=32, v=1).
        // Extract a single signature (65 bytes) for _index.
        bytes calldata signature = _signatures[_index * 65:(_index + 1) * 65];
        signer = ECDSA.recover(_digest, signature);
    }
}
