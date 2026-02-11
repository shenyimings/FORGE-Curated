// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

// Dependency imports
import {IMorpho} from "@morpho-blue/interfaces/IMorpho.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

// Internal imports
import {ILeverageManager} from "../interfaces/ILeverageManager.sol";
import {ILeverageToken} from "../interfaces/ILeverageToken.sol";
import {ISwapAdapter} from "../interfaces/periphery/ISwapAdapter.sol";
import {ILeverageRouter} from "../interfaces/periphery/ILeverageRouter.sol";
import {ActionData, ExternalAction} from "../types/DataTypes.sol";

/**
 * @dev The LeverageRouter contract is an immutable periphery contract that facilitates the use of Morpho flash loans and a swap adapter
 * to deposit and withdraw equity from LeverageTokens.
 *
 * The high-level deposit flow is as follows:
 *   1. The user calls `deposit` with the amount of equity to deposit, the minimum amount of shares (LeverageTokens) to receive, the maximum
 *      cost to the sender for the swap of debt to collateral during the deposit to help repay the flash loan, and the swap context.
 *   2. The LeverageRouter will flash loan the required collateral asset from Morpho.
 *   3. The LeverageRouter will use the flash loaned collateral and the equity from the sender for the deposit into the LeverageToken,
 *      receiving LeverageTokens and debt in return.
 *   4. The LeverageRouter will swap the debt received from the deposit to the collateral asset.
 *   5. The LeverageRouter will use the swapped assets to repay the flash loan along with the collateral asset from the sender
 *      (the maximum swap cost)
 *   6. The LeverageRouter will transfer the LeverageTokens and any remaining collateral asset to the sender.
 *
 * The high-level withdrawal flow is the same as the deposit flow, but in reverse.
 */
contract LeverageRouter is ILeverageRouter {
    /// @notice Deposit related parameters to pass to the Morpho flash loan callback handler for deposits
    struct DepositParams {
        // LeverageToken to deposit into
        ILeverageToken token;
        // Amount of equity to deposit, denominated in the collateral asset
        uint256 equityInCollateralAsset;
        // Minimum amount of shares (LeverageTokens) to receive
        uint256 minShares;
        // Maximum cost to the sender for the swap of debt to collateral during the deposit to repay the flash loan,
        // denominated in the collateral asset
        uint256 maxSwapCostInCollateralAsset;
        // Address of the sender of the deposit, who will also receive the shares
        address sender;
        // Swap context for the debt swap
        ISwapAdapter.SwapContext swapContext;
    }

    /// @notice Withdraw related parameters to pass to the Morpho flash loan callback handler for withdrawals
    struct WithdrawParams {
        // LeverageToken to withdraw from
        ILeverageToken token;
        // Amount of equity to withdraw, denominated in the collateral asset
        uint256 equityInCollateralAsset;
        // Maximum amount of shares (LeverageTokens) to be burned during the withdrawal
        uint256 maxShares;
        // Maximum cost to the sender for the swap of debt to collateral during the withdrawal to repay the flash loan,
        // denominated in the collateral asset. This cost is applied to the equity being withdrawn
        uint256 maxSwapCostInCollateralAsset;
        // Address of the sender of the withdrawal, whose shares will be burned and the equity will be transferred to
        address sender;
        // Swap context for the debt swap
        ISwapAdapter.SwapContext swapContext;
    }

    /// @notice Morpho flash loan callback data to pass to the Morpho flash loan callback handler
    struct MorphoCallbackData {
        ExternalAction action;
        bytes data;
    }

    /// @inheritdoc ILeverageRouter
    ILeverageManager public immutable leverageManager;

    /// @inheritdoc ILeverageRouter
    IMorpho public immutable morpho;

    /// @inheritdoc ILeverageRouter
    ISwapAdapter public immutable swapper;

    /// @notice Creates a new LeverageRouter
    /// @param _leverageManager The LeverageManager contract
    /// @param _morpho The Morpho core protocol contract
    /// @param _swapper The Swapper contract
    constructor(ILeverageManager _leverageManager, IMorpho _morpho, ISwapAdapter _swapper) {
        leverageManager = _leverageManager;
        morpho = _morpho;
        swapper = _swapper;
    }

    /// @inheritdoc ILeverageRouter
    function deposit(
        ILeverageToken token,
        uint256 equityInCollateralAsset,
        uint256 minShares,
        uint256 maxSwapCostInCollateralAsset,
        ISwapAdapter.SwapContext memory swapContext
    ) external {
        uint256 collateralToAdd = leverageManager.previewDeposit(token, equityInCollateralAsset).collateral;

        bytes memory depositData = abi.encode(
            DepositParams({
                token: token,
                equityInCollateralAsset: equityInCollateralAsset,
                minShares: minShares,
                maxSwapCostInCollateralAsset: maxSwapCostInCollateralAsset,
                sender: msg.sender,
                swapContext: swapContext
            })
        );

        // Flash loan the additional required collateral (the sender must supply at least equityInCollateralAsset),
        // and pass the required data to the Morpho flash loan callback handler for the deposit.
        morpho.flashLoan(
            address(leverageManager.getLeverageTokenCollateralAsset(token)),
            collateralToAdd - equityInCollateralAsset,
            abi.encode(MorphoCallbackData({action: ExternalAction.Deposit, data: depositData}))
        );
    }

    /// @inheritdoc ILeverageRouter
    function withdraw(
        ILeverageToken token,
        uint256 equityInCollateralAsset,
        uint256 maxShares,
        uint256 maxSwapCostInCollateralAsset,
        ISwapAdapter.SwapContext memory swapContext
    ) external {
        uint256 debtToBorrow = leverageManager.previewWithdraw(token, equityInCollateralAsset).debt;

        bytes memory withdrawData = abi.encode(
            WithdrawParams({
                token: token,
                equityInCollateralAsset: equityInCollateralAsset,
                maxShares: maxShares,
                maxSwapCostInCollateralAsset: maxSwapCostInCollateralAsset,
                sender: msg.sender,
                swapContext: swapContext
            })
        );

        // Flash loan the debt asset required to repay the flash loan, and pass the required data to the Morpho flash loan callback handler for the withdrawal.
        morpho.flashLoan(
            address(leverageManager.getLeverageTokenDebtAsset(token)),
            debtToBorrow,
            abi.encode(MorphoCallbackData({action: ExternalAction.Withdraw, data: withdrawData}))
        );
    }

    /// @notice Morpho flash loan callback function
    /// @param loanAmount Amount of asset flash loaned
    /// @param data Encoded data passed to `morpho.flashLoan`
    function onMorphoFlashLoan(uint256 loanAmount, bytes calldata data) external {
        if (msg.sender != address(morpho)) revert Unauthorized();

        MorphoCallbackData memory callbackData = abi.decode(data, (MorphoCallbackData));

        if (callbackData.action == ExternalAction.Deposit) {
            DepositParams memory params = abi.decode(callbackData.data, (DepositParams));
            _depositAndRepayMorphoFlashLoan(params, loanAmount);
        } else if (callbackData.action == ExternalAction.Withdraw) {
            WithdrawParams memory params = abi.decode(callbackData.data, (WithdrawParams));
            _withdrawAndRepayMorphoFlashLoan(params, loanAmount);
        }
    }

    /// @notice Executes the deposit of equity into a LeverageToken and the swap of debt assets to the collateral asset
    /// to repay the flash loan from Morpho
    /// @param params Params for the deposit of equity into a LeverageToken
    /// @param collateralLoanAmount Amount of collateral asset flash loaned
    function _depositAndRepayMorphoFlashLoan(DepositParams memory params, uint256 collateralLoanAmount) internal {
        IERC20 collateralAsset = leverageManager.getLeverageTokenCollateralAsset(params.token);
        IERC20 debtAsset = leverageManager.getLeverageTokenDebtAsset(params.token);

        // Transfer the collateral from the sender for the deposit
        // slither-disable-next-line arbitrary-send-erc20
        SafeERC20.safeTransferFrom(
            collateralAsset,
            params.sender,
            address(this),
            params.equityInCollateralAsset + params.maxSwapCostInCollateralAsset
        );

        // Use the flash loaned collateral and the equity from the sender for the deposit into the LeverageToken
        SafeERC20.forceApprove(
            collateralAsset, address(leverageManager), collateralLoanAmount + params.equityInCollateralAsset
        );
        ActionData memory actionData =
            leverageManager.deposit(params.token, params.equityInCollateralAsset, params.minShares);

        // Swap the debt asset received from the deposit to the collateral asset, used to repay the flash loan
        SafeERC20.forceApprove(debtAsset, address(swapper), actionData.debt);

        uint256 collateralFromSwap = swapper.swapExactInput(
            debtAsset,
            actionData.debt,
            0, // Set to zero because additional collateral from the sender is used to help repay the flash loan
            params.swapContext
        );

        // Transfer any surplus collateral assets to the sender
        uint256 assetsAvailableToRepayFlashLoan = collateralFromSwap + params.maxSwapCostInCollateralAsset;
        if (collateralLoanAmount > assetsAvailableToRepayFlashLoan) {
            revert MaxSwapCostExceeded(collateralLoanAmount - collateralFromSwap, params.maxSwapCostInCollateralAsset);
        } else {
            // Return any surplus collateral assets to the sender
            uint256 collateralAssetSurplus = assetsAvailableToRepayFlashLoan - collateralLoanAmount;
            if (collateralAssetSurplus > 0) {
                SafeERC20.safeTransfer(collateralAsset, params.sender, collateralAssetSurplus);
            }
        }

        // Transfer shares received from the deposit to the deposit sender
        SafeERC20.safeTransfer(params.token, params.sender, actionData.shares);

        // Approve morpho to transfer assets to repay the flash loan
        SafeERC20.forceApprove(collateralAsset, address(morpho), collateralLoanAmount);
    }

    /// @notice Executes the withdrawal of equity from a LeverageToken and the swap of collateral assets to the debt asset
    /// to repay the flash loan from Morpho
    /// @param params Params for the withdrawal of equity from a LeverageToken
    /// @param debtLoanAmount Amount of debt asset flash loaned
    function _withdrawAndRepayMorphoFlashLoan(WithdrawParams memory params, uint256 debtLoanAmount) internal {
        IERC20 collateralAsset = leverageManager.getLeverageTokenCollateralAsset(params.token);
        IERC20 debtAsset = leverageManager.getLeverageTokenDebtAsset(params.token);

        // Transfer the shares from the sender
        // slither-disable-next-line arbitrary-send-erc20
        SafeERC20.safeTransferFrom(params.token, params.sender, address(this), params.maxShares);

        // Withdraw the equity from the leverage token
        SafeERC20.forceApprove(debtAsset, address(leverageManager), debtLoanAmount);
        uint256 collateralWithdrawn =
            leverageManager.withdraw(params.token, params.equityInCollateralAsset, params.maxShares).collateral;

        // Swap the collateral asset received from the withdrawal to the debt asset, used to repay the flash loan
        SafeERC20.forceApprove(collateralAsset, address(swapper), collateralWithdrawn);
        uint256 collateralAmountSwapped =
            swapper.swapExactOutput(collateralAsset, debtLoanAmount, collateralWithdrawn, params.swapContext);

        // Check if the amount of collateral swapped to repay the flash loan is greater than the allowed cost
        uint256 remainingCollateral = collateralWithdrawn - collateralAmountSwapped;
        if (remainingCollateral < params.equityInCollateralAsset - params.maxSwapCostInCollateralAsset) {
            revert MaxSwapCostExceeded(
                params.equityInCollateralAsset - remainingCollateral, params.maxSwapCostInCollateralAsset
            );
        } else if (remainingCollateral > 0) {
            SafeERC20.safeTransfer(collateralAsset, params.sender, remainingCollateral);
        }

        // Approve morpho to transfer assets to repay the flash loan
        SafeERC20.forceApprove(debtAsset, address(morpho), debtLoanAmount);
    }
}
