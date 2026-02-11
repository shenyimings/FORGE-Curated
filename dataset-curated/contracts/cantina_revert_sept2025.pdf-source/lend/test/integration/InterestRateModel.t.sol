// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "forge-std/console.sol";

// base contracts
import "../../src/InterestRateModel.sol";

contract InterestRateModelIntegrationTest is Test {
    uint256 constant Q32 = 2 ** 32;
    uint256 constant Q64 = 2 ** 64;

    uint256 constant YEAR_SECS = 31557600; // taking into account leap years

    uint256 mainnetFork;
    InterestRateModel interestRateModel;

    function setUp() external {
        // 5% base rate - after 80% - 109% (like in compound v2 deployed)
        interestRateModel = new InterestRateModel(0, Q64 * 5 / 100, Q64 * 109 / 100, Q64 * 80 / 100);
    }

    function testUtilizationRates() external {
        assertEq(interestRateModel.getUtilizationRateX64(10, 0), 0);
        assertEq(interestRateModel.getUtilizationRateX64(10, 10), Q64 / 2);
        assertEq(interestRateModel.getUtilizationRateX64(0, 10), Q64);
    }

    function testInterestRates() external {
        (uint256 borrowRateX64, uint256 lendRateX64) = interestRateModel.getRatesPerSecondX64(10, 0);
        assertEq(borrowRateX64 * YEAR_SECS, 0); // 0% for 0% utilization
        assertEq(lendRateX64 * YEAR_SECS, 0); // 0% for 0% utilization

        (borrowRateX64, lendRateX64) = interestRateModel.getRatesPerSecondX64(10000000, 10000000);
        assertEq(borrowRateX64 * YEAR_SECS, 461168601834355200); // 2.5% per year for 50% utilization
        assertEq(lendRateX64 * YEAR_SECS, 230584300917177600); // 1.25% for 50% utilization

        (borrowRateX64, lendRateX64) = interestRateModel.getRatesPerSecondX64(0, 10);
        assertEq(borrowRateX64 * YEAR_SECS, 4759259970973464000); // 25.8% per year for 100% utilization
        assertEq(lendRateX64 * YEAR_SECS, 4759259970973464000); // 25.8% per year for 100% utilization
    }
}
