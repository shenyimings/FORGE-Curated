// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

// Internal imports
import {LeverageTokenTest} from "./LeverageToken.t.sol";
import {PermitLib} from "../../utils/PermitLib.sol";

contract PermitTest is LeverageTokenTest {
    using PermitLib for PermitLib.Permit;

    /// @dev Sanity test to ensure that token supports permit
    function testFuzz_permit(PermitLib.Permit memory permit, uint256 privateKey, uint128 blockTimestamp) public {
        vm.assume(permit.spender != address(0));
        vm.warp(blockTimestamp);

        privateKey = bound(privateKey, 1, type(uint32).max);
        permit.owner = vm.addr(privateKey);

        permit.deadline = bound(permit.deadline, block.timestamp, type(uint256).max);
        permit.nonce = leverageToken.nonces(permit.owner);

        PermitLib.Signature memory sig;
        bytes32 digest = PermitLib.getPermitTypedDataHash(permit, address(leverageToken));
        (sig.v, sig.r, sig.s) = vm.sign(privateKey, digest);

        leverageToken.permit(permit.owner, permit.spender, permit.value, permit.deadline, sig.v, sig.r, sig.s);

        assertEq(leverageToken.nonces(permit.owner), permit.nonce + 1);
        assertEq(leverageToken.allowance(permit.owner, permit.spender), permit.value);
    }
}
