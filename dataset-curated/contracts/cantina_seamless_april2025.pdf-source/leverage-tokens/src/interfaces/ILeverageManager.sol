// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

// Dependency imports
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// Internal imports
import {IFeeManager} from "./IFeeManager.sol";
import {IRebalanceAdapterBase} from "./IRebalanceAdapterBase.sol";
import {ILeverageToken} from "./ILeverageToken.sol";
import {IBeaconProxyFactory} from "./IBeaconProxyFactory.sol";
import {ILendingAdapter} from "./ILendingAdapter.sol";
import {
    ActionData,
    LeverageTokenState,
    RebalanceAction,
    TokenTransfer,
    LeverageTokenConfig
} from "src/types/DataTypes.sol";

interface ILeverageManager is IFeeManager {
    /// @notice Error thrown when someone tries to set zero address for collateral or debt asset when creating a LeverageToken
    error InvalidLeverageTokenAssets();

    /// @notice Error thrown when collateral ratios are invalid for an action
    error InvalidCollateralRatios();

    /// @notice Error thrown when slippage is too high during deposit/withdraw
    /// @param actual The actual amount of tokens received
    /// @param expected The expected amount of tokens to receive
    error SlippageTooHigh(uint256 actual, uint256 expected);

    /// @notice Error thrown when caller is not authorized to rebalance
    /// @param token The LeverageToken to rebalance
    /// @param caller The caller of the rebalance function
    error NotRebalancer(ILeverageToken token, address caller);

    /// @notice Error thrown when a LeverageToken is not eligible for rebalance
    /// @param token The LeverageToken that is not eligible for rebalance
    error LeverageTokenNotEligibleForRebalance(ILeverageToken token);

    /// @notice Error thrown when a LeverageToken's state after rebalance is invalid
    /// @param token The LeverageToken that has invalid state after rebalance
    error InvalidLeverageTokenStateAfterRebalance(ILeverageToken token);

    /// @notice Event emitted when the LeverageManager is initialized
    /// @param leverageTokenFactory The factory for creating new LeverageTokens
    event LeverageManagerInitialized(IBeaconProxyFactory leverageTokenFactory);

    /// @notice Event emitted when a new LeverageToken is created
    /// @param token The new LeverageToken
    /// @param collateralAsset The collateral asset of the LeverageToken
    /// @param debtAsset The debt asset of the LeverageToken
    /// @param config The config of the LeverageToken
    event LeverageTokenCreated(
        ILeverageToken indexed token, IERC20 collateralAsset, IERC20 debtAsset, LeverageTokenConfig config
    );

    /// @notice Event emitted when a user deposits assets into a LeverageToken
    /// @param token The LeverageToken
    /// @param sender The sender of the deposit
    /// @param actionData The action data of the deposit
    event Deposit(ILeverageToken indexed token, address indexed sender, ActionData actionData);

    /// @notice Event emitted when a user withdraws assets from a LeverageToken
    /// @param token The LeverageToken
    /// @param sender The sender of the withdraw
    /// @param actionData The action data of the withdraw
    event Withdraw(ILeverageToken indexed token, address indexed sender, ActionData actionData);

    /// @notice Returns the factory for creating new LeverageTokens
    /// @return factory Factory for creating new LeverageTokens
    function getLeverageTokenFactory() external view returns (IBeaconProxyFactory factory);

    /// @notice Returns the lending adapter for a LeverageToken
    /// @param token LeverageToken to get lending adapter for
    /// @return adapter Lending adapter for the LeverageToken
    function getLeverageTokenLendingAdapter(ILeverageToken token) external view returns (ILendingAdapter adapter);

    /// @notice Returns the collateral asset for a LeverageToken
    /// @param token LeverageToken to get collateral asset for
    /// @return collateralAsset Collateral asset for the LeverageToken
    function getLeverageTokenCollateralAsset(ILeverageToken token) external view returns (IERC20 collateralAsset);

    /// @notice Returns the debt asset for a LeverageToken
    /// @param token LeverageToken to get debt asset for
    /// @return debtAsset Debt asset for the LeverageToken
    function getLeverageTokenDebtAsset(ILeverageToken token) external view returns (IERC20 debtAsset);

    /// @notice Returns the rebalance adapter for a LeverageToken
    /// @param token LeverageToken to get the rebalance adapter for
    /// @return adapter Rebalance adapter for the LeverageToken
    function getLeverageTokenRebalanceAdapter(ILeverageToken token)
        external
        view
        returns (IRebalanceAdapterBase adapter);

    /// @notice Returns the entire configuration for a LeverageToken
    /// @param token LeverageToken to get config for
    /// @return config LeverageToken configuration
    function getLeverageTokenConfig(ILeverageToken token) external view returns (LeverageTokenConfig memory config);

    /// @notice Returns the initial collateral ratio for a LeverageToken
    /// @param token LeverageToken to get initial collateral ratio for
    /// @return initialCollateralRatio Initial collateral ratio for the LeverageToken
    /// @dev Initial collateral ratio is followed when the LeverageToken has no shares and on deposits when debt is 0.
    function getLeverageTokenInitialCollateralRatio(ILeverageToken token)
        external
        view
        returns (uint256 initialCollateralRatio);

    /// @notice Returns all data required to describe current LeverageToken state - collateral, debt, equity and collateral ratio
    /// @param token LeverageToken to query state for
    /// @return state LeverageToken state
    function getLeverageTokenState(ILeverageToken token) external view returns (LeverageTokenState memory state);

    /// @notice Creates a new LeverageToken with the given config
    /// @param config Configuration of the LeverageToken
    /// @param name Name of the LeverageToken
    /// @param symbol Symbol of the LeverageToken
    /// @return token Address of the new LeverageToken
    function createNewLeverageToken(LeverageTokenConfig memory config, string memory name, string memory symbol)
        external
        returns (ILeverageToken token);

    /// @notice Previews deposit function call and returns all required data
    /// @param token LeverageToken to preview deposit for
    /// @param equityInCollateralAsset Equity to deposit denominated in collateral asset
    /// @return previewData Preview data for deposit
    ///         - collateralToAdd Amount of collateral that sender needs to approve the LeverageManager to spend,
    ///           this includes any fees
    ///         - debtToBorrow Amount of debt that will be borrowed and sent to sender
    ///         - equity Amount of equity that will be deposited before fees, denominated in collateral asset
    ///         - shares Amount of shares that will be minted to the sender
    ///         - tokenFee Amount of collateral asset that will be charged for the deposit to the leverage token
    ///         - treasuryFee Amount of collateral asset that will be charged for the deposit to the treasury
    /// @dev Sender should approve leverage manager to spend collateralToAdd amount of collateral asset
    function previewDeposit(ILeverageToken token, uint256 equityInCollateralAsset)
        external
        view
        returns (ActionData memory previewData);

    /// @notice Previews withdraw function call and returns all required data
    /// @param token LeverageToken to preview withdraw for
    /// @param equityInCollateralAsset Equity to withdraw denominated in collateral asset
    /// @return previewData Preview data for withdraw
    ///         - collateralToRemove Amount of collateral that will be removed from the LeverageToken and sent to the sender
    ///         - debtToRepay Amount of debt that will be taken from sender and repaid to the LeverageToken
    ///         - equity Amount of equity that will be withdrawn before fees, denominated in collateral asset
    ///         - shares Amount of shares that will be burned from sender
    ///         - tokenFee Amount of collateral asset that will be charged for the withdraw to the leverage token
    ///         - treasuryFee Amount of collateral asset that will be charged for the withdraw to the treasury
    /// @dev Sender should approve leverage manager to spend debtToRepay amount of debt asset
    function previewWithdraw(ILeverageToken token, uint256 equityInCollateralAsset)
        external
        view
        returns (ActionData memory previewData);

    /// @notice Deposits equity into a LeverageToken and mints shares to the sender
    /// @param token The LeverageToken to deposit into
    /// @param equityInCollateralAsset The amount of equity to deposit denominated in the collateral asset of the LeverageToken
    /// @param minShares The minimum amount of shares to mint
    /// @return actionData Data about the deposit
    ///         - collateral Amount of collateral that was added, including any fees
    ///         - debt Amount of debt that was added
    ///         - equity Amount of equity that was deposited before fees, denominated in collateral asset
    ///         - shares Amount of shares minted to the sender
    ///         - tokenFee Amount of collateral that was charged for the deposit to the leverage token
    ///         - treasuryFee Amount of collateral that was charged for the deposit to the treasury
    function deposit(ILeverageToken token, uint256 equityInCollateralAsset, uint256 minShares)
        external
        returns (ActionData memory actionData);

    /// @notice Withdraws equity from a LeverageToken and burns shares from sender
    /// @param token The LeverageToken to withdraw from
    /// @param equityInCollateralAsset The amount of equity to withdraw denominated in the collateral asset of the LeverageToken
    /// @param maxShares The maximum amount of shares to burn
    /// @return actionData Data about the withdraw
    ///         - collateral Amount of collateral that was removed from LeverageToken and sent to sender
    ///         - debt Amount of debt that was repaid to LeverageToken, taken from sender
    ///         - equity Amount of equity that was withdrawn before fees, denominated in collateral asset
    ///         - shares Amount of the sender's shares that were burned for the withdrawal
    ///         - tokenFee Amount of collateral that was charged for the withdraw to the leverage token
    ///         - treasuryFee Amount of collateral that was charged for the withdraw to the treasury
    function withdraw(ILeverageToken token, uint256 equityInCollateralAsset, uint256 maxShares)
        external
        returns (ActionData memory actionData);

    /// @notice Rebalances LeverageTokens based on provided actions
    /// @param actions Array of rebalance actions to execute (add collateral, remove collateral, borrow or repay)
    /// @param tokensIn Array of tokens to transfer in. Transfer from caller to the LeverageManager contract
    /// @param tokensOut Array of tokens to transfer out. Transfer from the LeverageManager contract to caller
    /// @dev Anyone can call this function. At the end function will just check if all effected LeverageTokens are in the
    ///      better state than before rebalance. Caller needs to calculate and to provide tokens for rebalancing and he needs
    ///      to specify tokens that he wants to receive
    function rebalance(
        RebalanceAction[] calldata actions,
        TokenTransfer[] calldata tokensIn,
        TokenTransfer[] calldata tokensOut
    ) external;
}
