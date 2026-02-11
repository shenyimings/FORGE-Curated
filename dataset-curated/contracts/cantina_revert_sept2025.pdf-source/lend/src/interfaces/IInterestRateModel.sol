// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

interface IInterestRateModel {
    // gets borrow and supply interest rate per second
    function getRatesPerSecondX64(uint256 cash, uint256 debt)
        external
        view
        returns (uint256 borrowRateX64, uint256 supplyRateX64);
}
