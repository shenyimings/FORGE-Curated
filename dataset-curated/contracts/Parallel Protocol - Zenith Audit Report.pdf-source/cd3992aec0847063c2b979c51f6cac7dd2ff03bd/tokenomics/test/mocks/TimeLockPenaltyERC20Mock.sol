// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import { TimeLockPenaltyERC20 } from "contracts/sPRL/TimeLockPenaltyERC20.sol";

contract TimeLockPenaltyERC20Mock is TimeLockPenaltyERC20 {
    constructor(
        string memory name,
        string memory symbol,
        address underlying,
        address feeReceiver,
        address accessManager,
        uint256 startPenaltyPercentage,
        uint64 timeLockDuration
    )
        TimeLockPenaltyERC20(
            name,
            symbol,
            underlying,
            feeReceiver,
            accessManager,
            startPenaltyPercentage,
            timeLockDuration
        )
    { }
}
