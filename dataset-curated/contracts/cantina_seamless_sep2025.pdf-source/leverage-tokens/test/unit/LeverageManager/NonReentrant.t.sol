// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

// Dependency imports
import {ReentrancyGuardTransientUpgradeable} from
    "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardTransientUpgradeable.sol";

// Internal imports
import {ILendingAdapter} from "src/interfaces/ILendingAdapter.sol";
import {IRebalanceAdapter} from "src/interfaces/IRebalanceAdapter.sol";
import {LeverageTokenConfig} from "src/types/DataTypes.sol";
import {LeverageManagerTest} from "./LeverageManager.t.sol";
import {LeverageManagerHarness} from "../harness/LeverageManagerHarness.t.sol";
import {MockERC20, ReentrancyCallType} from "../mock/MockERC20.sol";
import {MockLendingAdapter} from "../mock/MockLendingAdapter.sol";
import {MockRebalanceAdapter} from "../mock/MockRebalanceAdapter.sol";

contract NonReentrantTest is LeverageManagerTest {
    function test_nonReentrant_RevertIf_Reentrancy() public {
        MockERC20 reentrancyToken = new MockERC20();
        reentrancyToken.mockSetDecimals(18);
        reentrancyToken.mockSetLeverageManager(leverageManager);

        lendingAdapter = new MockLendingAdapter(address(reentrancyToken), address(debtToken), address(this));

        leverageToken = _createNewLeverageToken(
            manager,
            2e18,
            LeverageTokenConfig({
                lendingAdapter: ILendingAdapter(address(lendingAdapter)),
                rebalanceAdapter: IRebalanceAdapter(address(rebalanceAdapter)),
                mintTokenFee: 0,
                redeemTokenFee: 0
            }),
            address(reentrancyToken),
            address(debtToken),
            "dummy name",
            "dummy symbol"
        );

        uint256 sharesToMint = 10 ether;

        deal(address(reentrancyToken), address(this), type(uint256).max);
        deal(address(debtToken), address(this), type(uint256).max);
        reentrancyToken.approve(address(leverageManager), type(uint256).max);

        // Transient storage for reentrancy guard is false outside of any tx execution stack on the LeverageManager
        assertEq(LeverageManagerHarness(address(leverageManager)).exposed_getReentrancyGuardTransientStorage(), false);

        // mint is non-reentrant
        reentrancyToken.mockSetReentrancyCallType(ReentrancyCallType.Mint);
        vm.expectRevert(
            abi.encodeWithSelector(ReentrancyGuardTransientUpgradeable.ReentrancyGuardReentrantCall.selector)
        );
        leverageManager.mint(leverageToken, sharesToMint, type(uint256).max);

        // Transient storage slot is reset to false
        assertEq(LeverageManagerHarness(address(leverageManager)).exposed_getReentrancyGuardTransientStorage(), false);

        // redeem is non-reentrant
        reentrancyToken.mockSetReentrancyCallType(ReentrancyCallType.Redeem);
        vm.expectRevert(
            abi.encodeWithSelector(ReentrancyGuardTransientUpgradeable.ReentrancyGuardReentrantCall.selector)
        );
        leverageManager.mint(leverageToken, sharesToMint, type(uint256).max);

        // Transient storage slot is reset to false
        assertEq(LeverageManagerHarness(address(leverageManager)).exposed_getReentrancyGuardTransientStorage(), false);

        // rebalance is non-reentrant
        reentrancyToken.mockSetReentrancyCallType(ReentrancyCallType.Rebalance);
        vm.expectRevert(
            abi.encodeWithSelector(ReentrancyGuardTransientUpgradeable.ReentrancyGuardReentrantCall.selector)
        );
        leverageManager.mint(leverageToken, sharesToMint, type(uint256).max);

        // Transient storage slot is reset to false
        assertEq(LeverageManagerHarness(address(leverageManager)).exposed_getReentrancyGuardTransientStorage(), false);

        // createNewLeverageToken is non-reentrant
        reentrancyToken.mockSetReentrancyCallType(ReentrancyCallType.CreateNewLeverageToken);
        vm.expectRevert(
            abi.encodeWithSelector(ReentrancyGuardTransientUpgradeable.ReentrancyGuardReentrantCall.selector)
        );
        leverageManager.mint(leverageToken, sharesToMint, type(uint256).max);

        // Transient storage slot is reset to false
        assertEq(LeverageManagerHarness(address(leverageManager)).exposed_getReentrancyGuardTransientStorage(), false);
    }
}
