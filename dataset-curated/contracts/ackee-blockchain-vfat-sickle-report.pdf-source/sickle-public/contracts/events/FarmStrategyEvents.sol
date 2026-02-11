// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { Sickle } from "contracts/Sickle.sol";

abstract contract FarmStrategyEvents {
    event SickleDeposited(
        Sickle indexed sickle,
        address indexed stakingContract,
        uint256 indexed poolIndex
    );

    event SickleHarvested(
        Sickle indexed sickle,
        address indexed stakingContract,
        uint256 indexed poolIndex
    );

    event SickleCompounded(
        Sickle indexed sickle,
        address indexed claimStakingContract,
        uint256 claimPoolIndex,
        address indexed depositStakingContract,
        uint256 depositPoolIndex
    );

    event SickleWithdrawn(
        Sickle indexed sickle,
        address indexed stakingContract,
        uint256 indexed poolIndex
    );

    event SickleExited(
        Sickle indexed sickle,
        address indexed stakingContract,
        uint256 indexed poolIndex
    );
}
