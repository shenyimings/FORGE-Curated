// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { IERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import { Test } from "forge-std/Test.sol";

contract PermitUtils is Test {
    bytes32 private constant PERMIT_TYPEHASH =
        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");

    function getPermitSignature(
        address owner,
        uint256 pk,
        address spender,
        uint256 value,
        uint256 deadline,
        address token
    ) public view returns (uint8 v, bytes32 r, bytes32 s) {
        // Get the nonce for the owner
        uint256 nonce = IERC20Permit(token).nonces(owner);

        // Create the permit digest according to EIP-712
        bytes32 structHash = keccak256(abi.encode(PERMIT_TYPEHASH, owner, spender, value, nonce, deadline));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", IERC20Permit(token).DOMAIN_SEPARATOR(), structHash));

        (v, r, s) = vm.sign(pk, digest);
    }
}
