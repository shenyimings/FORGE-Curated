// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

// Dependency imports
import {IERC5267} from "@openzeppelin/contracts/interfaces/IERC5267.sol";

library PermitLib {
    struct Permit {
        address owner;
        address spender;
        uint256 value;
        uint256 nonce;
        uint256 deadline;
    }

    struct Signature {
        uint8 v;
        bytes32 r;
        bytes32 s;
    }

    bytes32 internal constant PERMIT_TYPEHASH =
        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");

    bytes32 internal constant TYPE_HASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");

    function getPermitTypedDataHash(Permit memory permit, address contractAddress) internal view returns (bytes32) {
        (, string memory name, string memory version,,,,) = IERC5267(contractAddress).eip712Domain();
        return keccak256(
            bytes.concat("\x19\x01", domainSeparator(contractAddress, name, version), permitHashStruct(permit))
        );
    }

    function domainSeparator(address contractAddress, string memory name, string memory version)
        internal
        view
        returns (bytes32)
    {
        return keccak256(
            abi.encode(TYPE_HASH, keccak256(bytes(name)), keccak256(bytes(version)), block.chainid, contractAddress)
        );
    }

    function permitHashStruct(Permit memory permit) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(PERMIT_TYPEHASH, permit.owner, permit.spender, permit.value, permit.nonce, permit.deadline)
        );
    }
}
