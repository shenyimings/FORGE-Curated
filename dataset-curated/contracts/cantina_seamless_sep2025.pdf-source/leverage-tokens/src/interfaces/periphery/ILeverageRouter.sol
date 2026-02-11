// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

// Dependency imports
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IMorpho} from "@morpho-blue/interfaces/IMorpho.sol";

// Internal imports
import {ILeverageManager} from "../ILeverageManager.sol";
import {ILeverageToken} from "../ILeverageToken.sol";
import {IVeloraAdapter} from "./IVeloraAdapter.sol";
import {ActionData} from "src/types/DataTypes.sol";

interface ILeverageRouter {
    enum LeverageRouterAction {
        Deposit,
        Redeem,
        RedeemWithVelora
    }

    /// @notice Struct containing the target, value, and data for a single external call.
    struct Call {
        address target; // Call target
        uint256 value; // ETH value to send
        bytes data; // Calldata you ABI-encode off-chain
    }

    /// @notice Deposit related parameters to pass to the Morpho flash loan callback handler for deposits
    struct DepositParams {
        // Address of the sender of the deposit
        address sender;
        // LeverageToken to deposit into
        ILeverageToken leverageToken;
        // Amount of collateral from the sender to deposit
        uint256 collateralFromSender;
        // Minimum amount of shares (LeverageTokens) to receive
        uint256 minShares;
        // External calls to execute for the swap of flash loaned debt to collateral
        Call[] swapCalls;
    }

    /// @notice Morpho flash loan callback data to pass to the Morpho flash loan callback handler
    struct MorphoCallbackData {
        LeverageRouterAction action;
        bytes data;
    }

    /// @notice Redeem related parameters to pass to the Morpho flash loan callback handler for redeems
    struct RedeemParams {
        // Address of the sender of the redeem
        address sender;
        // LeverageToken to redeem from
        ILeverageToken leverageToken;
        // Amount of shares to redeem
        uint256 shares;
        // Minimum amount of collateral for the sender to receive
        uint256 minCollateralForSender;
        // External calls to execute for the swap of flash loaned debt to collateral
        Call[] swapCalls;
    }

    /// @notice Redeem related parameters to pass to the Morpho flash loan callback handler for redeems using Velora
    struct RedeemWithVeloraParams {
        // Address of the sender of the redeem, whose shares will be burned and the collateral asset will be transferred to
        address sender;
        // LeverageToken to redeem from
        ILeverageToken leverageToken;
        // Amount of shares to redeem
        uint256 shares;
        // Minimum amount of collateral for the sender to receive
        uint256 minCollateralForSender;
        // Velora adapter to use for the swap
        IVeloraAdapter veloraAdapter;
        // Velora Augustus contract to use for the swap
        address augustus;
        // Offsets for the Velora swap
        IVeloraAdapter.Offsets offsets;
        // Calldata for the Velora swap
        bytes swapData;
    }

    /// @notice Error thrown when the remaining collateral is less than the minimum collateral for the sender to receive
    /// @param remainingCollateral The remaining collateral after the swap
    /// @param minCollateralForSender The minimum collateral for the sender to receive
    error CollateralSlippageTooHigh(uint256 remainingCollateral, uint256 minCollateralForSender);

    /// @notice Error thrown when the collateral from the swap + the collateral from the sender is less than the collateral required for the deposit
    /// @param available The collateral from the swap + the collateral from the sender, available for the deposit
    /// @param required The collateral required for the deposit
    error InsufficientCollateralForDeposit(uint256 available, uint256 required);

    /// @notice Error thrown when the cost of a swap exceeds the maximum allowed cost
    /// @param actualCost The actual cost of the swap
    /// @param maxCost The maximum allowed cost of the swap
    error MaxSwapCostExceeded(uint256 actualCost, uint256 maxCost);

    /// @notice Error thrown when the caller is not authorized to execute a function
    error Unauthorized();

    /// @notice Converts an amount of equity to an amount of collateral for a LeverageToken, based on the current
    /// collateral ratio of the LeverageToken
    /// @param token LeverageToken to convert equity to collateral for
    /// @param equityInCollateralAsset Amount of equity to convert to collateral, denominated in the collateral asset of the LeverageToken
    /// @return collateral Amount of collateral that correspond to the equity amount
    function convertEquityToCollateral(ILeverageToken token, uint256 equityInCollateralAsset)
        external
        view
        returns (uint256 collateral);

    /// @notice The LeverageManager contract
    /// @return _leverageManager The LeverageManager contract
    function leverageManager() external view returns (ILeverageManager _leverageManager);

    /// @notice The Morpho core protocol contract
    /// @return _morpho The Morpho core protocol contract
    function morpho() external view returns (IMorpho _morpho);

    /// @notice Previews the deposit function call for an amount of equity and returns all required data
    /// @param token LeverageToken to preview deposit for
    /// @param collateralFromSender The amount of collateral from the sender to deposit
    /// @return previewData Preview data for deposit
    ///         - collateral Total amount of collateral that will be added to the LeverageToken (including collateral from swapping flash loaned debt)
    ///         - debt Amount of debt that will be borrowed
    ///         - shares Amount of shares that will be minted
    ///         - tokenFee Amount of shares that will be charged for the deposit that are given to the LeverageToken
    ///         - treasuryFee Amount of shares that will be charged for the deposit that are given to the treasury
    function previewDeposit(ILeverageToken token, uint256 collateralFromSender)
        external
        view
        returns (ActionData memory);

    /// @notice Deposits collateral into a LeverageToken and mints shares to the sender. Any surplus debt received from
    /// the deposit of (collateralFromSender + debt swapped to collateral) is given to the sender.
    /// @param leverageToken LeverageToken to deposit into
    /// @param collateralFromSender Collateral asset amount from the sender to deposit
    /// @param flashLoanAmount Amount of debt to flash loan, which is swapped to collateral and used to deposit into the LeverageToken
    /// @param minShares Minimum number of shares expected to be received by the sender
    /// @param swapCalls External calls to execute for the swap of flash loaned debt to collateral for the LeverageToken deposit
    /// @dev Before each external call, the target contract is approved to spend flashLoanAmount of the debt asset
    function deposit(
        ILeverageToken leverageToken,
        uint256 collateralFromSender,
        uint256 flashLoanAmount,
        uint256 minShares,
        Call[] calldata swapCalls
    ) external;

    /// @notice Redeems an amount of shares of a LeverageToken and transfers collateral asset to the sender, using arbitrary
    /// calldata for the swap of collateral from the redemption to debt to repay the flash loan. Any surplus debt assets
    /// after repaying the flash loan are given to the sender along with the remaining collateral asset.
    /// @param token LeverageToken to redeem from
    /// @param shares Amount of shares to redeem
    /// @param minCollateralForSender Minimum amount of collateral for the sender to receive
    /// @param swapCalls External calls to execute for the swap of collateral from the redemption to debt to repay the flash loan
    function redeem(ILeverageToken token, uint256 shares, uint256 minCollateralForSender, Call[] calldata swapCalls)
        external;

    /// @notice Redeems an amount of shares of a LeverageToken and transfers collateral asset to the sender, using Velora
    /// for the required swap of collateral from the redemption to debt to repay the flash loan
    /// @param token LeverageToken to redeem from
    /// @param shares Amount of shares to redeem
    /// @param minCollateralForSender Minimum amount of collateral for the sender to receive
    /// @param veloraAdapter Velora adapter to use for the swap
    /// @param augustus Velora Augustus address to use for the swap
    /// @param offsets Offsets to use for updating the Velora Augustus calldata
    /// @param swapData Velora swap calldata to use for the swap
    /// @dev The calldata should be for using Velora for an exact output swap of the collateral asset to the debt asset
    /// for the debt amount flash loaned, which is equal to the amount of debt removed from the LeverageToken for the
    /// redemption of shares. The exact output amount in the calldata is updated on chain to match the up to date debt
    /// amount for the redemption of shares, which typically occurs due to borrow interest accrual and price changes
    /// between off chain and on chain execution
    function redeemWithVelora(
        ILeverageToken token,
        uint256 shares,
        uint256 minCollateralForSender,
        IVeloraAdapter veloraAdapter,
        address augustus,
        IVeloraAdapter.Offsets calldata offsets,
        bytes calldata swapData
    ) external;
}
