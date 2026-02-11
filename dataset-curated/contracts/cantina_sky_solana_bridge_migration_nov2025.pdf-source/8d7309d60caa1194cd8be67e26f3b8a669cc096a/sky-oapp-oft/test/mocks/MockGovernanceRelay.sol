// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.22;

import { IGovernanceOAppReceiver, MessageOrigin } from "../../contracts/interfaces/IGovernanceOAppReceiver.sol";

contract MockGovernanceRelay {
    bytes32 public immutable allowedOriginCaller;
    uint32 public immutable allowedEid;
    IGovernanceOAppReceiver public immutable messenger;

    error DelegateCallFailed();
    error TestRevert();
    error UnauthorizedMessenger();
    error UnauthorizedOriginCaller();
    
    constructor(IGovernanceOAppReceiver _messenger, bytes32 _allowedOriginCaller, uint32 _allowedEid) {
        messenger = _messenger;
        allowedOriginCaller = _allowedOriginCaller;
        allowedEid = _allowedEid;
    }

    modifier onlyAuthorized() {
        if (msg.sender != address(messenger)) {
            revert UnauthorizedMessenger();
        }

        MessageOrigin memory origin = messenger.messageOrigin();
        if (origin.srcEid != allowedEid || origin.srcSender != allowedOriginCaller) {
            revert UnauthorizedOriginCaller();
        }
        _;
    }

    function relay(address target, bytes calldata targetData) external onlyAuthorized {
        (bool success, bytes memory result) = target.delegatecall(targetData);

        if (!success) {
            if (result.length == 0) revert DelegateCallFailed();
            assembly ("memory-safe") {
                revert(add(32, result), mload(result))
            }
        }
    }

    function revertTest() external pure {
        revert TestRevert();
    }

    function revertTestNoData() external pure {
        revert();
    }
}