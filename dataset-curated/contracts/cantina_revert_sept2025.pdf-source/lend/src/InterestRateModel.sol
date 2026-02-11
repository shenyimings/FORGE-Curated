// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeCast.sol";

import "./interfaces/IInterestRateModel.sol";
import "./utils/Constants.sol";

/// @title Model for interest rate calculation used in Vault
/// @notice Calculates both borrow and supply rate
contract InterestRateModel is Ownable, IInterestRateModel, Constants {

    uint256 public constant YEAR_SECS = 31557600; // taking into account leap years

    uint256 public constant MAX_BASE_RATE_X64 = Q64 / 10; // 10%
    uint256 public constant MAX_MULTIPLIER_X64 = Q64 * 2; // 200%

    event SetValues(
        uint256 baseRatePerYearX64, uint256 multiplierPerYearX64, uint256 jumpMultiplierPerYearX64, uint256 kinkX64
    );

    // all values are multiplied by Q64
    uint64 public multiplierPerSecondX64;
    uint64 public baseRatePerSecondX64;
    uint64 public jumpMultiplierPerSecondX64;
    uint64 public kinkX64;

    /// @notice Creates interest rate model
    /// @param baseRatePerYearX64 Base rate per year multiplied by Q64
    /// @param multiplierPerYearX64 Multiplier for utilization rate below kink multiplied by Q64
    /// @param jumpMultiplierPerYearX64 Multiplier for utilization rate above kink multiplied by Q64
    /// @param _kinkX64 Kink percentage multiplied by Q64
    constructor(
        uint256 baseRatePerYearX64,
        uint256 multiplierPerYearX64,
        uint256 jumpMultiplierPerYearX64,
        uint256 _kinkX64
    ) {
        setValues(baseRatePerYearX64, multiplierPerYearX64, jumpMultiplierPerYearX64, _kinkX64);
    }

    /// @notice Returns utilization rate X64 given cash and debt
    /// @param cash Current available cash
    /// @param debt Current debt
    /// @return Utilization rate between 0 and Q64
    function getUtilizationRateX64(uint256 cash, uint256 debt) public pure returns (uint256) {
        if (debt == 0) {
            return 0;
        }
        return debt * Q64 / (cash + debt);
    }

    /// @notice Returns interest rates X64 given cash and debt
    /// @param cash Current available cash
    /// @param debt Current debt
    /// @return borrowRateX64 borrow rate multiplied by Q64
    /// @return supplyRateX64 supply rate multiplied by Q64
    function getRatesPerSecondX64(uint256 cash, uint256 debt)
        public
        view
        override
        returns (uint256 borrowRateX64, uint256 supplyRateX64)
    {
        uint256 utilizationRateX64 = getUtilizationRateX64(cash, debt);

        if (utilizationRateX64 <= kinkX64) {
            borrowRateX64 = (utilizationRateX64 * multiplierPerSecondX64 / Q64) + baseRatePerSecondX64;
        } else {
            uint256 normalRateX64 = (uint256(kinkX64) * multiplierPerSecondX64 / Q64) + baseRatePerSecondX64;
            uint256 excessUtilX64 = utilizationRateX64 - kinkX64;
            borrowRateX64 = (excessUtilX64 * jumpMultiplierPerSecondX64 / Q64) + normalRateX64;
        }

        supplyRateX64 = utilizationRateX64 * borrowRateX64 / Q64;
    }

    /// @notice Update interest rate values (onlyOwner)
    /// @param baseRatePerYearX64 Base rate per year multiplied by Q64
    /// @param multiplierPerYearX64 Multiplier for utilization rate below kink multiplied by Q64
    /// @param jumpMultiplierPerYearX64 Multiplier for utilization rate above kink multiplied by Q64
    /// @param _kinkX64 Kink percentage multiplied by Q64
    function setValues(
        uint256 baseRatePerYearX64,
        uint256 multiplierPerYearX64,
        uint256 jumpMultiplierPerYearX64,
        uint256 _kinkX64
    ) public onlyOwner {
        if (
            baseRatePerYearX64 > MAX_BASE_RATE_X64 || multiplierPerYearX64 > MAX_MULTIPLIER_X64
                || jumpMultiplierPerYearX64 > MAX_MULTIPLIER_X64
        ) {
            revert InvalidConfig();
        }

        baseRatePerSecondX64 = SafeCast.toUint64(baseRatePerYearX64 / YEAR_SECS);
        multiplierPerSecondX64 = SafeCast.toUint64(multiplierPerYearX64 / YEAR_SECS);
        jumpMultiplierPerSecondX64 = SafeCast.toUint64(jumpMultiplierPerYearX64 / YEAR_SECS);
        kinkX64 = SafeCast.toUint64(_kinkX64);

        emit SetValues(baseRatePerYearX64, multiplierPerYearX64, jumpMultiplierPerYearX64, _kinkX64);
    }
}
