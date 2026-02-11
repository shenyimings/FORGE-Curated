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
    /// @param _maxPrice Maximum price to pay
    /// @param _assets Assets to buy
    /// @param _minAmounts Minimum amounts to buy
    /// @param _receiver Receiver address for the assets
    /// @param _deadline Deadline for the auction
    function buy(
        uint256 _maxPrice,
        address[] calldata _assets,
        uint256[] calldata _minAmounts,
        address _receiver,
        uint256 _deadline
    ) external;

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

    /// @dev Minimum start price must be set
    error NoMinStartPrice();
    /// @dev Start price must be greater than minimum start price
    error InvalidStartPrice();

    /// @dev Price must be less than maximum price
    error InvalidPrice();

    /// @dev Assets must be non-zero length and have matching lengths
    error InvalidAssets();

    /// @dev Receiver must be non-zero address
    error InvalidReceiver();

    /// @dev Deadline must be in the future
    error InvalidDeadline();

    /// @dev Insufficient balance for asset
    error InsufficientBalance(address asset, uint256 balance, uint256 minAmount);
}
