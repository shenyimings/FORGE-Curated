// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

// Dependency imports
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// Internal imports
import {FeeManagerTest} from "test/unit/FeeManager/FeeManager.t.sol";

contract ChargeTreasuryFeeTest is FeeManagerTest {
    /// forge-config: default.fuzz.runs = 1
    function testFuzz_chargeTreasuryFee(uint256 shares) public {
        shares = bound(shares, 1, type(uint256).max);

        vm.prank(feeManagerRole);
        feeManager.setTreasury(treasury);

        vm.expectEmit(true, true, true, true);
        emit IERC20.Transfer(address(0), treasury, shares);
        feeManager.exposed_chargeTreasuryFee(leverageToken, shares);

        assertEq(leverageToken.balanceOf(treasury), shares);
    }

    function test_chargeTreasuryFee_ZeroShares() public {
        vm.prank(feeManagerRole);
        feeManager.setTreasury(treasury);

        feeManager.exposed_chargeTreasuryFee(leverageToken, 0);
        assertEq(leverageToken.balanceOf(treasury), 0);
    }
}
