// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

// Internal imports
import {ILeverageManager} from "../ILeverageManager.sol";
import {ILeverageToken} from "../ILeverageToken.sol";
import {IAggregatorV2V3Interface} from "./IAggregatorV2V3Interface.sol";

interface IPricingAdapter {
    /// @notice The LeverageManager contract
    /// @return _leverageManager The LeverageManager contract
    function leverageManager() external view returns (ILeverageManager _leverageManager);

    /// @notice Returns the price of one LeverageToken (1e18 wei) denominated in collateral asset of the LeverageToken
    /// @param leverageToken The LeverageToken to get the price for
    /// @return price The price of one LeverageToken denominated in collateral asset
    function getLeverageTokenPriceInCollateral(ILeverageToken leverageToken) external view returns (uint256);

    /// @notice Returns the price of one LeverageToken (1e18 wei) denominated in debt asset of the LeverageToken
    /// @param leverageToken The LeverageToken to get the price for
    /// @return price The price of one LeverageToken denominated in debt asset
    function getLeverageTokenPriceInDebt(ILeverageToken leverageToken) external view returns (uint256);

    /// @notice Returns the price of one LeverageToken (1e18 wei) adjusted to the price on the Chainlink oracle
    /// @param leverageToken The LeverageToken to get the price for
    /// @param chainlinkOracle The Chainlink oracle to use for pricing
    /// @param isBaseDebtAsset True if the debt asset is the base asset of the Chainlink oracle, false if the collateral asset is the base asset
    /// @return price The price of one LeverageToken adjusted to the price on the Chainlink oracle, in the decimals of the oracle
    function getLeverageTokenPriceAdjusted(
        ILeverageToken leverageToken,
        IAggregatorV2V3Interface chainlinkOracle,
        bool isBaseDebtAsset
    ) external view returns (int256);
}
