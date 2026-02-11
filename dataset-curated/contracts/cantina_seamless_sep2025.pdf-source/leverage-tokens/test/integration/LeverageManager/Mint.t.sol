// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

// Internal imports
import {MorphoLendingAdapter} from "src/lending/MorphoLendingAdapter.sol";
import {LeverageManagerTest} from "./LeverageManager.t.sol";
import {ActionData, LeverageTokenState, ExternalAction} from "src/types/DataTypes.sol";

contract LeverageManagerMintTest is LeverageManagerTest {
    /// @dev In this block price on oracle 3392.292471591441746049801068
    function testFork_mint_NoFee() public {
        uint256 sharesToMint = 10 ether;
        uint256 collateralToAdd = 2 * sharesToMint;
        uint256 debtToBorrow = 33922_924715; // 33922.924715

        _mint(user, sharesToMint, collateralToAdd);

        assertEq(leverageToken.balanceOf(user), sharesToMint);
        assertEq(WETH.balanceOf(user), 0);
        assertEq(USDC.balanceOf(user), debtToBorrow);

        assertEq(morphoLendingAdapter.getCollateral(), collateralToAdd);
        assertGe(morphoLendingAdapter.getDebt(), debtToBorrow);
        assertLe(morphoLendingAdapter.getDebt(), debtToBorrow + 1);
    }

    function testFork_mint_WithFees() public {
        uint256 treasuryActionFee = 10_00; // 10%
        leverageManager.setTreasuryActionFee(ExternalAction.Mint, treasuryActionFee);

        uint256 tokenActionFee = 10_00; // 10%
        leverageToken = _createNewLeverageToken(BASE_RATIO, 2 * BASE_RATIO, 3 * BASE_RATIO, tokenActionFee, 0);

        uint256 managementFee = 10_00; // 10%
        leverageManager.setManagementFee(leverageToken, managementFee);

        morphoLendingAdapter =
            MorphoLendingAdapter(address(leverageManager.getLeverageTokenLendingAdapter(leverageToken)));

        uint256 sharesToMint = 8.1 ether;
        uint256 collateralToAdd = 20 ether;

        _mint(user, sharesToMint, collateralToAdd);

        // 10% of equity is for diluting leverage token shares, and 10% of the remaining shares
        // after subtracting the dilution is for the treasury fee (10 * 0.9) * 0.9 = 8.1
        assertEq(leverageToken.balanceOf(user), sharesToMint);
        assertEq(leverageToken.balanceOf(treasury), 0.9 ether);
        assertEq(leverageToken.balanceOf(user) + leverageToken.balanceOf(treasury), leverageToken.totalSupply());
        // Some slight deviation from 10 ether is expected due to interest accrual in morpho and rounding errors
        assertEq(morphoLendingAdapter.getEquityInCollateralAsset(), 9.999999999974771473 ether);

        uint256 collateralRatio = leverageManager.getLeverageTokenState(leverageToken).collateralRatio;
        assertEq(collateralRatio, 1.999999999970521409e18);

        // One year passes, same mint amount occurs
        skip(SECONDS_ONE_YEAR);

        // CR goes down due to morpho borrow interest
        collateralRatio = leverageManager.getLeverageTokenState(leverageToken).collateralRatio;
        assertEq(collateralRatio, 1.974502635802161566e18);

        ActionData memory previewData = leverageManager.previewMint(leverageToken, sharesToMint);

        assertEq(previewData.shares, sharesToMint);
        // collateralToAdd is higher than before due to higher leverage from CR going down
        assertEq(previewData.collateral, 20.202020202020202021 ether);
        assertEq(previewData.tokenFee, 1 ether);
        assertEq(previewData.treasuryFee, 0.9 ether);

        // Preview data is the same after charging management fee but treasury balance of LT increases by 0.9 ether (10% of total supply)
        leverageManager.chargeManagementFee(leverageToken);
        previewData = leverageManager.previewMint(leverageToken, sharesToMint);

        assertEq(previewData.shares, sharesToMint);
        assertEq(previewData.collateral, 20.202020202020202021 ether);
        assertEq(previewData.tokenFee, 1 ether);
        assertEq(previewData.treasuryFee, 0.9 ether);
        assertEq(leverageToken.balanceOf(treasury), 1.8 ether);

        // Mint again
        _mint(user, sharesToMint, previewData.collateral);

        assertEq(leverageToken.balanceOf(user), 8.1 ether + previewData.shares);
        assertEq(leverageToken.balanceOf(treasury), 1.8 ether + previewData.treasuryFee);
        assertEq(leverageToken.totalSupply(), leverageToken.balanceOf(user) + leverageToken.balanceOf(treasury));

        uint256 collateralRatioAfter = leverageManager.getLeverageTokenState(leverageToken).collateralRatio;
        assertGe(collateralRatioAfter, collateralRatio);
        assertEq(collateralRatioAfter, 1.974502635847067912e18);
    }

    function testFuzzFork_mint(uint256 sharesToMintA, uint256 sharesToMintB, uint256 sharesToMintC, uint64 deltaTime)
        public
    {
        sharesToMintA = bound(sharesToMintA, 1e9, 100 ether);
        sharesToMintB = bound(sharesToMintB, 1e9, 100 ether);
        sharesToMintC = bound(sharesToMintC, 1e9, 100 ether);
        deltaTime = uint64(bound(deltaTime, 0, 365 days));

        ActionData memory previewData = leverageManager.previewMint(leverageToken, sharesToMintA);

        ActionData memory mintDataA = _mint(user, sharesToMintA, previewData.collateral);

        assertEq(mintDataA.shares, sharesToMintA);
        assertEq(mintDataA.collateral, previewData.collateral);
        assertEq(mintDataA.debt, previewData.debt);
        assertEq(mintDataA.tokenFee, previewData.tokenFee);
        assertEq(mintDataA.treasuryFee, previewData.treasuryFee);

        skip(deltaTime);

        previewData = leverageManager.previewMint(leverageToken, sharesToMintB);

        ActionData memory mintDataB = _mint(user, sharesToMintB, previewData.collateral);

        assertEq(mintDataB.shares, sharesToMintB);
        assertEq(mintDataB.collateral, previewData.collateral);
        assertEq(mintDataB.debt, previewData.debt);
        assertEq(mintDataB.tokenFee, previewData.tokenFee);
        assertEq(mintDataB.treasuryFee, previewData.treasuryFee);

        skip(deltaTime);

        previewData = leverageManager.previewMint(leverageToken, sharesToMintC);

        ActionData memory mintDataC = _mint(user, sharesToMintC, previewData.collateral);

        assertEq(mintDataC.shares, sharesToMintC);
        assertEq(mintDataC.collateral, previewData.collateral);
        assertEq(mintDataC.debt, previewData.debt);
        assertEq(mintDataC.tokenFee, previewData.tokenFee);
        assertEq(mintDataC.treasuryFee, previewData.treasuryFee);

        assertEq(leverageToken.balanceOf(user), mintDataA.shares + mintDataB.shares + mintDataC.shares);
        assertEq(
            leverageManager.getLeverageTokenLendingAdapter(leverageToken).getCollateral(),
            mintDataA.collateral + mintDataB.collateral + mintDataC.collateral
        );
    }
}
