// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {ILeverageToken} from "src/interfaces/ILeverageToken.sol";
import {LeverageTokenState} from "src/types/DataTypes.sol";

contract MockRebalanceAdapter {
    bool public isEligible;
    bool public isValid;

    mapping(ILeverageToken => uint256) public leverageTokenMinCollateralRatio;
    mapping(ILeverageToken => uint256) public leverageTokenMaxCollateralRatio;

    function getLeverageTokenMinCollateralRatio(ILeverageToken leverageToken) external view returns (uint256) {
        return leverageTokenMinCollateralRatio[leverageToken];
    }

    function getLeverageTokenMaxCollateralRatio(ILeverageToken leverageToken) external view returns (uint256) {
        return leverageTokenMaxCollateralRatio[leverageToken];
    }

    function mockSetLeverageTokenMinCollateralRatio(ILeverageToken leverageToken, uint256 minCollateralRatio) public {
        leverageTokenMinCollateralRatio[leverageToken] = minCollateralRatio;
    }

    function mockSetLeverageTokenMaxCollateralRatio(ILeverageToken leverageToken, uint256 maxCollateralRatio) public {
        leverageTokenMaxCollateralRatio[leverageToken] = maxCollateralRatio;
    }

    function mockIsEligibleForRebalance(ILeverageToken, bool _isEligible) public {
        isEligible = _isEligible;
    }

    function mockIsValidStateAfterRebalance(ILeverageToken, bool _isValid) public {
        isValid = _isValid;
    }

    function isEligibleForRebalance(ILeverageToken, LeverageTokenState memory, address) external view returns (bool) {
        return isEligible;
    }

    function isStateAfterRebalanceValid(ILeverageToken, LeverageTokenState memory) external view returns (bool) {
        return isValid;
    }
}
