// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ILeverageToken} from "./ILeverageToken.sol";
import {ILeverageManager} from "./ILeverageManager.sol";
import {LeverageTokenState} from "src/types/DataTypes.sol";
import {Auction} from "src/types/DataTypes.sol";

interface IDutchAuctionRebalanceAdapter {
    /// @notice Error thrown when the LeverageToken is already set
    error LeverageTokenAlreadySet();

    /// @notice Error thrown when an auction is not valid
    error AuctionNotValid();

    /// @notice Error thrown when an auction is still valid
    error AuctionStillValid();

    /// @notice Error thrown when the LeverageToken is not eligible for rebalance
    error LeverageTokenNotEligibleForRebalance();

    /// @notice Error thrown when attempting to set an auction duration of zero
    error InvalidAuctionDuration();

    /// @notice Error thrown when the minimum price multiplier is higher than the initial price multiplier
    error MinPriceMultiplierTooHigh();

    /// @notice Event emitted when the Dutch auction rebalancer is initialized
    /// @param auctionDuration The duration of auctions
    /// @param initialPriceMultiplier The initial price multiplier for auctions
    /// @param minPriceMultiplier The minimum price multiplier for auctions
    event DutchAuctionRebalanceAdapterInitialized(
        uint256 auctionDuration, uint256 initialPriceMultiplier, uint256 minPriceMultiplier
    );

    /// @notice Event emitted when the LeverageToken is set
    /// @param leverageToken The LeverageToken
    event LeverageTokenSet(ILeverageToken leverageToken);

    /// @notice Event emitted when a new auction is created
    /// @param auction The auction
    event AuctionCreated(Auction auction);

    /// @notice Event emitted when an auction is taken
    /// @param taker The taker of the auction
    /// @param amountIn The amount of tokens provided
    /// @param amountOut The amount of tokens received
    event Take(address indexed taker, uint256 amountIn, uint256 amountOut);

    /// @notice Event emitted when an auction ends
    event AuctionEnded();

    /// @notice Returns the LeverageManager
    /// @return leverageManager The LeverageManager
    function getLeverageManager() external view returns (ILeverageManager leverageManager);

    /// @notice Returns the LeverageToken
    /// @return leverageToken The LeverageToken
    function getLeverageToken() external view returns (ILeverageToken leverageToken);

    /// @notice Returns the current ongoing auction, if one exists
    /// @return auction The current ongoing auction, if one exists
    /// @dev If there is no ongoing auction, this function will return a un-initialized Auction struct
    function getAuction() external view returns (Auction memory auction);

    /// @notice Returns the maximum duration of all auctions in seconds
    /// @return auctionDuration The maximum duration of all auctions in seconds
    function getAuctionDuration() external view returns (uint120 auctionDuration);

    /// @notice Returns the initial price multiplier for all auctions
    /// @return initialPriceMultiplier The initial price multiplier for all auctions
    function getInitialPriceMultiplier() external view returns (uint256 initialPriceMultiplier);

    /// @notice Returns the minimum price multiplier for all auctions
    /// @return minPriceMultiplier The minimum price multiplier for all auctions
    function getMinPriceMultiplier() external view returns (uint256 minPriceMultiplier);

    /// @notice Returns target collateral ratio for the LeverageToken
    /// @return targetCollateralRatio Target collateral ratio
    function getLeverageTokenTargetCollateralRatio() external view returns (uint256 targetCollateralRatio);

    /// @notice Returns the LeverageToken's rebalance status
    /// @return _isEligibleForRebalance True if the LeverageToken is eligible for rebalance, false otherwise
    /// @return isOverCollateralized True if the LeverageToken is over-collateralized, false otherwise
    function getLeverageTokenRebalanceStatus()
        external
        view
        returns (bool _isEligibleForRebalance, bool isOverCollateralized);

    /// @notice Returns the current auction multiplier
    /// @return multiplier The current auction multiplier
    /// @dev This module uses exponential approximation (1-x)^4 to calculate the current auction multiplier
    function getCurrentAuctionMultiplier() external view returns (uint256 multiplier);

    /// @notice Returns true if the LeverageToken is eligible for rebalance
    /// @param token The LeverageToken
    /// @param state The state of the LeverageToken
    /// @param caller The caller of the function
    /// @return isEligible True if the LeverageToken is eligible for rebalance, false otherwise
    function isEligibleForRebalance(ILeverageToken token, LeverageTokenState memory state, address caller)
        external
        view
        returns (bool isEligible);

    /// @notice Returns true if the LeverageToken state after rebalance is valid
    /// @param token The LeverageToken
    /// @param stateBefore The state of the LeverageToken before rebalance
    /// @return isValid True if the LeverageToken state after rebalance is valid, false otherwise
    function isStateAfterRebalanceValid(ILeverageToken token, LeverageTokenState memory stateBefore)
        external
        view
        returns (bool isValid);

    /// @notice Returns whether the current auction is valid
    /// @return isValid Whether the current auction is valid
    function isAuctionValid() external view returns (bool isValid);

    /// @notice Returns the amount of tokens to provide for a given amount of tokens to receive for the current auction
    /// @param amountOut The amount of tokens to receive
    /// @return amountIn The amount of tokens to provide
    /// @dev If there is no valid auction in the current block, this function will still return a value based on the auction
    ///      saved in storage (whether that be the most recent auction or an un-initialized auction)
    function getAmountIn(uint256 amountOut) external view returns (uint256 amountIn);

    /// @notice Creates a new auction for the LeverageToken that needs rebalancing
    function createAuction() external;

    /// @notice Ends the current auction
    function endAuction() external;

    /// @notice Takes part in the current auction at the current price
    /// @param amountOut The amount of tokens to receive
    /// @dev To preview the amount of tokens to provide, the `getAmountIn` function can be used
    function take(uint256 amountOut) external;
}
