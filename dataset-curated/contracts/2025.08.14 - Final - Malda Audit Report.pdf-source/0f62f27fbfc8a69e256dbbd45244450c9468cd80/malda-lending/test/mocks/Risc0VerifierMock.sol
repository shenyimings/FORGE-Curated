// SPDX-License-Identifier: BSL-1.1
pragma solidity =0.8.28;

// contracts
import {Steel} from "risc0/steel/Steel.sol";

contract Risc0VerifierMock {
    struct Receipt {
        bytes seal;
        bytes32 claimDigest;
    }

    bool public shouldRevert;

    function setStatus(bool _failure) external {
        shouldRevert = _failure;
    }

    function verify(bytes calldata, bytes32, bytes32) external view {
        if (shouldRevert) revert("Failure");
    }

    function verifyIntegrity(Receipt calldata) external view {
        if (shouldRevert) revert("Failure");
    }
}
