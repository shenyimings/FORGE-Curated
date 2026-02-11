// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

// Dependency imports
import {Id, IMorpho, MarketParams} from "@morpho-blue/interfaces/IMorpho.sol";

// Internal imports
import {IPreLiquidationLendingAdapter} from "./IPreLiquidationLendingAdapter.sol";
import {ILeverageManager} from "./ILeverageManager.sol";

interface IMorphoLendingAdapter is IPreLiquidationLendingAdapter {
    /// @notice Event emitted when the MorphoLendingAdapter is initialized
    /// @param morphoMarketId The ID of the Morpho market that the MorphoLendingAdapter manages a position in
    /// @param marketParams The market parameters of the Morpho market
    /// @param authorizedCreator The authorized creator of the MorphoLendingAdapter, allowed to create LeverageTokens using this adapter
    event MorphoLendingAdapterInitialized(
        Id indexed morphoMarketId, MarketParams marketParams, address indexed authorizedCreator
    );

    /// @notice Event emitted when the MorphoLendingAdapter is flagged as used
    event MorphoLendingAdapterUsed();

    /// @notice Thrown when someone tries to create a LeverageToken with this MorphoLendingAdapter but it is already in use
    error LendingAdapterAlreadyInUse();

    /// @notice The authorized creator of the MorphoLendingAdapter
    /// @return _authorizedCreator The authorized creator of the MorphoLendingAdapter
    /// @dev Only the authorized creator can create a new LeverageToken using this adapter on the LeverageManager
    function authorizedCreator() external view returns (address _authorizedCreator);

    /// @notice Whether the MorphoLendingAdapter is in use
    /// @return _isUsed Whether the MorphoLendingAdapter is in use
    /// @dev If this is true, the MorphoLendingAdapter cannot be used to create a new LeverageToken
    function isUsed() external view returns (bool _isUsed);

    /// @notice The LeverageManager contract
    /// @return _leverageManager The LeverageManager contract
    function leverageManager() external view returns (ILeverageManager _leverageManager);

    /// @notice The ID of the Morpho market that the MorphoLendingAdapter manages a position in
    /// @return _morphoMarketId The ID of the Morpho market that the MorphoLendingAdapter manages a position in
    function morphoMarketId() external view returns (Id _morphoMarketId);

    /// @notice The market parameters of the Morpho lending pool
    /// @return loanToken The loan token of the Morpho lending pool
    /// @return collateralToken The collateral token of the Morpho lending pool
    /// @return oracle The oracle of the Morpho lending pool
    /// @return irm The IRM of the Morpho lending pool
    /// @return lltv The LLTV of the Morpho lending pool
    function marketParams()
        external
        view
        returns (address loanToken, address collateralToken, address oracle, address irm, uint256 lltv);

    /// @notice The Morpho core protocol contract
    /// @return _morpho The Morpho core protocol contract
    function morpho() external view returns (IMorpho _morpho);
}
