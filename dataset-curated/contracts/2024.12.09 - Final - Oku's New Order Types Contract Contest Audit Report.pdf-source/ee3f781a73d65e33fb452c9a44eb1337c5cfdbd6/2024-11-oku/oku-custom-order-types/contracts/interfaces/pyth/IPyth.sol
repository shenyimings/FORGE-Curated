// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IPyth {
    // A price with a degree of uncertainty, represented as a price +- a confidence interval.
    //
    // The confidence interval roughly corresponds to the standard error of a normal distribution.
    // Both the price and confidence are stored in a fixed-point numeric representation,
    // `x * (10^expo)`, where `expo` is the exponent.
    //
    // Please refer to the documentation at https://docs.pyth.network/documentation/pythnet-price-feeds/best-practices for how
    // to how this price safely.
    struct Price {
        // Price
        int64 price;
        // Confidence interval around the price
        uint64 conf;
        // Price exponent
        int32 expo;
        // Unix timestamp describing when the price was published
        uint publishTime;
    }

    // PriceFeed represents a current aggregate price from pyth publisher feeds.
    struct PriceFeed {
        // The price ID.
        bytes32 id;
        // Latest available price
        Price price;
        // Latest available exponentially-weighted moving average price
        Price emaPrice;
    }

    /**
     * @notice Returns the latest price for a given price feed ID.
     * @param priceId The Pyth price feed ID (a unique 32-byte value for each asset).
     * @return Price struct containing price, confidence interval, exponent, and timestamp.
     */
    function getPrice(bytes32 priceId) external view returns (Price memory);

    /**
     * @notice Returns the latest exponentially-weighted moving average (EMA) price for a given feed ID.
     * This function reverts if the price data is not fresh.
     * @param priceId The Pyth price feed ID.
     * @return Price struct with the latest available data.
     */
    function getEmaPrice(bytes32 priceId) external view returns (Price memory);

    /**
     * @notice Returns the latest price for a given price feed ID without checking for freshness.
     * This is a faster, unsafe method if you do not care about staleness.
     * @param priceId The Pyth price feed ID.
     * @return Price struct containing price, confidence interval, exponent, and timestamp.
     */
    function getPriceUnsafe(
        bytes32 priceId
    ) external view returns (Price memory);

    /// @notice Returns the price that is no older than `age` seconds of the current time.
    /// @dev This function is a sanity-checked version of `getPriceUnsafe` which is useful in
    /// applications that require a sufficiently-recent price. Reverts if the price wasn't updated sufficiently
    /// recently.
    /// @return price - please read the documentation of PythStructs.Price to understand how to use this safely.
    function getPriceNoOlderThan(
        bytes32 id,
        uint age
    ) external view returns (Price memory price);

    /**
     * @notice Checks if the given price feed is fresh based on a specified age threshold.
     * @param priceId The Pyth price feed ID.
     * @param age The maximum acceptable age (in seconds) of the price data.
     * @return True if the price is fresh, false otherwise.
     */
    function isPriceFresh(
        bytes32 priceId,
        uint age
    ) external view returns (bool);

    /**
     * @notice Update the price feeds using a signed VAA (Verified Action Approval).
     * This is a write function and requires a signature from Pyth off-chain.
     * @param updateData Encoded price data.
     */
    function updatePriceFeeds(bytes[] calldata updateData) external payable;

    /// @notice Returns the required fee to update an array of price updates.
    /// @param updateData Array of price update data.
    /// @return feeAmount The required fee in Wei.
    function getUpdateFee(
        bytes[] calldata updateData
    ) external view returns (uint feeAmount);

    /**
     * @notice Fetches the timestamp of the last update for a given price feed.
     * @param priceId The Pyth price feed ID.
     * @return The timestamp of the last update.
     */
    function getLastUpdateTime(bytes32 priceId) external view returns (uint256);
}
