// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

// Internal imports
import {FeeManagerTest} from "test/unit/FeeManager/FeeManager.t.sol";

contract GetFeeAdjustedTotalSupplyTest is FeeManagerTest {
    function test_getFeeAdjustedTotalSupply() public {
        _setManagementFee(feeManagerRole, leverageToken, 0.1e4); // 10% management fee
        feeManager.chargeManagementFee(leverageToken);

        uint256 totalSupply = 1000;
        leverageToken.mint(address(this), totalSupply);

        // No time has passed yet, so no management fee should be accrued
        uint256 feeAdjustedTotalSupply = feeManager.getFeeAdjustedTotalSupply(leverageToken);
        assertEq(feeAdjustedTotalSupply, totalSupply);

        skip(SECONDS_ONE_YEAR); // One year passes

        uint256 accruedManagementFee = feeManager.exposed_getAccruedManagementFee(leverageToken, totalSupply);
        assertEq(accruedManagementFee, 100);

        // 10% of total supply should be included in the fee adjusted total supply as the accrued management fee
        feeAdjustedTotalSupply = feeManager.getFeeAdjustedTotalSupply(leverageToken);
        assertEq(feeAdjustedTotalSupply, totalSupply + accruedManagementFee);

        // Charging the management fee should not affect the fee adjusted total supply if no time has passed
        feeManager.chargeManagementFee(leverageToken);
        feeAdjustedTotalSupply = feeManager.getFeeAdjustedTotalSupply(leverageToken);
        assertEq(feeAdjustedTotalSupply, totalSupply + accruedManagementFee);
    }

    function test_getFeeAdjustedTotalSupply_MultipleYears() public {
        _setManagementFee(feeManagerRole, leverageToken, 0.1e4); // 10% management fee
        feeManager.chargeManagementFee(leverageToken);

        uint256 totalSupply = 1000;
        leverageToken.mint(address(this), totalSupply);

        // No time has passed yet, so no management fee should be accrued
        uint256 feeAdjustedTotalSupply = feeManager.getFeeAdjustedTotalSupply(leverageToken);
        assertEq(feeAdjustedTotalSupply, totalSupply);

        skip(SECONDS_ONE_YEAR); // One year passes

        uint256 accruedManagementFee = feeManager.exposed_getAccruedManagementFee(leverageToken, totalSupply);
        assertEq(accruedManagementFee, 100);

        // 10% of total supply should be included in the fee adjusted total supply as the accrued management fee
        feeAdjustedTotalSupply = feeManager.getFeeAdjustedTotalSupply(leverageToken);
        assertEq(feeAdjustedTotalSupply, totalSupply + accruedManagementFee);

        skip(SECONDS_ONE_YEAR); // Another year passes

        accruedManagementFee = feeManager.exposed_getAccruedManagementFee(leverageToken, totalSupply);
        assertEq(accruedManagementFee, 200);

        feeAdjustedTotalSupply = feeManager.getFeeAdjustedTotalSupply(leverageToken);
        assertEq(feeAdjustedTotalSupply, totalSupply + accruedManagementFee);
    }
}
