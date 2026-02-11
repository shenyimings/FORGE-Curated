// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

// External imports
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

// Internal imports
import {ExternalAction} from "src/types/DataTypes.sol";
import {FeeManagerTest} from "test/unit/FeeManager/FeeManager.t.sol";

contract ComputeTreasuryFeeTest is FeeManagerTest {
    function testFuzz_computeTreasuryFee_RoundsUp(uint8 actionNum, uint128 shares, uint256 treasuryActionFee) public {
        ExternalAction action = ExternalAction(actionNum % 2);
        treasuryActionFee = bound(treasuryActionFee, 0, MAX_ACTION_FEE);
        _setTreasuryActionFee(feeManagerRole, action, treasuryActionFee);

        uint256 treasuryFee = feeManager.exposed_computeTreasuryFee(action, shares);
        assertEq(treasuryFee, Math.mulDiv(shares, treasuryActionFee, MAX_BPS, Math.Rounding.Ceil));
        assertLe(treasuryFee, shares); // Treasury fee is less than or equal to the shares
    }
}
