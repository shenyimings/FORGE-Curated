// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

// Dependency imports
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// Internal imports
import {FeeManagerTest} from "test/unit/FeeManager/FeeManager.t.sol";
import {MockERC20} from "test/unit/mock/MockERC20.sol";

contract ChargeTreasuryFeeTest is FeeManagerTest {
    function test_chargeTreasuryFee() public {
        IERC20 token = new MockERC20();
        uint256 treasuryFeeAmount = 100;
        address treasury = makeAddr("treasury");

        _setTreasury(feeManagerRole, treasury);
        deal(address(token), address(feeManager), treasuryFeeAmount);

        feeManager.exposed_chargeTreasuryFee(token, treasuryFeeAmount);

        assertEq(token.balanceOf(treasury), treasuryFeeAmount);
    }

    function test_chargeTreasuryFee_NoTreasury() public {
        IERC20 token = new MockERC20();
        uint256 treasuryFeeAmount = 100;

        _setTreasury(feeManagerRole, address(0));
        deal(address(token), address(feeManager), treasuryFeeAmount);

        feeManager.exposed_chargeTreasuryFee(token, treasuryFeeAmount);

        // Fee is not transferred
        assertEq(token.balanceOf(address(feeManager)), treasuryFeeAmount);
        assertEq(token.balanceOf(address(0)), 0);
    }
}
