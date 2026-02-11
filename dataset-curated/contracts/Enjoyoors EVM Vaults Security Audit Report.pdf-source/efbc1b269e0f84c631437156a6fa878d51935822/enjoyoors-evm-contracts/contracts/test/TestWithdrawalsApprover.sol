// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.26;

import '../interfaces/IEnjoyoorsWithdrawalApprover.sol';

contract TestWithdrawalApprover is IEnjoyoorsWithdrawalApprover {
  function canClaimWithdrawal(uint256 requestId, bytes calldata approverData) external pure {
    if (!abi.decode(approverData, (bool))) revert NotApproved(requestId);
  }
}
