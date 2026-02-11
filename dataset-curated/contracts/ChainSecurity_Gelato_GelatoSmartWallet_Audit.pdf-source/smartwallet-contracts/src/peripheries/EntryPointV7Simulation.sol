// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {PackedUserOperation} from "account-abstraction-v0.7/interfaces/PackedUserOperation.sol";
import {EntryPoint} from "account-abstraction-v0.7/core/EntryPoint.sol";
import {SenderCreator} from "account-abstraction-v0.7/core/SenderCreator.sol";

address constant SENDER_CREATOR = 0xEFC2c1444eBCC4Db75e7613d20C6a62fF67A167C;

contract EntryPointV7Simulation is EntryPoint {
    function senderCreator() internal view virtual override returns (SenderCreator) {
        return SenderCreator(SENDER_CREATOR);
    }

    function simulateHandleOps(PackedUserOperation[] calldata userOps, address payable beneficiary)
        public
    {
        uint256 count = userOps.length;
        UserOpInfo[] memory opInfos = new UserOpInfo[](count);

        unchecked {
            for (uint256 i = 0; i < count; i++) {
                _validatePrepayment(0, userOps[i], opInfos[i]);
            }

            uint256 collected = 0;
            for (uint256 i = 0; i < count; i++) {
                collected += _executeUserOp(0, userOps[i], opInfos[i]);
            }

            _compensate(beneficiary, collected);
        }
    }

    function createSenderAndCall(address to, bytes calldata data, bytes calldata initCode)
        external
    {
        senderCreator().createSender(initCode);

        if (to != address(0)) {
            (bool success, bytes memory result) = to.call(data);

            if (!success) {
                assembly {
                    revert(add(result, 32), mload(result))
                }
            }
        }
    }
}
