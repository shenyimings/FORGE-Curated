// SPDX-License-Identifier: MIT
pragma solidity ^0.8;

import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

interface IkpkShares is IERC165 {
    //
    // Errors
    //

    /// @notice Error when attempting to cancel a request that hasn't passed his TTL yet
    error RequestNotPastTtl();

    /// @notice Error when attempting to cancel a request that is not pending
    error RequestNotPending();

    /// @notice Error when the asset is not approved for redemptions
    error UnredeemableAsset();

    /// @notice Error when invalid arguments are provided
    error InvalidArguments();

    /// @notice Error when the caller is not authorized to perform the action
    error NotAuthorized();

    /// @notice Error when the asset is not approved for deposits
    error NotAnApprovedAsset();

    /// @notice Error when the fee rate is too high
    error FeeRateLimitExceeded();

    /// @notice Error when the request type does not match the expected type
    error RequestTypeMismatch();

    /// @notice Error when the request price is lower than the operator price
    error RequestPriceLowerThanOperatorPrice();

    /// @notice Error when the price deviation from the last settled price is too large
    error PriceDeviationTooLarge();

    /// @notice Error when no stored price is available for the asset
    error NoStoredPrice();

    //
    // Structs
    //

    /// @notice Struct representing an approved asset for deposits and redemptions
    /// @param asset The address of the asset
    /// @param symbol The asset's symbol (e.g., "USDC", "ETH")
    /// @param decimals The number of decimal places for the asset
    /// @param isFeeModuleAsset Whether the asset can be used for performance fee module calculations
    /// @param canDeposit Whether the asset is approved for deposits
    /// @param canRedeem Whether the asset is approved for redemptions
    struct ApprovedAsset {
        address asset;
        string symbol;
        uint8 decimals;
        bool isFeeModuleAsset;
        bool canDeposit;
        bool canRedeem;
    }

    /// @notice Struct representing a request for subscription or redemption.
    /// @param requestId The unique identifier for the request
    /// @param requestType The type of request (SUBSCRIPTION or REDEMPTION)
    /// @param requestStatus The current status of the request
    /// @param asset The address of the asset involved in the request
    /// @param assetAmount The amount of assets involved in the request
    /// @param sharesAmount The number of shares involved in the request
    /// @param investor The submitter of the request
    /// @param receiver The receiver of the assets or shares in a successful request
    /// @param timestamp The timestamp when the request was created
    /// @param expiryAt The timestamp when the request expires (cannot be approved after this time)
    struct UserRequest {
        // Request metadata
        RequestType requestType;
        RequestStatus requestStatus;
        // Financial details
        address asset;
        uint256 assetAmount;
        uint256 sharesAmount;
        // User details
        address investor;
        address receiver;
        // Timestamps
        uint64 timestamp;
        uint64 expiryAt;
    }

    //
    // Enums
    //
    /// @notice Enum representing the type of request
    enum RequestType {
        SUBSCRIPTION,
        REDEMPTION
    }

    /// @notice Enum representing the status of a request
    enum RequestStatus {
        PENDING,
        PROCESSED,
        REJECTED,
        CANCELLED
    }

    //
    // Events
    //

    /// @notice Event emitted when a subscription request is made.
    /// @param investor The investor of the shares being subscribed.
    /// @param requestId The unique identifier for the request.
    /// @param receiver The receiver of the shares in a successful request.
    /// @param subscriptionAsset The address of the asset being subscribed.
    /// @param assetsAmount The number of assets being subscribed.
    /// @param sharesAmount The number of shares being issued.
    /// @param timestamp The timestamp when the request was created
    /// @param cancelableFrom The timestamp from which the request can be cancelled (timestamp + subscriptionRequestTtl)
    /// @param expiryAt The timestamp when the request expires (timestamp + maxLifetime)
    event SubscriptionRequest(
        address indexed investor,
        uint256 requestId,
        address indexed receiver,
        address indexed subscriptionAsset,
        uint256 assetsAmount,
        uint256 sharesAmount,
        uint64 timestamp,
        uint64 cancelableFrom,
        uint64 expiryAt
    );

    /// @notice Event emitted when a subscription request is fulfilled.
    /// @param requestId The unique identifier for the request.
    /// @param assets The number of assets subscribed.
    /// @param shares The number of shares issued.
    event SubscriptionApproval(uint256 requestId, uint256 assets, uint256 shares);

    /// @notice Event emitted when a subscription is cancelled
    /// @param requestId The unique identifier for the request.
    /// @param canceller account who cancelled the subscription
    event SubscriptionCancellation(uint256 requestId, address canceller);

    /// @notice Event emitted when a subscription request is denied.
    /// @param requestId The unique identifier for the request.
    /// @param assets The number of assets involved in the request.
    /// @param shares The number of shares requested.
    event SubscriptionDenial(uint256 requestId, uint256 assets, uint256 shares);

    /// @notice Event emitted when a redemption request is made.
    /// @param investor The investor of the shares being redeemed.
    /// @param requestId The unique identifier for the request.
    /// @param receiver The receiver of the assets in a successful request.
    /// @param redemptionAsset The address of the asset being redeemed.
    /// @param assetsAmount The number of assets being redeemed.
    /// @param sharesAmount The number of shares being used.
    /// @param timestamp The timestamp when the request was created
    /// @param cancelableFrom The timestamp from which the request can be cancelled (timestamp + redemptionRequestTtl)
    /// @param expiryAt The timestamp when the request expires (timestamp + maxLifetime)
    event RedemptionRequest(
        address indexed investor,
        uint256 requestId,
        address indexed receiver,
        address indexed redemptionAsset,
        uint256 assetsAmount,
        uint256 sharesAmount,
        uint64 timestamp,
        uint64 cancelableFrom,
        uint64 expiryAt
    );

    /// @notice Event emitted when a redemption request is fulfilled.
    /// @param requestId The unique identifier for the request.
    /// @param assets The number of assets redeemed.
    /// @param shares The number of shares returned.
    /// @param redemptionFee The amount of shares charged as redemption fee
    event RedemptionApproval(uint256 requestId, uint256 assets, uint256 shares, uint256 redemptionFee);

    /// @notice Event emitted when a redemption request is denied.
    /// @param requestId The unique identifier for the request.
    /// @param assets The number of assets involved in the request.
    /// @param shares The number of shares requested.
    event RedemptionDenial(uint256 requestId, uint256 assets, uint256 shares);

    /// @notice Event emitted when a redemption is cancelled
    /// @param requestId The unique identifier for the request.
    /// @param canceller account who cancelled the request
    event RedemptionCancellation(uint256 requestId, address canceller);

    /// @notice Event emitted when subscriptionRequestTtl is updated (only when value changes)
    /// @param ttl The new ttl
    event SubscriptionRequestTtlUpdate(uint64 ttl);

    /// @notice Event emitted when redemptionRequestTtl is updated (only when value changes)
    /// @param ttl The new ttl
    event RedemptionRequestTtlUpdate(uint64 ttl);

    /// @notice Event emitted when a subscription request is skipped due to expiry
    /// @param requestId The unique identifier for the expired request
    /// @param expiryAt The timestamp when the request expired
    event SubscriptionRequestExpired(uint256 requestId, uint64 expiryAt);

    /// @notice Event emitted when a redemption request is skipped due to expiry
    /// @param requestId The unique identifier for the expired request
    /// @param expiryAt The timestamp when the request expired
    event RedemptionRequestExpired(uint256 requestId, uint64 expiryAt);

    /// @notice Event emitted when fees are collected (only when at least one fee > 0)
    /// @param managementFee The amount of assets charged as management fee
    /// @param performanceFee The amount of assets charged as performance fee
    event FeeCollection(uint256 managementFee, uint256 performanceFee);

    /// @notice Event emitted when fee receiver is updated
    /// @param newFeeReceiver The new fee receiver address
    event FeeReceiverUpdate(address indexed newFeeReceiver);

    /// @notice Event emitted when management fee rate is updated (only when value changes)
    /// @param newRate The new management fee rate (in basis points, 2000 = 20%)
    event ManagementFeeRateUpdate(uint256 newRate);

    /// @notice Event emitted when redemption fee is updated (only when value changes)
    /// @param newRate The new redemption fee (in basis points, 2000 = 20%)
    event RedemptionFeeRateUpdate(uint256 newRate);

    /// @notice Event emitted when performance fee is updated (only when value changes)
    /// @param newRate The new performance fee (in basis points, 2000 = 20%)
    event PerformanceFeeRateUpdate(uint256 newRate);

    /// @notice Event emitted when performance fee module is updated
    /// @param newPerformanceFeeModule The new performance fee module address
    event PerformanceFeeModuleUpdate(address indexed newPerformanceFeeModule);

    /// @notice Event emitted when an asset is updated
    /// @param asset The address of the asset
    /// @param isFeeModuleAsset Whether the asset can be used for performance fee module calculations
    /// @param canDeposit Whether the asset is approved for deposits
    /// @param canRedeem Whether the asset is approved for redemptions
    event AssetUpdate(address indexed asset, bool isFeeModuleAsset, bool canDeposit, bool canRedeem);

    /// @notice Event emitted when an asset is added
    /// @param asset The address of the asset
    event AssetAdd(address indexed asset);

    /// @notice Event emitted when an asset is removed
    /// @param asset The address of the asset
    event AssetRemove(address indexed asset);

    //
    // View Functions
    //

    /// @notice Returns the asset configuration for a specific asset
    /// @param asset The address of the asset
    /// @return The asset configuration including symbol, decimals, and oracle
    function getApprovedAsset(address asset) external view returns (ApprovedAsset memory);

    /// @notice Returns the list of approved assets
    /// @return An array of approved asset addresses
    function getApprovedAssets() external view returns (address[] memory);

    /// @notice Checks if an asset is approved for deposits or redemptions
    /// @param asset The address of the asset to check
    /// @return True if the asset is approved for deposits or redemptions
    function isApprovedAsset(address asset) external view returns (bool);

    /// @notice Returns the number of decimals for an asset
    /// @param asset The address of the asset
    /// @return The number of decimals for the asset
    function assetDecimals(address asset) external view returns (uint8);

    /// @notice Returns the amount of shares that the Vault would exchange for the amount of assets provided, in an
    /// ideal scenario.
    ///
    /// The conversion is based on the current price per share. The formula is:
    ///     shares = (assetAmount * 10^shareDecimals * 1e8) / (sharesPrice * 10^assetDecimals)
    ///
    /// @param assetAmount The amount of assets (in asset's native decimals).
    /// @param sharesPrice The current price per share in normalized USD units (8 decimals, i.e., _NORMALIZED_PRECISION_USD).
    /// @param subscriptionAsset The address of the asset being subscribed.
    /// @return The equivalent amount of shares (in share token's native decimals, typically 18).
    function assetsToShares(uint256 assetAmount, uint256 sharesPrice, address subscriptionAsset)
        external
        view
        returns (uint256);

    /// @notice Returns the amount of assets that the Vault would exchange for the amount of shares provided, in an
    /// ideal scenario.
    ///
    /// The conversion is based on the current price per share. The formula is:
    ///     assets = (shares * sharesPrice * 10^assetDecimals) / (1e8 * 10^shareDecimals)
    ///
    /// @param shares The amount of shares (in share token's native decimals, typically 18).
    /// @param sharesPrice The current price per share in normalized USD units (8 decimals, i.e., _NORMALIZED_PRECISION_USD).
    /// @param redemptionAsset The address of the asset to redeem for.
    /// @return The equivalent amount of assets (in asset's native decimals).
    function sharesToAssets(uint256 shares, uint256 sharesPrice, address redemptionAsset)
        external
        view
        returns (uint256);

    //
    // Subscription Functions
    //

    /// @notice Preview a subscription request
    /// @param assets The amount of assets to subscribe (in asset's native decimals)
    /// @param sharesPrice The current price per share in normalized USD units (8 decimals, i.e., _NORMALIZED_PRECISION_USD). Use 0 to use the last settled price.
    /// @param subscriptionAsset The address of the asset being subscribed
    /// @return shares The amount of shares that would be received (in share token's native decimals, typically 18)
    function previewSubscription(uint256 assets, uint256 sharesPrice, address subscriptionAsset)
        external
        view
        returns (uint256 shares);

    /// @notice Request a subscription of assets
    /// @param assetsIn The amount of assets to subscribe
    /// @param minSharesOut The minimum amount of shares to receive (slippage protection)
    /// @param subscriptionAsset The address of the asset being subscribed
    /// @param receiver The address that will receive the shares
    /// @return requestId The ID of the created subscription request
    /// @dev Gas cost: ~278,000 gas
    /// @dev The minimum shares output is used for slippage protection. The actual shares minted will be computed from the current price at approval time.
    function requestSubscription(uint256 assetsIn, uint256 minSharesOut, address subscriptionAsset, address receiver)
        external
        returns (uint256 requestId);

    /// @notice Cancel a subscription request
    /// @param id The ID of the subscription request to cancel
    function cancelSubscription(uint256 id) external;

    /// @notice Process requests (approve/reject)
    /// @param approveRequests Array of request IDs to approve
    /// @param rejectRequests Array of request IDs to reject
    /// @param asset The asset to process requests for
    /// @param sharesPrice The current price per share in normalized USD units (8 decimals, i.e., _NORMALIZED_PRECISION_USD)
    /// @dev Gas cost: ~71,000 gas per approval, ~15,000 gas per rejection
    function processRequests(
        uint256[] calldata approveRequests,
        uint256[] calldata rejectRequests,
        address asset,
        uint256 sharesPrice
    ) external;

    //
    // Redemption Functions
    //

    /// @notice Preview a redemption request
    /// @param shares The amount of shares to redeem (in share token's native decimals, typically 18)
    /// @param sharesPrice The current price per share in normalized USD units (8 decimals, i.e., _NORMALIZED_PRECISION_USD). Use 0 to use the last settled price.
    /// @param redemptionAsset The address of the asset to redeem for
    /// @return assets The amount of assets that would be received (after fees, in asset's native decimals)
    function previewRedemption(uint256 shares, uint256 sharesPrice, address redemptionAsset)
        external
        view
        returns (uint256 assets);

    /// @notice Request to redeem shares for assets
    /// @param sharesIn The amount of shares to redeem
    /// @param minAssetsOut The minimum amount of assets to receive (slippage protection)
    /// @param redemptionAsset The address of the asset to redeem for
    /// @param receiver The address that will receive the assets
    /// @return requestId The ID of the redemption request
    /// @dev Gas cost: ~192,000 gas
    /// @dev The minimum assets output is used for slippage protection. The actual assets received will be computed from the current price at approval time.
    function requestRedemption(uint256 sharesIn, uint256 minAssetsOut, address redemptionAsset, address receiver)
        external
        returns (uint256 requestId);

    /// @notice Cancel a redemption request
    /// @param id The ID of the redemption request to cancel
    function cancelRedemption(uint256 id) external;

    //
    // Admin Functions
    //

    /// @notice Sets the subscription request TTL for all pending subscription requests (only emits event when value changes)
    /// @param ttl The new TTL to apply (max 7 days)
    /// @dev Changing this value affects all pending requests, not just new ones. The TTL is used during validation
    ///      when canceling requests, so updating it changes the cancellation behavior for existing pending requests.
    function setSubscriptionRequestTtl(uint64 ttl) external;

    /// @notice Sets the redemption request TTL for all pending redemption requests (only emits event when value changes)
    /// @param ttl The new TTL to apply (max 7 days)
    /// @dev Changing this value affects all pending requests, not just new ones. The TTL is used during validation
    ///      when canceling requests, so updating it changes the cancellation behavior for existing pending requests.
    function setRedemptionRequestTtl(uint64 ttl) external;

    /// @notice Sets the fee receiver address
    /// @param newFeeReceiver The new fee receiver address
    function setFeeReceiver(address newFeeReceiver) external;

    /// @notice Sets the management fee rate (only emits event when value changes)
    /// @param newRate The new management rate (in basis points, max 2000 = 20%)
    function setManagementFeeRate(uint256 newRate) external;

    /// @notice Sets the redemption fee rate (only emits event when value changes)
    /// @param newRate The new redemption fee (in basis points, max 2000 = 20%)
    function setRedemptionFeeRate(uint256 newRate) external;

    /// @notice Sets the performance fee rate (only emits event when value changes)
    /// @param newRate The new performance fee (in basis points, max 2000 = 20%)
    /// @param usdAsset The USD asset to use for performance fee calculations
    function setPerformanceFeeRate(uint256 newRate, address usdAsset) external;

    /// @notice Sets the performance fee module
    /// @param newPerformanceFeeModule The new performance fee module address
    function setPerformanceFeeModule(address newPerformanceFeeModule) external;

    /// @notice Updates an asset configuration for deposits and redemption
    /// @param asset The asset address to configure
    /// @param isFeeModuleAsset Whether the asset can be used for performance fee module calculations
    /// @param canDeposit Whether the asset is approved for deposits
    /// @param canRedeem Whether the asset is approved for redemptions
    function updateAsset(address asset, bool isFeeModuleAsset, bool canDeposit, bool canRedeem) external;

    /// @notice Returns a request (deposit or redeem) by ID
    /// @param id The request IDs
    /// @return The request details
    function getRequest(uint256 id) external view returns (UserRequest memory);

    /// @notice Returns the current redemption fee rate
    /// @return The redemption fee rate in basis points (1000 = 10%)
    function redemptionFeeRate() external view returns (uint256);

    /// @notice Returns the current management fee rate
    /// @return The management fee rate in basis points (1000 = 10%)
    function managementFeeRate() external view returns (uint256);

    /// @notice Returns the portfolio safe address where assets are transferred
    /// @return The portfolio safe address
    function portfolioSafe() external view returns (address);

    /// @notice Returns the performance fee module address
    /// @return The performance fee module address
    function performanceFeeModule() external view returns (address);

    /// @notice Returns the fee receiver address
    /// @return The fee receiver address
    function feeReceiver() external view returns (address);

    /// @notice Returns the performance fee rate
    /// @return The performance fee rate in basis points (1000 = 10%)
    function performanceFeeRate() external view returns (uint256);

    /// @notice Returns the current request ID counter
    /// @return The current request ID
    function requestId() external view returns (uint256);

    /// @notice Returns the subscription request TTL
    /// @return The subscription request TTL in seconds
    function subscriptionRequestTtl() external view returns (uint64);

    /// @notice Returns the redemption request TTL
    /// @return The redemption request TTL in seconds
    function redemptionRequestTtl() external view returns (uint64);

    /// @notice Returns the subscription assets mapping for a specific asset
    /// @param asset The address of the asset
    /// @return The amount of assets pending in subscription requests for this asset
    function subscriptionAssets(address asset) external view returns (uint256);

    /// @notice Returns the last settled price for a specific asset
    /// @param asset The address of the asset
    /// @return The last settled price per share in normalized USD units (8 decimals), or 0 if no price has been settled yet
    function getLastSettledPrice(address asset) external view returns (uint256);
}
