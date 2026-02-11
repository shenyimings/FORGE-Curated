// SPDX-License-Identifier: MIT
pragma solidity ^0.8;

import {
    IERC20,
    ERC20Upgradeable,
    IERC20Metadata
} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {IPerfFeeModule} from "./FeeModules/IPerfFeeModule.sol";
import {IkpkShares} from "./IkpkShares.sol";
import {RecoverFunds} from "./utils/RecoverFunds.sol";

/// @title KpkShares - Onchain Investment Vehicles Implementation
/// @author kpk
/// @notice Onchain Investment Vehicles shares with subscription/redemption requests and fee management
contract KpkShares is
    Initializable,
    UUPSUpgradeable,
    AccessControlUpgradeable,
    ERC20Upgradeable,
    IkpkShares,
    RecoverFunds
{
    //
    // Libraries
    //
    using Math for uint256;
    using SafeERC20 for IERC20;

    //
    // Constants
    //
    /// @notice Precision constant for WAD (18 decimals)
    uint256 private constant _PRECISION_WAD = 1e18;

    /// @notice Normalized precision for USD calculations (8 decimals)
    uint256 private constant _NORMALIZED_PRECISION_USD = 1e8;

    uint256 private constant _PRECISION_BPS = 10_000;

    /// @notice Maximum time-to-live for requests (7 days)
    uint64 public constant MAX_TTL = 7 days;

    /// @notice Maximum fee rate allowed (2000 = 20%)
    uint256 public constant MAX_FEE_RATE = 2000;

    /// @notice Number of seconds in a year (365 days)
    uint256 public constant SECONDS_PER_YEAR = 365 days;

    /// @notice Minimum time elapsed required for fee calculations (6 hours)
    uint256 public constant MIN_TIME_ELAPSED = 6 hours;

    /// @notice Maximum price deviation allowed (3000 = 30%)
    uint256 public constant MAX_PRICE_DEVIATION_BPS = 3000;

    /// @notice Role identifier for operators
    bytes32 public constant OPERATOR = keccak256("OPERATOR");

    //
    // State Variables
    //

    /// @notice List of added assets
    address[] private _approvedAssets;

    /// @notice Asset configurations mapped by asset address
    mapping(address => ApprovedAsset) private _approvedAssetsMap;

    /// @notice Unique identifier for requests
    uint256 public requestId;

    /// @notice Portfolio safe address where assets are transferred for fund operations
    address public portfolioSafe;

    /// @notice Performance fee module address
    address public performanceFeeModule;

    /// @notice Total assets pending in subscription requests
    mapping(address => uint256) public subscriptionAssets;

    /// @notice Counter of pending requests (subscriptions + redemptions) per asset
    mapping(address => uint256) private _pendingRequestsCount;

    /// @notice Time-to-live for subscription requests before they can be cancelled
    uint64 public subscriptionRequestTtl;

    /// @notice Time-to-live for redemption requests before they can be cancelled
    uint64 public redemptionRequestTtl;

    /// @notice Address that receives redemption fees
    address public feeReceiver;

    /// @notice Management fee rate (in basis points, 2000 = 20%)
    uint256 public managementFeeRate;

    /// @notice Redemption fee rate (in basis points, 2000 = 20%)
    uint256 public redemptionFeeRate;

    /// @notice Performance fee rate (in basis points, 2000 = 20%)
    uint256 public performanceFeeRate;

    /// @notice Management fee last update timestamp
    uint256 private _managementFeeLastUpdate;

    /// @notice Performance fee last update timestamp
    uint256 private _performanceFeeLastUpdate;

    /// @notice Last settled price per asset (in normalized USD units, 8 decimals)
    mapping(address => uint256) private _lastSettledPrice;

    //
    // Storage Mappings
    //

    /// @notice Requests indexed by request ID
    mapping(uint256 requestId => UserRequest request) private _requests;

    //
    // Constructor
    //

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    //
    // Initialization
    //

    /// @notice Parameters for fund initialization
    /// @param asset The address of the underlying asset (MUST be configured with isFeeModuleAsset=true to initialize performance fee calculations)
    /// @param admin The address of the initial default admin
    /// @param name The name of the shares
    /// @param symbol The symbol of the shares
    /// @param safe The address of the main safe
    /// @param subscriptionRequestTtl The time-to-live for subscription requests
    /// @param redemptionRequestTtl The time-to-live for redemption requests
    /// @param feeReceiver The address that receives redemption fees
    /// @param managementFeeRate The management fee rate (in basis points, 2000 = 20%)
    /// @param redemptionFeeRate The redemption fee rate (in basis points, 2000 = 20%)
    /// @param performanceFeeModule The performance fee module address
    /// @param performanceFeeRate The performance fee rate (in basis points, 2000 = 20%)
    struct ConstructorParams {
        address asset;
        address admin;
        string name;
        string symbol;
        address safe;
        uint64 subscriptionRequestTtl;
        uint64 redemptionRequestTtl;
        address feeReceiver;
        uint256 managementFeeRate;
        uint256 redemptionFeeRate;
        address performanceFeeModule;
        uint256 performanceFeeRate;
    }

    /// @notice Initialize the contract with fund parameters
    /// @param params Initialization parameters
    function initialize(ConstructorParams memory params) external initializer {
        __UUPSUpgradeable_init();
        __AccessControl_init();
        __ERC20_init(params.name, params.symbol);
        __Context_init();
        __ERC165_init();
        _validateInitializationParams(params);
        _initializeState(params);
        _setupRoles(params.admin);
    }

    //
    // Authorization Functions
    //

    /// @notice Modifier to check if the caller is an admin
    modifier isAdmin() {
        if (!hasRole(DEFAULT_ADMIN_ROLE, msg.sender)) revert NotAuthorized();
        _;
    }

    /// @notice Modifier to check if the caller is an operator
    modifier isOperator() {
        if (!hasRole(OPERATOR, msg.sender)) revert NotAuthorized();
        _;
    }

    //
    // Subscription Operations
    //

    /// @inheritdoc IkpkShares
    function previewSubscription(uint256 assets, uint256 sharesPrice, address subscriptionAsset)
        external
        view
        returns (uint256 shares)
    {
        // If sharesPrice is 0, use the last settled price
        if (sharesPrice == 0) {
            uint256 lastPrice = _lastSettledPrice[subscriptionAsset];
            if (lastPrice == 0) {
                revert NoStoredPrice();
            }
            sharesPrice = lastPrice;
        }
        // sharesToShares() checks canDeposit of subscriptionAsset
        return assetsToShares(assets, sharesPrice, subscriptionAsset);
    }

    /// @inheritdoc IkpkShares
    function requestSubscription(uint256 assetsIn, uint256 minSharesOut, address subscriptionAsset, address receiver)
        external
        returns (uint256)
    {
        _requireValidRequestParams(assetsIn, minSharesOut, receiver);

        // Check if the asset is approved for subscriptions
        ApprovedAsset memory assetConfig = _approvedAssetsMap[subscriptionAsset];
        if (!assetConfig.canDeposit) revert NotAnApprovedAsset();

        // Transfer assets from investor first (before updating state)
        IERC20(subscriptionAsset).safeTransferFrom(msg.sender, address(this), assetsIn);

        // Update state and create request
        subscriptionAssets[subscriptionAsset] += assetsIn;
        _pendingRequestsCount[subscriptionAsset]++;
        uint256 currentRequestId = ++requestId;

        // Calculate expiry and cancelableFrom timestamps
        uint64 currentTimestamp = uint64(block.timestamp);
        uint64 expiryAt = currentTimestamp + MAX_TTL;
        uint64 cancelableFrom = currentTimestamp + subscriptionRequestTtl;

        // Create the actual request with the correct requestId
        _requests[currentRequestId] = UserRequest({
            requestType: RequestType.SUBSCRIPTION,
            requestStatus: RequestStatus.PENDING,
            asset: subscriptionAsset,
            assetAmount: assetsIn,
            sharesAmount: minSharesOut,
            investor: msg.sender,
            receiver: receiver,
            timestamp: currentTimestamp,
            expiryAt: expiryAt
        });

        emit SubscriptionRequest(
            msg.sender,
            currentRequestId,
            receiver,
            subscriptionAsset,
            assetsIn,
            minSharesOut,
            currentTimestamp,
            cancelableFrom,
            expiryAt
        );

        return currentRequestId;
    }

    /// @inheritdoc IkpkShares
    function cancelSubscription(uint256 id) external {
        UserRequest memory request = _requests[id];

        if (!_checkValidRequest(request.investor, request.requestStatus)) {
            revert RequestNotPending();
        }
        if (request.requestType != RequestType.SUBSCRIPTION) {
            revert RequestTypeMismatch();
        }

        // Check TTL - can only cancel after TTL has expired
        if (block.timestamp < request.timestamp + subscriptionRequestTtl) {
            revert RequestNotPastTtl();
        }

        _requireCancellationAuthorization(request.investor, request.receiver);

        uint256 totalAssets = request.assetAmount;
        subscriptionAssets[request.asset] -= totalAssets;
        _pendingRequestsCount[request.asset]--;

        // Update status to CANCELLED instead of deleting
        _requests[id].requestStatus = RequestStatus.CANCELLED;

        IERC20(request.asset).safeTransfer(request.investor, totalAssets);

        emit SubscriptionCancellation(id, msg.sender);
    }

    //
    // Redemption Operations
    //

    /// @inheritdoc IkpkShares
    function previewRedemption(uint256 shares, uint256 sharesPrice, address redemptionAsset)
        external
        view
        returns (uint256 assets)
    {
        // If sharesPrice is 0, use the last settled price
        if (sharesPrice == 0) {
            uint256 lastPrice = _lastSettledPrice[redemptionAsset];
            if (lastPrice == 0) {
                revert NoStoredPrice();
            }
            sharesPrice = lastPrice;
        }

        // Calculate redemption fee if applicable
        uint256 redemptionFee = 0;
        if (redemptionFeeRate > 0) {
            redemptionFee = (shares * redemptionFeeRate) / _PRECISION_BPS;
        }

        // Calculate net shares after fee deduction
        uint256 netShares = shares - redemptionFee;

        // Calculate net assets that will be received (after fees)
        // sharesToAssets() checks canRedeem of redemptionAsset
        return sharesToAssets(netShares, sharesPrice, redemptionAsset);
    }

    /// @inheritdoc IkpkShares
    function requestRedemption(uint256 sharesIn, uint256 minAssetsOut, address redemptionAsset, address receiver)
        external
        returns (uint256)
    {
        _requireValidRequestParams(sharesIn, minAssetsOut, receiver);

        // Check if the asset is approved for redemptions
        if (!_approvedAssetsMap[redemptionAsset].canRedeem) revert NotAnApprovedAsset();

        // Transfer shares to contract as escrow
        _transfer(msg.sender, address(this), sharesIn);

        uint256 currentRequestId = ++requestId;

        // Calculate expiry and cancelableFrom timestamps
        uint64 currentTimestamp = uint64(block.timestamp);
        uint64 expiryAt = currentTimestamp + MAX_TTL;
        uint64 cancelableFrom = currentTimestamp + redemptionRequestTtl;

        // Create the actual request with the correct requestId
        UserRequest memory request = UserRequest({
            requestType: RequestType.REDEMPTION,
            requestStatus: RequestStatus.PENDING,
            asset: redemptionAsset,
            assetAmount: minAssetsOut,
            sharesAmount: sharesIn,
            investor: msg.sender,
            receiver: receiver,
            timestamp: currentTimestamp,
            expiryAt: expiryAt
        });

        _requests[currentRequestId] = request;
        _pendingRequestsCount[redemptionAsset]++;

        emit RedemptionRequest(
            msg.sender,
            currentRequestId,
            receiver,
            redemptionAsset,
            minAssetsOut,
            sharesIn,
            currentTimestamp,
            cancelableFrom,
            expiryAt
        );

        return currentRequestId;
    }

    /// @inheritdoc IkpkShares
    function cancelRedemption(uint256 id) external {
        UserRequest memory request = _requests[id];

        if (!_checkValidRequest(request.investor, request.requestStatus)) {
            revert RequestNotPending();
        }
        if (request.requestType != RequestType.REDEMPTION) {
            revert RequestTypeMismatch();
        }
        // Check TTL - can only cancel after TTL has expired
        if (block.timestamp < request.timestamp + redemptionRequestTtl) {
            revert RequestNotPastTtl();
        }

        _requireCancellationAuthorization(request.investor, request.receiver);

        // Update status to CANCELLED instead of deleting
        _requests[id].requestStatus = RequestStatus.CANCELLED;
        _pendingRequestsCount[request.asset]--;

        // Return shares from escrow to investor
        _transfer(address(this), request.investor, request.sharesAmount);

        emit RedemptionCancellation(id, msg.sender);
    }

    //
    // Operator Functions
    //

    /// @inheritdoc IkpkShares
    function processRequests(
        uint256[] calldata approveRequests,
        uint256[] calldata rejectRequests,
        address asset,
        uint256 sharesPriceInAsset
    ) external isOperator {
        // Validate price deviation from last settled price
        _validatePriceDeviation(asset, sharesPriceInAsset);

        _chargeFees(asset, sharesPriceInAsset);
        _processApproved(approveRequests, asset, sharesPriceInAsset);
        _processRejected(rejectRequests, asset);

        // Update last settled price after successful processing
        _lastSettledPrice[asset] = sharesPriceInAsset;
    }

    /// @inheritdoc IkpkShares
    function updateAsset(address asset, bool isFeeModuleAsset, bool canDeposit, bool canRedeem) external isOperator {
        _updateAsset(asset, isFeeModuleAsset, canDeposit, canRedeem);
    }

    //
    // Admin Functions
    //

    /// @inheritdoc IkpkShares
    function setSubscriptionRequestTtl(uint64 ttl) external isAdmin {
        if (ttl == 0) revert InvalidArguments();

        _setSubscriptionRequestTtl(ttl);
    }

    /// @inheritdoc IkpkShares
    function setRedemptionRequestTtl(uint64 ttl) external isAdmin {
        if (ttl == 0) revert InvalidArguments();

        _setRedemptionRequestTtl(ttl);
    }

    /// @inheritdoc IkpkShares
    function setFeeReceiver(address newFeeReceiver) external isAdmin {
        if (newFeeReceiver == address(0)) revert InvalidArguments();
        _setFeeReceiver(newFeeReceiver);
    }

    /// @inheritdoc IkpkShares
    function setManagementFeeRate(uint256 newRate) external isAdmin {
        // Allow 0 rate (no fees)
        if (newRate > MAX_FEE_RATE) revert FeeRateLimitExceeded();
        if (managementFeeRate != newRate) {
            _setManagementFeeRate(newRate);
        }
    }

    /// @inheritdoc IkpkShares
    function setRedemptionFeeRate(uint256 newRate) external isAdmin {
        // Allow 0 rate (no fees)
        if (newRate > MAX_FEE_RATE) revert FeeRateLimitExceeded();

        if (redemptionFeeRate != newRate) {
            _setRedemptionFeeRate(newRate);
        }
    }

    /// @inheritdoc IkpkShares
    function setPerformanceFeeRate(uint256 newRate, address usdAsset) external isAdmin {
        // Allow 0 rate (no fees)
        if (newRate > MAX_FEE_RATE) revert FeeRateLimitExceeded(); // Max 20%

        if (performanceFeeRate != newRate) {
            _setPerformanceFeeRate(newRate, usdAsset);
        }
    }

    /// @inheritdoc IkpkShares
    function setPerformanceFeeModule(address newPerfFeeModule) external isAdmin {
        // Allow address(0) to disable performance fees
        _setPerformanceFeeModule(newPerfFeeModule);
    }

    //
    // View Functions
    //

    /// @inheritdoc IkpkShares
    function getApprovedAssets() external view returns (address[] memory) {
        uint256 length = _approvedAssets.length;
        address[] memory assets = new address[](length);
        for (uint256 i = 0; i < length; i++) {
            assets[i] = _approvedAssets[i];
        }
        return assets;
    }

    /// @inheritdoc IkpkShares
    function getApprovedAsset(address asset) external view returns (ApprovedAsset memory) {
        return _approvedAssetsMap[asset];
    }

    /// @inheritdoc IkpkShares
    function isApprovedAsset(address asset) external view returns (bool) {
        ApprovedAsset memory assetConfig = _approvedAssetsMap[asset];
        return assetConfig.asset != address(0) && (assetConfig.canDeposit || assetConfig.canRedeem);
    }

    /// @inheritdoc IkpkShares
    function assetDecimals(address asset) external view returns (uint8) {
        return _approvedAssetsMap[asset].decimals;
    }

    /// @inheritdoc IkpkShares
    function getRequest(uint256 id) external view returns (UserRequest memory) {
        return _requests[id];
    }

    /// @inheritdoc IkpkShares
    function getLastSettledPrice(address asset) external view returns (uint256) {
        return _lastSettledPrice[asset];
    }

    /// @inheritdoc IkpkShares
    function assetsToShares(uint256 assetAmount, uint256 sharesPrice, address subscriptionAsset)
        public
        view
        returns (uint256)
    {
        if (sharesPrice == 0 || assetAmount == 0) return 0;

        ApprovedAsset memory assetConfig = _approvedAssetsMap[subscriptionAsset];
        if (!assetConfig.canDeposit) revert NotAnApprovedAsset();

        uint8 assetDec = assetConfig.decimals;

        // Calculate the value of the assets
        // assetsValue = assetAmount * (10^shareDecimals * 1e18) / sharesPrice
        uint256 assetsValue = assetAmount.mulDiv((10 ** decimals()) * _PRECISION_WAD, sharesPrice, Math.Rounding.Floor);

        // Convert value to shares
        // shares = assetsValue * 1e8 / (10^assetDec * 1e18)
        return assetsValue.mulDiv(_NORMALIZED_PRECISION_USD, (10 ** assetDec) * _PRECISION_WAD, Math.Rounding.Floor);
    }

    /// @inheritdoc IkpkShares
    function sharesToAssets(uint256 shares, uint256 sharesPrice, address redemptionAsset)
        public
        view
        returns (uint256)
    {
        if (sharesPrice == 0 || shares == 0) return 0;

        // Get the asset configuration
        ApprovedAsset memory assetConfig = _approvedAssetsMap[redemptionAsset];
        if (!assetConfig.canRedeem) revert UnredeemableAsset();

        uint8 assetDec = assetConfig.decimals;

        // Calculate the value of the shares
        // sharesValue = shares * (sharesPrice * 1e18) / 1e8
        // This properly handles different asset decimal places
        uint256 sharesValue =
            shares.mulDiv(sharesPrice * _PRECISION_WAD, _NORMALIZED_PRECISION_USD, Math.Rounding.Floor);

        // Convert value to assets
        // assets = sharesValue * 10^assetDec / (10^shareDecimals * 1e18)
        return sharesValue.mulDiv((10 ** assetDec), (10 ** decimals()) * _PRECISION_WAD, Math.Rounding.Floor);
    }
    //
    // Overrides
    //

    /// @inheritdoc UUPSUpgradeable
    // solhint-disable-next-line no-empty-blocks
    function _authorizeUpgrade(
        address /* newImpl */
    )
        internal
        view
        override(UUPSUpgradeable)
        isAdmin
    {
        // Authorization is handled by the isAdmin modifier
    }

    /// @inheritdoc IERC165
    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(IERC165, AccessControlUpgradeable)
        returns (bool)
    {
        return interfaceId == type(IkpkShares).interfaceId || super.supportsInterface(interfaceId);
    }

    /// @inheritdoc RecoverFunds
    /// @dev WARNING: This function assumes tokens are not rebasing or fee-on-transfer.
    function _assetRecoverableAmount(address token) internal view override(RecoverFunds) returns (uint256) {
        // Hard-block the share token from being recovered
        if (token == address(this)) {
            return 0;
        }

        // Check if there are pending requests for this asset (even if config is deleted)
        if (_hasPendingRequests(token)) {
            return 0;
        }

        // Always exclude recorded escrow, even if asset config is deleted
        // This prevents sweeping funds needed for pending subscriptions
        uint256 escrowed = subscriptionAssets[token];
        if (escrowed > 0) {
            return 0;
        }

        return super._assetRecoverableAmount(token);
    }

    /// @inheritdoc RecoverFunds
    function _assetRecoverer() internal view override(RecoverFunds) returns (address) {
        return portfolioSafe;
    }

    //
    // Internal Functions
    //

    //
    // Initialization
    //

    /// @notice Validate initialization parameters
    /// @param params The initialization parameters
    function _validateInitializationParams(ConstructorParams memory params) internal pure {
        if (
            params.asset == address(0) || params.admin == address(0) || params.safe == address(0)
                || params.feeReceiver == address(0) || params.subscriptionRequestTtl == 0
                || params.redemptionRequestTtl == 0
        ) {
            revert InvalidArguments();
        }

        // Validate fee rates are within reasonable bounds.
        if (params.managementFeeRate > MAX_FEE_RATE) revert FeeRateLimitExceeded();
        if (params.performanceFeeRate > MAX_FEE_RATE) revert FeeRateLimitExceeded();
        if (params.redemptionFeeRate > MAX_FEE_RATE) revert FeeRateLimitExceeded();
    }

    /// @notice Initialize contract state variables
    /// @param params The initialization parameters
    /// @dev The base asset MUST be configured with isFeeModuleAsset=true to enable performance fee calculations.
    ///      This asset is used as the base pricing unit for fee module operations.
    function _initializeState(ConstructorParams memory params) internal {
        _updateAsset(params.asset, true, true, true);
        portfolioSafe = params.safe;

        _setFeeReceiver(params.feeReceiver);
        _setManagementFeeRate(params.managementFeeRate);
        _setRedemptionFeeRate(params.redemptionFeeRate);
        _setPerformanceFeeRate(params.performanceFeeRate, params.asset);
        _setPerformanceFeeModule(params.performanceFeeModule);

        // Set TTLs with overflow protection
        _setSubscriptionRequestTtl(params.subscriptionRequestTtl);
        _setRedemptionRequestTtl(params.redemptionRequestTtl);

        // Initialize managementFeeLastUpdate timestamp
        _managementFeeLastUpdate = block.timestamp;
        // Initialize performanceFeeLastUpdate timestamp

        _performanceFeeLastUpdate = block.timestamp;
    }

    /// @notice Setup access control roles
    /// @param admin The initial admin address
    function _setupRoles(address admin) internal {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
    }

    //
    // Request Logic
    //

    /// @notice Require valid request parameters (reverts on invalid)
    /// @param amountIn The amount (assets or shares) for the request
    /// @param amountOut The amount (shares or assets) for the request
    /// @param receiver The receiver address
    function _requireValidRequestParams(uint256 amountIn, uint256 amountOut, address receiver) internal pure {
        if (amountIn == 0 || amountOut == 0 || receiver == address(0)) revert InvalidArguments();
    }

    /// @notice Require cancellation authorization (reverts on invalid)
    /// @param investor The request investor
    /// @param receiver The receiver of the assets or shares
    function _requireCancellationAuthorization(address investor, address receiver) internal view {
        if (investor != msg.sender && receiver != msg.sender) {
            revert NotAuthorized();
        }
    }

    /// @notice Process approved requests
    /// @param approveRequests Array of request IDs to approve
    /// @param asset The asset to approve
    /// @param sharesPrice The price per share in normalized USD units (8 decimals, i.e., _NORMALIZED_PRECISION_USD)
    function _processApproved(uint256[] calldata approveRequests, address asset, uint256 sharesPrice) internal {
        uint256 length = approveRequests.length;
        for (uint256 i; i < length; i++) {
            UserRequest memory request = _requests[approveRequests[i]];
            if (!_checkValidRequest(request.investor, request.requestStatus)) continue;

            if (request.asset != asset) continue;

            // Check if request has expired
            if (block.timestamp > request.expiryAt) {
                // Request has expired, process as rejection and emit expiry event
                if (request.requestType == RequestType.SUBSCRIPTION) {
                    _rejectSubscriptionRequest(approveRequests[i], request);
                    emit SubscriptionRequestExpired(approveRequests[i], request.expiryAt);
                } else {
                    _rejectRedeemRequest(approveRequests[i], request);
                    emit RedemptionRequestExpired(approveRequests[i], request.expiryAt);
                }
                continue;
            }

            if (request.requestType == RequestType.SUBSCRIPTION) {
                _approveSubscriptionRequest(approveRequests[i], request, sharesPrice);
            } else {
                _approveRedeemRequest(approveRequests[i], request, sharesPrice);
            }
        }
    }

    /// @notice Process rejected requests
    /// @param rejectRequests Array of request IDs to reject
    /// @param asset The asset to reject requests for
    function _processRejected(uint256[] calldata rejectRequests, address asset) internal {
        uint256 length = rejectRequests.length;
        for (uint256 i; i < length; i++) {
            UserRequest memory request = _requests[rejectRequests[i]];
            if (!_checkValidRequest(request.investor, request.requestStatus)) continue;
            if (request.asset != asset) continue;

            if (request.requestType == RequestType.SUBSCRIPTION) {
                _rejectSubscriptionRequest(rejectRequests[i], request);
            } else {
                _rejectRedeemRequest(rejectRequests[i], request);
            }
        }
    }

    //
    // Subscription Processing
    //

    /// @notice Approve a subscription request
    /// @param id The ID of the request to approve
    /// @param request Subscription approval request
    /// @param sharesPrice The current price per share in normalized USD units (8 decimals, i.e., _NORMALIZED_PRECISION_USD)
    function _approveSubscriptionRequest(uint256 id, UserRequest memory request, uint256 sharesPrice) internal {
        // Compute sharesOut from the approved assetsIn and sharesPriceInAsset at approval
        uint256 sharesOut = assetsToShares(request.assetAmount, sharesPrice, request.asset);
        // Enforce sharesOut >= minSharesOut (the user's slippage bound)
        if (sharesOut < request.sharesAmount) revert RequestPriceLowerThanOperatorPrice();

        // --- Effects ---
        // Update status to PROCESSED
        // WARNING: request.requestStatus (memory copy) is now out of sync with storage - do not use it after this line.
        _requests[id].requestStatus = RequestStatus.PROCESSED;
        // Update subscription assets tracking
        subscriptionAssets[request.asset] -= request.assetAmount;
        _pendingRequestsCount[request.asset]--;
        // Mint sharesOut to the receiver
        _mint(request.receiver, sharesOut);

        // --- Interaction ---
        // Transfer assets to safe (the fund's vault)
        IERC20(request.asset).safeTransfer(portfolioSafe, request.assetAmount);

        // Emit the event using sharesOut
        emit SubscriptionApproval(id, request.assetAmount, sharesOut);
    }

    /// @notice Reject a subscription request
    /// @param id The ID of the request to reject
    /// @param request Request to reject
    function _rejectSubscriptionRequest(uint256 id, UserRequest memory request) internal {
        // --- Effects ---
        // Update status to REJECTED
        // WARNING: request.requestStatus (memory copy) is now out of sync with storage - do not use it after this line.
        _requests[id].requestStatus = RequestStatus.REJECTED;
        // Update subscription assets tracking
        subscriptionAssets[request.asset] -= request.assetAmount;
        _pendingRequestsCount[request.asset]--;

        // --- Interaction ---
        IERC20(request.asset).safeTransfer(request.investor, request.assetAmount);

        emit SubscriptionDenial(id, request.assetAmount, request.sharesAmount);
    }

    /// @notice Check if a request is valid (returns bool, does not revert)
    /// @param investor The investor address to check
    /// @param requestStatus The request status to check
    /// @return valid Whether the request was valid
    function _checkValidRequest(address investor, RequestStatus requestStatus) internal pure returns (bool) {
        if (investor == address(0) || requestStatus != RequestStatus.PENDING) {
            return false;
        }

        return true;
    }

    /// @notice Check if there are any pending requests (subscriptions or redemptions) for an asset
    /// @param asset The asset address to check
    /// @return hasPending True if there are pending requests for this asset
    /// @dev Uses counter-based tracking for efficient checking
    function _hasPendingRequests(address asset) internal view returns (bool) {
        return _pendingRequestsCount[asset] > 0;
    }

    //
    // Redemption Processing
    //

    /// @notice Approve a redemption request
    /// @param id The ID of the request to approve
    /// @param request Redemption approval request
    /// @param operatorPrice The current price per share in normalized USD units (8 decimals, i.e., _NORMALIZED_PRECISION_USD)
    function _approveRedeemRequest(uint256 id, UserRequest memory request, uint256 operatorPrice) internal {
        // Charge redemption fee before processing the redemption
        uint256 redemptionFee;
        if (redemptionFeeRate > 0) {
            redemptionFee = _chargeRedemptionFee(request);
        }

        // --- Effects ---
        // Calculate net shares to redeem after fees
        uint256 netShares = request.sharesAmount - redemptionFee;

        // Check if operator price is at least as good as the request price
        // Validate using net shares to ensure slippage protection applies to the actual amount received
        uint256 assetsOutNet = sharesToAssets(netShares, operatorPrice, request.asset);
        if (assetsOutNet < request.assetAmount) revert RequestPriceLowerThanOperatorPrice();

        // Update status to PROCESSED
        // WARNING: request.requestStatus (memory copy) is now out of sync with storage - do not use it after this line.
        _requests[id].requestStatus = RequestStatus.PROCESSED;
        _pendingRequestsCount[request.asset]--;
        // Burn only the net shares (fee shares are transferred, not burned)
        _burn(address(this), netShares);

        // --- Interaction (Asset Transfer) ---
        // Transfer assets to receiver
        IERC20(request.asset).safeTransferFrom(portfolioSafe, request.receiver, assetsOutNet);
        emit RedemptionApproval(id, assetsOutNet, request.sharesAmount, redemptionFee);
    }

    /// @notice Reject a redemption request
    /// @param id The ID of the request to reject
    /// @param request Redemption rejection request
    function _rejectRedeemRequest(uint256 id, UserRequest memory request) internal {
        // --- Effects ---
        // Update status to REJECTED
        // WARNING: request.requestStatus (memory copy) is now out of sync with storage - do not use it after this line.
        _requests[id].requestStatus = RequestStatus.REJECTED;
        _pendingRequestsCount[request.asset]--;

        // --- Interaction ---
        _transfer(address(this), request.investor, request.sharesAmount);

        emit RedemptionDenial(id, request.assetAmount, request.sharesAmount);
    }

    //
    // Share Management
    //

    /// @notice Validate that the price deviation from the last settled price is within acceptable bounds
    /// @param asset The asset to validate the price for
    /// @param sharesPriceInAsset The current price per share in normalized USD units (8 decimals)
    /// @dev If there's no previous settled price, the price is accepted (first time processing)
    /// @dev If there is a previous price, the deviation must be within MAX_PRICE_DEVIATION_BPS (10%)
    function _validatePriceDeviation(address asset, uint256 sharesPriceInAsset) internal view {
        uint256 lastPrice = _lastSettledPrice[asset];

        // If there's no previous settled price, accept the price (first time processing)
        if (lastPrice == 0) {
            return;
        }

        // Calculate the absolute deviation
        uint256 deviation;
        if (sharesPriceInAsset > lastPrice) {
            // Price increased
            deviation = sharesPriceInAsset - lastPrice;
        } else {
            // Price decreased
            deviation = lastPrice - sharesPriceInAsset;
        }

        // Calculate deviation in basis points: (deviation * 10000) / lastPrice
        // Use mulDiv to avoid overflow
        uint256 deviationBps = deviation.mulDiv(_PRECISION_BPS, lastPrice, Math.Rounding.Floor);

        // Check if deviation exceeds maximum allowed
        if (deviationBps > MAX_PRICE_DEVIATION_BPS) {
            revert PriceDeviationTooLarge();
        }
    }

    /// @notice Charge management and performance fees based on time elapsed
    /// @param asset The asset to charge fees for
    /// @param sharesPriceInAsset The current price per share in normalized USD units (8 decimals, i.e., _NORMALIZED_PRECISION_USD)
    function _chargeFees(address asset, uint256 sharesPriceInAsset) internal {
        // Charge management and performance fees based on time elapsed
        uint256 managementFee;
        uint256 performanceFee;

        // Management fees use shared managementFeeLastUpdate timestamp
        if (managementFeeRate > 0) {
            uint256 timeElapsed = block.timestamp - _managementFeeLastUpdate;
            if (timeElapsed > MIN_TIME_ELAPSED) {
                // Update state before external calls
                _managementFeeLastUpdate = block.timestamp;
                managementFee = _chargeManagementFee(timeElapsed);
            }
        }

        // Performance fees use asset-specific performanceFeeLastUpdate to prevent gaming
        if (performanceFeeRate > 0 && _approvedAssetsMap[asset].isFeeModuleAsset) {
            uint256 perfTimeElapsed = block.timestamp - _performanceFeeLastUpdate;
            if (perfTimeElapsed > MIN_TIME_ELAPSED) {
                _performanceFeeLastUpdate = block.timestamp;
                performanceFee = _chargePerformanceFee(sharesPriceInAsset, perfTimeElapsed);
            }
        }

        // Only emit FeeCollection event if at least one fee is non-zero
        if (managementFee > 0 || performanceFee > 0) {
            emit FeeCollection(managementFee, performanceFee);
        }
    }

    /// @notice Charge redemption fee and calculate net shares to redeem
    /// @param request The request to charge fees for
    /// @return feeShares The shares remaining after fee deduction
    function _chargeRedemptionFee(UserRequest memory request) internal returns (uint256 feeShares) {
        // Calculate fee shares: feeShares = requestedShares * REDEMPTION_FEE_RATE / 10000
        feeShares = (request.sharesAmount * redemptionFeeRate) / _PRECISION_BPS;

        // Transfer fee shares to fee receiver
        if (feeShares > 0) {
            _transfer(address(this), feeReceiver, feeShares);
        }

        return feeShares;
    }

    /// @notice Calculate and charge management fees based on time elapsed and total supply
    /// @param timeElapsed The time elapsed since last fee calculation
    /// @return The amount of management fee charged
    function _chargeManagementFee(uint256 timeElapsed) internal returns (uint256) {
        uint256 feeReceiverBalance = balanceOf(feeReceiver);
        uint256 feeAmount = ((totalSupply() - feeReceiverBalance) * managementFeeRate * timeElapsed)
            / (_PRECISION_BPS * SECONDS_PER_YEAR);
        if (feeAmount > 0) {
            _mint(feeReceiver, feeAmount);
        }
        return feeAmount;
    }

    /// @notice Calculate and charge performance fees using the performance fee module
    /// @param sharesPriceInUSD The current price per share in normalized USD units (8 decimals, i.e., _NORMALIZED_PRECISION_USD)
    /// @param timeElapsed The time elapsed since last fee calculation
    /// @return The amount of performance fee charged
    function _chargePerformanceFee(uint256 sharesPriceInUSD, uint256 timeElapsed) internal returns (uint256) {
        if (performanceFeeModule == address(0)) {
            return 0;
        }
        uint256 feeReceiverBalance = balanceOf(feeReceiver);
        uint256 netSupply = totalSupply() - feeReceiverBalance;
        uint256 performanceFee = IPerfFeeModule(performanceFeeModule)
            .calculatePerformanceFee(sharesPriceInUSD, timeElapsed, performanceFeeRate, netSupply);
        if (performanceFee > 0) {
            _mint(feeReceiver, performanceFee);
        }
        return performanceFee;
    }

    /// @notice Update asset configuration for deposits and redemptions
    /// @param asset The asset address to configure
    /// @param isFeeModuleAsset Whether the asset can be used for performance fee module calculations
    /// @param canDeposit Whether the asset is approved for deposits
    /// @param canRedeem Whether the asset is approved for redemptions
    /// @dev WARNING: Rebasing tokens (e.g., sUSDe) and fee-on-transfer tokens are NOT supported.
    function _updateAsset(address asset, bool isFeeModuleAsset, bool canDeposit, bool canRedeem) internal {
        if (asset == address(0)) revert InvalidArguments();
        if (asset == address(this)) revert InvalidArguments();

        //check if asset exists
        if (_approvedAssetsMap[asset].asset != address(0)) {
            //check if asset is being removed
            if (!canDeposit && !canRedeem) {
                // Gate full deletion: only allow removal when there are no pending subscriptions/redemptions
                // and subscriptionAssets[asset] == 0
                if (subscriptionAssets[asset] != 0) {
                    revert InvalidArguments(); // Cannot remove asset with pending subscriptions
                }
                // Check for pending requests using counter
                if (_pendingRequestsCount[asset] > 0) {
                    revert InvalidArguments(); // Cannot remove asset with pending requests
                }
                // Prevent removing the last asset
                if (_approvedAssets.length <= 1) {
                    revert InvalidArguments(); // Cannot remove last asset
                }

                _shadowAsset(asset);
                delete _approvedAssetsMap[asset];
                emit AssetRemove(asset);
            } else {
                //update asset configuration
                _approvedAssetsMap[asset].isFeeModuleAsset = isFeeModuleAsset;
                _approvedAssetsMap[asset].canDeposit = canDeposit;
                _approvedAssetsMap[asset].canRedeem = canRedeem;
                emit AssetUpdate(asset, isFeeModuleAsset, canDeposit, canRedeem);
            }
        } else {
            if (!canDeposit && !canRedeem) {
                // cannot add an asset with both canDeposit and canRedeem false
                revert InvalidArguments();
            } else {
                // Set address, symbol and decimals
                _approvedAssetsMap[asset].asset = asset;
                _approvedAssetsMap[asset].symbol = IERC20Metadata(asset).symbol();
                uint8 thisDecimals = IERC20Metadata(asset).decimals();
                if (thisDecimals > 36) revert InvalidArguments(); // Prevent overflow risks
                _approvedAssetsMap[asset].decimals = thisDecimals;
                _approvedAssetsMap[asset].isFeeModuleAsset = isFeeModuleAsset;
                _approvedAssetsMap[asset].canDeposit = canDeposit;
                _approvedAssetsMap[asset].canRedeem = canRedeem;
                //add asset
                _approvedAssets.push(asset);
                emit AssetAdd(asset);
                emit AssetUpdate(asset, isFeeModuleAsset, canDeposit, canRedeem);
            }
        }
    }

    /// @notice Remove an asset from the approved assets list
    /// @param asset The asset address to remove
    function _shadowAsset(address asset) internal {
        uint256 len = _approvedAssets.length;
        for (uint256 i = 0; i < len; i++) {
            if (_approvedAssets[i] == asset) {
                _approvedAssets[i] = _approvedAssets[len - 1];
                _approvedAssets.pop();
                break;
            }
        }
    }

    //
    // Setters
    //

    /// @notice Set subscription request TTL with 7-day maximum limit
    /// @param ttl New TTL value
    function _setSubscriptionRequestTtl(uint64 ttl) internal {
        uint64 newTtl = ttl > MAX_TTL ? MAX_TTL : ttl;
        if (subscriptionRequestTtl != newTtl) {
            subscriptionRequestTtl = newTtl;
            emit SubscriptionRequestTtlUpdate(subscriptionRequestTtl);
        }
    }

    /// @notice Set redemption request TTL with 7-day maximum limit
    /// @param ttl New TTL value
    function _setRedemptionRequestTtl(uint64 ttl) internal {
        uint64 newTtl = ttl > MAX_TTL ? MAX_TTL : ttl;
        if (redemptionRequestTtl != newTtl) {
            redemptionRequestTtl = newTtl;
            emit RedemptionRequestTtlUpdate(redemptionRequestTtl);
        }
    }

    /// @notice Set the fee receiver address
    /// @param newFeeReceiver The new fee receiver address
    function _setFeeReceiver(address newFeeReceiver) internal {
        feeReceiver = newFeeReceiver;
        emit FeeReceiverUpdate(newFeeReceiver);
    }

    /// @notice Set the management fee rate
    /// @param newRate The new management fee rate in basis points
    function _setManagementFeeRate(uint256 newRate) internal {
        // charge any management fees that have not been charged yet
        if (managementFeeRate > 0) {
            _chargeManagementFee(block.timestamp - _managementFeeLastUpdate);
        }
        _managementFeeLastUpdate = block.timestamp;
        managementFeeRate = newRate;
        emit ManagementFeeRateUpdate(newRate);
    }

    /// @notice Set the redemption fee rate
    /// @param newRate The new redemption fee rate in basis points
    function _setRedemptionFeeRate(uint256 newRate) internal {
        redemptionFeeRate = newRate;
        emit RedemptionFeeRateUpdate(newRate);
    }

    /// @notice Set the performance fee rate
    /// @param newRate The new performance fee rate in basis points
    function _setPerformanceFeeRate(uint256 newRate, address usdAsset) internal {
        if (performanceFeeRate > 0 && _approvedAssetsMap[usdAsset].isFeeModuleAsset) {
            _chargePerformanceFee(_lastSettledPrice[usdAsset], block.timestamp - _performanceFeeLastUpdate);
        }
        // if performance fees is not charged due to incompatible asset, update the timestamp
        // and forfeit any performance fees that have not been charged yet
        _performanceFeeLastUpdate = block.timestamp;
        performanceFeeRate = newRate;
        emit PerformanceFeeRateUpdate(newRate);
    }

    /// @notice Set the performance fee module address
    /// @param newPerformanceFeeModule The new performance fee module address
    function _setPerformanceFeeModule(address newPerformanceFeeModule) internal {
        performanceFeeModule = newPerformanceFeeModule;
        emit PerformanceFeeModuleUpdate(newPerformanceFeeModule);
    }
}
