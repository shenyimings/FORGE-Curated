// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {Delegation} from "../src/Delegation.sol";
import {Counter} from "./Counter.sol";
import {Vm} from "forge-std/Vm.sol";

abstract contract ECDSASignature {
    function _generateECDSASig(
        Vm vm,
        Delegation delegation,
        uint256 privateKey,
        bytes32 mode,
        Delegation.Call[] memory calls,
        uint256 nonce
    ) internal view returns (bytes memory) {
        // EOA is the verifying contract, not Delegate contract
        address eoa = vm.addr(privateKey);
        bytes32 digest = _computeDigest(delegation, eoa, mode, calls, nonce);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);

        bytes memory signature = abi.encodePacked(r, s, v);

        return signature;
    }

    function _computeDigest(
        Delegation delegation,
        address verifyingContract,
        bytes32 mode,
        Delegation.Call[] memory calls,
        uint256 nonce
    ) private view returns (bytes32) {
        bytes32[] memory callsHashes = new bytes32[](calls.length);
        for (uint256 i = 0; i < calls.length; i++) {
            callsHashes[i] = keccak256(
                abi.encode(
                    keccak256("Call(address to,uint256 value,bytes data)"),
                    calls[i].to,
                    calls[i].value,
                    keccak256(calls[i].data)
                )
            );
        }

        bytes32 executeHash = keccak256(
            abi.encode(
                keccak256(
                    "Execute(bytes32 mode,Call[] calls,uint256 nonce)Call(address to,uint256 value,bytes data)"
                ),
                mode,
                keccak256(abi.encodePacked(callsHashes)),
                nonce
            )
        );

        (, string memory name, string memory version, uint256 chainId,,,) =
            delegation.eip712Domain();

        bytes32 domainSeparator = keccak256(
            abi.encode(
                keccak256(
                    "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
                ),
                keccak256(bytes(name)),
                keccak256(bytes(version)),
                chainId,
                verifyingContract
            )
        );

        return keccak256(abi.encodePacked("\x19\x01", domainSeparator, executeHash));
    }
}
