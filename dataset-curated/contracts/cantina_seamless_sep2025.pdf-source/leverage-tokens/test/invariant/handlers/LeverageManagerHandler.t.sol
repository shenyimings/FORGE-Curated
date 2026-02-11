// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

// Forge imports
import {Test} from "forge-std/Test.sol";

// Dependency imports
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// Internal imports
import {ILendingAdapter} from "src/interfaces/ILendingAdapter.sol";
import {ILeverageToken} from "src/interfaces/ILeverageToken.sol";
import {IMorphoLendingAdapter} from "src/interfaces/IMorphoLendingAdapter.sol";
import {ActionData, LeverageTokenState} from "src/types/DataTypes.sol";
import {LeverageManagerHarness} from "test/unit/harness/LeverageManagerHarness.t.sol";
import {MockMorphoOracle} from "test/unit/mock/MockMorphoOracle.sol";

contract LeverageManagerHandler is Test {
    enum ActionType {
        // Invariants are checked before any calls are made as well, so we need a specific identifer for it for filtering
        Initial,
        Mint,
        AddCollateral,
        RepayDebt,
        Redeem,
        UpdateOraclePrice
    }

    struct AddCollateralActionData {
        uint256 collateral;
    }

    struct MintActionData {
        ILeverageToken leverageToken;
        uint256 equityInCollateralAsset;
        uint256 equityInDebtAsset;
        ActionData preview;
    }

    struct RepayDebtActionData {
        uint256 debt;
    }

    struct RedeemActionData {
        ILeverageToken leverageToken;
        uint256 equityInCollateralAsset;
        uint256 equityInDebtAsset;
        ActionData preview;
    }

    struct LeverageTokenStateData {
        ILeverageToken leverageToken;
        ActionType actionType;
        uint256 collateral;
        uint256 collateralInDebtAsset;
        uint256 debt;
        uint256 equityInCollateralAsset;
        uint256 equityInDebtAsset;
        uint256 collateralRatio;
        uint256 collateralRatioUsingDebtNormalized;
        uint256 totalSupply;
        bytes actionData;
    }

    uint256 public BASE_RATIO;

    LeverageManagerHarness public leverageManager;
    ILeverageToken[] public leverageTokens;
    address[] public actors;

    address public currentActor;
    ILeverageToken public currentLeverageToken;

    LeverageTokenStateData public leverageTokenStateBefore;

    modifier useActor() {
        currentActor = pickActor();
        vm.startPrank(currentActor);
        _;
        vm.stopPrank();
    }

    modifier useLeverageToken() {
        currentLeverageToken = pickLeverageToken();
        _;
    }

    constructor(
        LeverageManagerHarness _leverageManager,
        ILeverageToken[] memory _leverageTokens,
        address[] memory _actors
    ) {
        leverageManager = _leverageManager;
        leverageTokens = _leverageTokens;
        actors = _actors;

        BASE_RATIO = leverageManager.BASE_RATIO();

        vm.label(address(leverageManager), "leverageManager");

        for (uint256 i = 0; i < _leverageTokens.length; i++) {
            vm.label(
                address(_leverageTokens[i]),
                string.concat("leverageToken-", Strings.toHexString(uint256(uint160(address(_leverageTokens[i]))), 20))
            );
        }
    }

    function mint(uint256 seed) public useLeverageToken useActor {
        uint256 equityForMint = _boundEquityForMint(currentLeverageToken, seed);

        ActionData memory preview = leverageManager.previewMint(currentLeverageToken, equityForMint);
        ILendingAdapter lendingAdapter = leverageManager.getLeverageTokenLendingAdapter(currentLeverageToken);

        _saveLeverageTokenState(
            currentLeverageToken,
            ActionType.Mint,
            abi.encode(
                MintActionData({
                    leverageToken: currentLeverageToken,
                    equityInCollateralAsset: equityForMint,
                    equityInDebtAsset: lendingAdapter.convertCollateralToDebtAsset(equityForMint),
                    preview: preview
                })
            )
        );

        IERC20 collateralAsset = leverageManager.getLeverageTokenCollateralAsset(currentLeverageToken);
        deal(address(collateralAsset), currentActor, type(uint256).max);
        collateralAsset.approve(address(leverageManager), type(uint256).max);
        leverageManager.mint(currentLeverageToken, equityForMint, 0);
    }

    /// @dev Simulates someone adding collateral to the position held by the leverage token directly, not through the LeverageManager.
    function addCollateral(uint256 seed) public useLeverageToken {
        IMorphoLendingAdapter lendingAdapter =
            IMorphoLendingAdapter(address(leverageManager.getLeverageTokenLendingAdapter(currentLeverageToken)));

        uint256 collateral = lendingAdapter.getCollateral();
        (, address collateralAsset,,,) = lendingAdapter.marketParams();

        uint256 collateralToAdd = bound(seed, 0, type(uint128).max - collateral);

        _saveLeverageTokenState(
            currentLeverageToken,
            ActionType.AddCollateral,
            abi.encode(AddCollateralActionData({collateral: collateralToAdd}))
        );

        deal(address(collateralAsset), address(this), collateralToAdd);
        IERC20(collateralAsset).approve(address(lendingAdapter), collateralToAdd);
        lendingAdapter.addCollateral(collateralToAdd);
    }

    /// @dev Simulates someone repaying debt from the position held by the leverage token directly, not through the LeverageManager.
    function repayDebt(uint256 seed) public useLeverageToken {
        IMorphoLendingAdapter lendingAdapter =
            IMorphoLendingAdapter(address(leverageManager.getLeverageTokenLendingAdapter(currentLeverageToken)));

        uint256 debt = lendingAdapter.getDebt();
        (address debtAsset,,,,) = lendingAdapter.marketParams();

        uint256 debtToRemove = bound(seed, 0, debt);

        _saveLeverageTokenState(
            currentLeverageToken, ActionType.RepayDebt, abi.encode(RepayDebtActionData({debt: debtToRemove}))
        );

        deal(address(debtAsset), address(this), debtToRemove);
        IERC20(debtAsset).approve(address(lendingAdapter), debtToRemove);
        lendingAdapter.repay(debtToRemove);
    }

    function redeem(uint256 seed) public useLeverageToken useActor {
        uint256 equityForRedeem = _boundEquityForRedeem(currentLeverageToken, currentActor, seed);

        ActionData memory preview = leverageManager.previewRedeem(currentLeverageToken, equityForRedeem);
        ILendingAdapter lendingAdapter = leverageManager.getLeverageTokenLendingAdapter(currentLeverageToken);

        _saveLeverageTokenState(
            currentLeverageToken,
            ActionType.Redeem,
            abi.encode(
                RedeemActionData({
                    leverageToken: currentLeverageToken,
                    equityInCollateralAsset: equityForRedeem,
                    equityInDebtAsset: lendingAdapter.convertCollateralToDebtAsset(equityForRedeem),
                    preview: preview
                })
            )
        );

        IERC20 debtAsset = leverageManager.getLeverageTokenDebtAsset(currentLeverageToken);
        deal(address(debtAsset), currentActor, type(uint256).max);
        debtAsset.approve(address(leverageManager), type(uint256).max);
        leverageManager.redeem(currentLeverageToken, equityForRedeem, currentLeverageToken.balanceOf(currentActor));
    }

    /// @dev Simulates updates to the oracle used by the lending adapter of a leverage token
    function updateOraclePrice(uint256 seed) public useLeverageToken {
        IMorphoLendingAdapter lendingAdapter =
            IMorphoLendingAdapter(address(leverageManager.getLeverageTokenLendingAdapter(currentLeverageToken)));

        (,, address oracle,,) = lendingAdapter.marketParams();

        uint256 newPrice = bound(seed, 0, type(uint256).max);
        MockMorphoOracle(oracle).setPrice(newPrice);

        _saveLeverageTokenState(currentLeverageToken, ActionType.UpdateOraclePrice, "");
    }

    function convertToAssets(ILeverageToken leverageToken, uint256 shares) public view returns (uint256) {
        uint256 equityInCollateralAsset =
            leverageManager.getLeverageTokenLendingAdapter(leverageToken).getEquityInCollateralAsset();

        if (leverageToken.totalSupply() == 0 && equityInCollateralAsset == 0) {
            return shares;
        }

        return Math.mulDiv(shares, equityInCollateralAsset, leverageToken.totalSupply(), Math.Rounding.Floor);
    }

    function getLeverageTokenStateBefore() public view returns (LeverageTokenStateData memory) {
        return leverageTokenStateBefore;
    }

    function pickActor() public returns (address) {
        return actors[bound(vm.randomUint(), 0, actors.length - 1)];
    }

    function pickLeverageToken() public returns (ILeverageToken) {
        return leverageTokens[bound(vm.randomUint(), 0, leverageTokens.length - 1)];
    }

    /// @dev Bounds the amount of equity to deposit based on the maximum collateral and debt that can be added to a leverage token
    ///      due to overflow limits
    function _boundEquityForMint(ILeverageToken leverageToken, uint256 seed) internal view returns (uint256) {
        LeverageTokenState memory stateBefore = leverageManager.getLeverageTokenState(leverageToken);

        uint256 maxCollateralAmount = type(uint128).max
            - leverageManager.getLeverageTokenLendingAdapter(leverageToken).convertDebtToCollateralAsset(
                stateBefore.collateralInDebtAsset
            );
        // Bound the amount of equity to deposit based on the maximum collateral that can be added to avoid overflow
        bool shouldFollowInitialRatio = leverageToken.totalSupply() == 0 || stateBefore.debt == 0;
        uint256 collateralRatioForMint = shouldFollowInitialRatio
            ? leverageManager.getLeverageTokenInitialCollateralRatio(leverageToken)
            : stateBefore.collateralRatio;

        // Divide first to avoid overflow
        uint256 maxEquity = (maxCollateralAmount / collateralRatioForMint) * (collateralRatioForMint - BASE_RATIO);

        // Divide max equity by a random number between 2 and 100000 to split deposits up more among calls
        uint256 equityDivisor = bound(seed, 2, 100000);
        return bound(seed, 0, maxEquity / equityDivisor);
    }

    function _boundEquityForRedeem(ILeverageToken leverageToken, address actor, uint256 seed)
        internal
        view
        returns (uint256)
    {
        uint256 shares = leverageToken.balanceOf(actor);
        uint256 maxEquity = convertToAssets(leverageToken, shares);

        // Divide max equity by a random number between 1 and 10 to split withdrawals up more among calls
        uint256 equityDivisor = bound(seed, 1, 10);
        return bound(seed, 0, maxEquity / equityDivisor);
    }

    function _saveLeverageTokenState(ILeverageToken leverageToken, ActionType actionType, bytes memory actionData)
        internal
    {
        ILendingAdapter lendingAdapter = leverageManager.getLeverageTokenLendingAdapter(leverageToken);

        uint256 collateralRatio = leverageManager.getLeverageTokenState(leverageToken).collateralRatio;
        uint256 collateral = lendingAdapter.getCollateral();
        uint256 collateralInDebtAsset = lendingAdapter.convertCollateralToDebtAsset(collateral);
        uint256 debt = lendingAdapter.getDebt();
        uint256 debtInCollateralAsset = lendingAdapter.convertDebtToCollateralAsset(debt);
        uint256 totalSupply = leverageToken.totalSupply();
        uint256 equityInCollateralAsset = lendingAdapter.getEquityInCollateralAsset();
        uint256 equityInDebtAsset = lendingAdapter.getEquityInDebtAsset();
        uint256 collateralRatioUsingDebtNormalized = debtInCollateralAsset > 0
            ? Math.mulDiv(collateral, BASE_RATIO, debtInCollateralAsset, Math.Rounding.Floor)
            : type(uint256).max;

        leverageTokenStateBefore = LeverageTokenStateData({
            leverageToken: leverageToken,
            actionType: actionType,
            collateral: collateral,
            collateralInDebtAsset: collateralInDebtAsset,
            debt: debt,
            equityInCollateralAsset: equityInCollateralAsset,
            equityInDebtAsset: equityInDebtAsset,
            collateralRatio: collateralRatio,
            collateralRatioUsingDebtNormalized: collateralRatioUsingDebtNormalized,
            totalSupply: totalSupply,
            actionData: actionData
        });
    }
}
