// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

// Internal imports
import {IFeeManager} from "src/interfaces/IFeeManager.sol";
import {FeeManagerTest} from "test/unit/FeeManager/FeeManager.t.sol";

contract ChargeManagementFeeTest is FeeManagerTest {
    function test_chargeManagementFee() public {
        _setManagementFee(feeManagerRole, leverageToken, 0.1e4); // 10% management fee

        uint256 totalSupply = 1000;
        leverageToken.mint(address(this), totalSupply);

        vm.expectEmit(true, true, true, true);
        emit IFeeManager.ManagementFeeCharged(leverageToken, 0);
        feeManager.chargeManagementFee(leverageToken);

        uint256 totalSupplyAfter = leverageToken.totalSupply();
        assertEq(totalSupplyAfter, totalSupply); // No time has passed yet, total supply should be the same

        skip(SECONDS_ONE_YEAR); // One year passes and management fee is charged
        vm.expectEmit(true, true, true, true);
        emit IFeeManager.ManagementFeeCharged(leverageToken, 100);
        feeManager.chargeManagementFee(leverageToken);

        // 10% of 1000 total supply should be minted to the treasury and the last management fee accrual timestamp
        // should be updated
        totalSupplyAfter = leverageToken.totalSupply();
        assertEq(totalSupplyAfter, totalSupply + 100);
        assertEq(leverageToken.balanceOf(treasury), 100);
        assertEq(feeManager.getLastManagementFeeAccrualTimestamp(leverageToken), block.timestamp);

        // Another year passes and management fee is charged again
        skip(SECONDS_ONE_YEAR);
        vm.expectEmit(true, true, true, true);
        emit IFeeManager.ManagementFeeCharged(leverageToken, 110);
        feeManager.chargeManagementFee(leverageToken);

        // 10% of 1100 total supply should be minted to the treasury and the last management fee accrual timestamp
        // should be updated
        totalSupplyAfter = leverageToken.totalSupply();
        assertEq(totalSupplyAfter, totalSupply + 100 + 110);
        assertEq(leverageToken.balanceOf(treasury), 100 + 110);
        assertEq(feeManager.getLastManagementFeeAccrualTimestamp(leverageToken), block.timestamp);
    }

    function test_chargeManagementFee_ZeroFee() public {
        _setManagementFee(feeManagerRole, leverageToken, 0);

        uint256 totalSupply = 1000;
        leverageToken.mint(address(this), totalSupply);

        feeManager.chargeManagementFee(leverageToken);

        skip(SECONDS_ONE_YEAR);

        feeManager.chargeManagementFee(leverageToken);

        assertEq(leverageToken.balanceOf(treasury), 0);
        assertEq(leverageToken.totalSupply(), totalSupply);
    }
}
