// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.22;

import { IGovernanceController } from "../../contracts/IGovernanceController.sol";

contract MockGovernanceRelay {
    bytes32 public immutable allowedOriginCaller;
    uint32 public immutable allowedEid;
    IGovernanceController public immutable messenger;

    error DelegateCallFailed();
    error TestRevert();
    error UnauthorizedMessenger();
    error UnauthorizedOriginCaller();
    
    constructor(IGovernanceController _messenger, bytes32 _allowedOriginCaller, uint32 _allowedEid) {
        messenger = _messenger;
        allowedOriginCaller = _allowedOriginCaller;
        allowedEid = _allowedEid;
    }

    modifier onlyAuthorized() {
        if (msg.sender != address(messenger)) {
            revert UnauthorizedMessenger();
        }

        (uint32 originEid, bytes32 originCaller) = messenger.messageOrigin();
        if (originEid != allowedEid || originCaller != allowedOriginCaller) {
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