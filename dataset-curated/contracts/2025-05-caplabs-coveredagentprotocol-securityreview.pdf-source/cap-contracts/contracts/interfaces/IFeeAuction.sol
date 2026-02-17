// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

/// @title Fee Auction Interface
/// @author kexley, @capLabs
/// @notice Interface for the FeeAuction contract
interface IFeeAuction {
    /// @custom:storage-location erc7201:cap.storage.FeeAuction
    /// @dev Storage for the FeeAuction contract
    /// @dev Token used to pay for fees in the auction
    /// @dev Address that receives the payment tokens
    /// @dev Starting price of the current auction in payment tokens
    /// @dev Timestamp when the current auction started
    /// @dev Duration of each auction in seconds
    /// @dev Minimum allowed start price for future auctions
    struct FeeAuctionStorage {
        address paymentToken;
        address paymentRecipient;
        uint256 startPrice;
        uint256 startTimestamp;
        uint256 duration;
        uint256 minStartPrice;
    }

    /// @notice Current price in the payment token, linearly decays toward 0 over time
    /// @return price Current price
    function currentPrice() external view returns (uint256 price);

    /// @notice Buy fees in exchange for the payment token
    /// @dev Starts new auction where start price is double the settled price of this one
    /// @param _assets Assets to buy
    /// @param _receiver Receiver address for the assets
    /// @param _callback Optional callback data
    function buy(address[] calldata _assets, address _receiver, bytes calldata _callback) external;

    /// @notice Set the start price of the current auction
    /// @param _startPrice New start price
    function setStartPrice(uint256 _startPrice) external;

    /// @notice Set the duration of future auctions
    /// @param _duration New duration
    function setDuration(uint256 _duration) external;

    /// @notice Set the minimum start price for future auctions
    /// @param _minStartPrice New minimum start price
    function setMinStartPrice(uint256 _minStartPrice) external;

    /// @dev Buy fees
    event Buy(address buyer, uint256 price, address[] assets, uint256[] balances);

    /// @dev Set start price
    event SetStartPrice(uint256 startPrice);

    /// @dev Set duration
    event SetDuration(uint256 duration);

    /// @dev Set minimum start price
    event SetMinStartPrice(uint256 minStartPrice);

    /// @dev Duration must be set
    error NoDuration();
}
