// Copyright (c) 2025 Merge Layers Inc.
//
// This source code is licensed under the Business Source License 1.1
// (the "License"); you may not use this file except in compliance with the
// License. You may obtain a copy of the License at
//
//     https://github.com/malda-protocol/malda-lending/blob/main/LICENSE-BSL
//
// See the License for the specific language governing permissions and
// limitations under the License.
//
// This file contains code derived from or inspired by Compound V2,
// originally licensed under the BSD 3-Clause License. See LICENSE-COMPOUND-V2
// for original license terms and attributions.

// SPDX-License-Identifier: BSL-1.1
pragma solidity =0.8.28;

/*
 _____ _____ __    ____  _____ 
|     |  _  |  |  |    \|  _  |
| | | |     |  |__|  |  |     |
|_|_|_|__|__|_____|____/|__|__|   
*/

/**
 * @title IInterestRateModel
 * @notice Interface for the interest rate contracts
 */
interface IInterestRateModel {
    /// @notice Emitted when interest rate parameters are updated
    /// @param baseRatePerBlock The base rate per block
    /// @param multiplierPerBlock The multiplier per block for the interest rate slope
    /// @param jumpMultiplierPerBlock The multiplier after hitting the kink
    /// @param kink The utilization point where the jump multiplier is applied
    event NewInterestParams(
        uint256 baseRatePerBlock, uint256 multiplierPerBlock, uint256 jumpMultiplierPerBlock, uint256 kink
    );

    /**
     * @notice Should return true
     */
    function isInterestRateModel() external view returns (bool);

    /**
     * @notice The approximate number of blocks per year that is assumed by the interest rate model
     * @return The number of blocks per year
     */
    function blocksPerYear() external view returns (uint256);

    /**
     * @notice The multiplier of utilization rate that gives the slope of the interest rate
     * @return The multiplier per block
     */
    function multiplierPerBlock() external view returns (uint256);

    /**
     * @notice The base interest rate which is the y-intercept when utilization rate is 0
     * @return The base rate per block
     */
    function baseRatePerBlock() external view returns (uint256);

    /**
     * @notice The multiplierPerBlock after hitting a specified utilization point
     * @return The jump multiplier per block
     */
    function jumpMultiplierPerBlock() external view returns (uint256);

    /**
     * @notice The utilization point at which the jump multiplier is applied
     * @return The utilization point (kink)
     */
    function kink() external view returns (uint256);

    /**
     * @notice A name for user-friendliness, e.g. WBTC
     * @return The name of the interest rate model
     */
    function name() external view returns (string memory);

    /**
     * @notice Calculates the utilization rate of the market
     * @param cash The total cash in the market
     * @param borrows The total borrows in the market
     * @param reserves The total reserves in the market
     * @return The utilization rate as a mantissa between [0, 1e18]
     */
    function utilizationRate(uint256 cash, uint256 borrows, uint256 reserves) external pure returns (uint256);

    /**
     * @notice Returns the current borrow rate per block for the market
     * @param cash The total cash in the market
     * @param borrows The total borrows in the market
     * @param reserves The total reserves in the market
     * @return The current borrow rate per block, scaled by 1e18
     */
    function getBorrowRate(uint256 cash, uint256 borrows, uint256 reserves) external view returns (uint256);

    /**
     * @notice Returns the current supply rate per block for the market
     * @param cash The total cash in the market
     * @param borrows The total borrows in the market
     * @param reserves The total reserves in the market
     * @param reserveFactorMantissa The current reserve factor for the market
     * @return The current supply rate per block, scaled by 1e18
     */
    function getSupplyRate(uint256 cash, uint256 borrows, uint256 reserves, uint256 reserveFactorMantissa)
        external
        view
        returns (uint256);
}
