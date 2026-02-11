// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {CollateralRatiosRebalanceAdapterTest} from "./CollateralRatiosRebalanceAdapter.t.sol";
import {ILeverageToken} from "src/interfaces/ILeverageToken.sol";
import {LeverageTokenState} from "src/types/DataTypes.sol";

contract IsEligibleForRebalanceTest is CollateralRatiosRebalanceAdapterTest {
    function test_isEligibleForRebalance_WhenLeverageTokenIsEmpty() public {
        LeverageTokenState memory state =
            LeverageTokenState({collateralInDebtAsset: 100 ether, debt: 100 ether, equity: 0, collateralRatio: 1e18});

        _mockTotalSupply(0);

        // It is not eligible because total supply is zero
        bool isEligible = rebalanceAdapter.isEligibleForRebalance(leverageToken, state, address(this));
        assertFalse(isEligible);

        _mockTotalSupply(1);
        state = LeverageTokenState({collateralInDebtAsset: 0, debt: 100 ether, equity: 0, collateralRatio: 1e18});

        isEligible = rebalanceAdapter.isEligibleForRebalance(leverageToken, state, address(this));
        assertFalse(isEligible);
    }

    function test_isEligibleForRebalance_WhenCollateralRatioTooLow() public {
        LeverageTokenState memory state =
            LeverageTokenState({collateralInDebtAsset: 100 ether, debt: 100 ether, equity: 0, collateralRatio: 1e18});

        // Mock total supply to non zero
        _mockTotalSupply(1);

        bool isEligible = rebalanceAdapter.isEligibleForRebalance(leverageToken, state, address(this));
        assertTrue(isEligible);
    }

    function test_isEligibleForRebalance_WhenCollateralRatioTooHigh() public {
        LeverageTokenState memory state = LeverageTokenState({
            collateralInDebtAsset: 300 ether,
            debt: 100 ether,
            equity: 200 ether,
            collateralRatio: 3e18
        });

        // Mock total supply to non zero
        _mockTotalSupply(1);

        bool isEligible = rebalanceAdapter.isEligibleForRebalance(leverageToken, state, address(this));
        assertTrue(isEligible);
    }

    function test_isEligibleForRebalance_WhenCollateralRatioInRange() public {
        LeverageTokenState memory state = LeverageTokenState({
            collateralInDebtAsset: 200 ether,
            debt: 100 ether,
            equity: 100 ether,
            collateralRatio: 2e18
        });

        // Mock total supply to non zero
        _mockTotalSupply(1);

        bool isEligible = rebalanceAdapter.isEligibleForRebalance(leverageToken, state, address(this));
        assertFalse(isEligible);
    }

    /// forge-config: default.fuzz.runs = 1
    function testFuzz_isEligibleForRebalance(uint256 collateralRatio) public {
        uint256 minRatio = rebalanceAdapter.getLeverageTokenMinCollateralRatio();
        uint256 maxRatio = rebalanceAdapter.getLeverageTokenMaxCollateralRatio();

        LeverageTokenState memory state = LeverageTokenState({
            collateralInDebtAsset: 100 ether,
            debt: 100 ether,
            equity: 0,
            collateralRatio: collateralRatio
        });

        // Mock total supply to non zero
        _mockTotalSupply(1);

        bool isEligible = rebalanceAdapter.isEligibleForRebalance(leverageToken, state, address(this));
        bool shouldBeEligible = collateralRatio < minRatio || collateralRatio > maxRatio;

        assertEq(isEligible, shouldBeEligible);
    }

    function _mockTotalSupply(uint256 totalSupply) internal {
        vm.mockCall(
            address(leverageToken), abi.encodeWithSelector(IERC20.totalSupply.selector), abi.encode(totalSupply)
        );
    }
}
