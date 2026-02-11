// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {SafePct} from "../../utils/library/SafePct.sol";


library SettingsValidators {
    using SafePct for uint256;

    error FactorsNotIncreasing();
    error VaultCollateralFactorHigherThanTotal();
    error FactorNotAboveOne();
    error AtLeastOneFactorRequired();
    error LengthsNotEqual();
    error ValueTooHigh();

    uint256 internal constant MAXIMUM_PROOF_WINDOW = 1 days;

    function validateTimeForPayment(
        uint256 _underlyingBlocks,
        uint256 _underlyingSeconds,
        uint256 _averageBlockTimeMS
    )
        internal pure
    {
        require(_underlyingSeconds <= MAXIMUM_PROOF_WINDOW, ValueTooHigh());
        require(_underlyingBlocks * _averageBlockTimeMS / 1000 <= MAXIMUM_PROOF_WINDOW, ValueTooHigh());
    }

    function validateLiquidationFactors(
        uint256[] memory liquidationFactors,
        uint256[] memory vaultCollateralFactors
    )
        internal pure
    {
        require(liquidationFactors.length == vaultCollateralFactors.length, LengthsNotEqual());
        require(liquidationFactors.length >= 1, AtLeastOneFactorRequired());
        for (uint256 i = 0; i < liquidationFactors.length; i++) {
            // per item validations
            require(liquidationFactors[i] > SafePct.MAX_BIPS, FactorNotAboveOne());
            require(vaultCollateralFactors[i] <= liquidationFactors[i], VaultCollateralFactorHigherThanTotal());
            require(i == 0 || liquidationFactors[i] > liquidationFactors[i - 1], FactorsNotIncreasing());
        }
    }
}