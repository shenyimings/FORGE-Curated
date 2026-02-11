// SPDX-License-Identifier: BUSL-1.1
// Terms: https://liminal.money/xtokens/license

pragma solidity 0.8.28;

import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {IPriceOracle} from "./interfaces/IPriceOracle.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IPyth} from "@pythnetwork/pyth-sdk-solidity/IPyth.sol";
import {PythStructs} from "@pythnetwork/pyth-sdk-solidity/PythStructs.sol";

/**
 * @title PythPriceOracle
 * @notice Oracle integration with Pyth Network price feeds
 * @dev Uses Pyth's pull-based price model with real-time updates
 */
contract PythPriceOracle is AccessControlUpgradeable, IPriceOracle {
    /// @notice Role for managing price IDs
    bytes32 public constant PRICE_MANAGER_ROLE = keccak256("PRICE_MANAGER_ROLE");

    /// @notice Maximum confidence interval threshold in basis points
    uint256 public constant BASIS_POINTS = 10_000;

    /// @custom:storage-location erc7201:liminal.pythPriceOracle.v1
    struct PythPriceOracleStorage {
        /// @notice Timelock controller for critical operations
        address timeLockController;
        /// @notice Asset address to Pyth price ID mapping
        mapping(address => bytes32) priceIds;
        /// @notice Asset decimals for conversion
        mapping(address => uint8) assetDecimals;
        /// @notice Underlying asset of the vault (for redemptions)
        address underlyingAsset;
        /// @notice Pyth Network oracle contract
        IPyth pyth;
        /// @notice Maximum price age for staleness check (default 60 seconds)
        uint96 maxPriceAge;
        /// @notice Maximum confidence interval threshold in basis points (default 50 bps = 0.5%)
        uint256 maxConfidenceBps;
    }

    // keccak256(abi.encode(uint256(keccak256("liminal.storage.pythPriceOracle.v1")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant PYTH_PRICE_ORACLE_STORAGE_LOCATION =
        0x79f8fe64cf697304b8736b5ceebe50109f667154b58cb0fe6be0d930c76b5e00;

    function _getPythPriceOracleStorage() private pure returns (PythPriceOracleStorage storage $) {
        assembly {
            $.slot := PYTH_PRICE_ORACLE_STORAGE_LOCATION
        }
    }

    /// Events
    event PriceIdSet(address indexed asset, bytes32 priceId, uint8 decimals);
    event UnderlyingAssetSet(address indexed asset);
    event MaxPriceAgeUpdated(uint96 newMaxAge);
    event PythContractUpdated(address indexed newPyth);
    event TimelockControllerSet(address indexed oldTimelock, address indexed newTimelock);
    event MaxConfidenceBpsUpdated(uint256 newMaxConfidenceBps);


    /// @notice Modifier for timelock-protected functions
    modifier onlyTimelock() {
        PythPriceOracleStorage storage $ = _getPythPriceOracleStorage();
        require(msg.sender == $.timeLockController, "PythOracle: only timelock");
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initialize the oracle
     * @dev Ownership (DEFAULT_ADMIN_ROLE) is granted to deployer
     * @param _deployer Deployer address (receives DEFAULT_ADMIN_ROLE)
     * @param _priceManager Initial price manager for setting price IDs
     * @param _pyth Pyth Network contract address
     * @param _underlyingAsset Vault's underlying asset for redemptions
     * @param _timeLockController Timelock controller for critical operations
     * @param _maxConfidenceBps Maximum confidence interval threshold in basis points (default 50 bps = 0.5%)
     */
    function initialize(
        address _deployer,
        address _priceManager,
        address _pyth,
        address _underlyingAsset,
        address _timeLockController,
        uint256 _maxConfidenceBps
    ) external initializer {
        require(_deployer != address(0), "PythOracle: zero deployer");
        require(_priceManager != address(0), "PythOracle: zero manager");
        require(_pyth != address(0), "PythOracle: zero pyth");
        require(_underlyingAsset != address(0), "PythOracle: zero underlying");
        require(_timeLockController != address(0), "PythOracle: zero timelock");
        require(_maxConfidenceBps > 0, "PythOracle: zero confidence threshold");
        require(_maxConfidenceBps <= BASIS_POINTS, "PythOracle: confidence threshold too high");

        __AccessControl_init();

        // Grant ownership to deployer
        _grantRole(DEFAULT_ADMIN_ROLE, _deployer);
        _grantRole(PRICE_MANAGER_ROLE, _priceManager);

        PythPriceOracleStorage storage $ = _getPythPriceOracleStorage();
        $.pyth = IPyth(_pyth);
        $.underlyingAsset = _underlyingAsset;
        $.maxPriceAge = 3600; // 1 hour default
        $.timeLockController = _timeLockController;
        $.maxConfidenceBps = _maxConfidenceBps;

        emit UnderlyingAssetSet(_underlyingAsset);
    }

    /**
     * @notice Set Pyth price ID for an asset
     * @param asset Asset address
     * @param priceId Pyth price feed ID (32 bytes)
     * @param decimals Asset token decimals
     */
    function setPriceId(address asset, bytes32 priceId, uint8 decimals) external onlyTimelock {
        require(asset != address(0), "PythOracle: zero asset");
        require(priceId != bytes32(0), "PythOracle: zero price ID");
        require(decimals <= 18, "PythOracle: invalid decimals");
        require(decimals == IERC20Metadata(asset).decimals(), "PythOracle: decimals mismatch");

        PythPriceOracleStorage storage $ = _getPythPriceOracleStorage();
        $.priceIds[asset] = priceId;
        $.assetDecimals[asset] = decimals;

        emit PriceIdSet(asset, priceId, decimals);
    }

    /**
     * @notice Batch set price IDs for multiple assets
     * @param assets Array of asset addresses
     * @param _priceIds Array of Pyth price feed IDs
     * @param decimalsArray Array of token decimals
     */
    function setPriceIds(address[] calldata assets, bytes32[] calldata _priceIds, uint8[] calldata decimalsArray)
        external
        onlyTimelock
    {
        require(assets.length == _priceIds.length, "PythOracle: length mismatch");
        require(assets.length == decimalsArray.length, "PythOracle: decimals mismatch");

        PythPriceOracleStorage storage $ = _getPythPriceOracleStorage();
        for (uint256 i = 0; i < assets.length; i++) {
            require(assets[i] != address(0), "PythOracle: zero asset");
            require(_priceIds[i] != bytes32(0), "PythOracle: zero price ID");
            require(decimalsArray[i] <= 18, "PythOracle: invalid decimals");
            require(decimalsArray[i] == IERC20Metadata(assets[i]).decimals(), "PythOracle: decimals mismatch");

            $.priceIds[assets[i]] = _priceIds[i];
            $.assetDecimals[assets[i]] = decimalsArray[i];

            emit PriceIdSet(assets[i], _priceIds[i], decimalsArray[i]);
        }
    }

    /**
     * @notice Get price of asset in terms of underlying asset
     * @param asset Asset to price
     * @return Price scaled to 18 decimals
     */
    function getPrice(address asset) external view override returns (uint256) {
        PythPriceOracleStorage storage $ = _getPythPriceOracleStorage();
        if (asset == $.underlyingAsset) {
            return 1e18; // 1:1 for underlying asset
        }

        PythStructs.Price memory assetPrice = _getPythPrice(asset);
        PythStructs.Price memory underlyingPrice = _getPythPrice($.underlyingAsset);

        // Convert Pyth prices (with expo) to 18 decimal format
        uint256 assetPriceUSD = _convertPythPrice(assetPrice);
        uint256 underlyingPriceUSD = _convertPythPrice(underlyingPrice);

        // Price = (asset price in USD / underlying price in USD) * 1e18
        return (assetPriceUSD * 1e18) / underlyingPriceUSD;
    }

    /**
     * @notice Get USD price of an asset
     * @param asset Asset address
     * @return Price in USD with 8 decimals (Pyth standard)
     */
    function getPriceInUSD(address asset) external view override returns (uint256) {
        PythStructs.Price memory price = _getPythPrice(asset);
        return _convertPythPrice(price);
    }

    /**
     * @notice Convert amount between assets using Pyth prices
     * @param fromAsset Source asset
     * @param toAsset Target asset
     * @param amount Amount in source asset
     * @return Converted amount in target asset's native decimals (eg: USDC 6 decimals, WETH 18 decimals)
     */
    function convertAmount(address fromAsset, address toAsset, uint256 amount)
        external
        view
        override
        returns (uint256)
    {
        PythPriceOracleStorage storage $ = _getPythPriceOracleStorage();

        if (fromAsset == toAsset) {
            // Same asset conversion - always return the same amount
            return amount;
        }

        PythStructs.Price memory fromPrice = _getPythPrice(fromAsset);
        PythStructs.Price memory toPrice = _getPythPrice(toAsset);

        uint8 fromDecimals = $.assetDecimals[fromAsset];
        uint8 toDecimals = $.assetDecimals[toAsset];

        require(amount > 0, "PythOracle: zero amount");

        // Convert prices to 18 decimals for high precision calculation
        uint256 fromPrice18 = _convertPythPriceTo18Decimals(fromPrice);
        uint256 toPrice18 = _convertPythPriceTo18Decimals(toPrice);

        // Normalize amount to 18 decimals
        uint256 amount18 = _normalizeDecimals(amount, fromDecimals, 18);

        // Calculate: (amount18 * fromPrice18) / toPrice18
        uint256 result18 = (amount18 * fromPrice18) / toPrice18;

        // Always return in the target asset's native decimals
        return _normalizeDecimals(result18, 18, toDecimals);
    }

    /**
     * @notice Get Pyth price with staleness check
     * @param asset Asset address
     * @return Pyth price struct
     */
    function _getPythPrice(address asset) internal view returns (PythStructs.Price memory) {
        PythPriceOracleStorage storage $ = _getPythPriceOracleStorage();
        bytes32 priceId = $.priceIds[asset];
        require(priceId != bytes32(0), "PythOracle: price ID not set");

        // Check staleness
        PythStructs.Price memory price = $.pyth.getPriceNoOlderThan(priceId, $.maxPriceAge);
        // Check that price is positive (price.price is int64)
        require(price.price > 0, "PythOracle: invalid price");

        // Check confidence interval
        _validateConfidence(price, $.maxConfidenceBps);


        return price;
    }

     /**
     * @notice Validate price confidence interval against threshold
     * @param price Pyth price struct
     * @param maxConfThreshold Maximum allowed confidence interval in basis points
     * @dev Reverts if conf/price ratio exceeds the threshold
     */
    function _validateConfidence(PythStructs.Price memory price, uint256 maxConfThreshold) internal pure {
        // Calculate confidence ratio: (conf / price) * BASIS_POINTS
        // Both conf and price have the same exponent, so we can compare them directly
        uint256 confidenceRatioBps = (uint256(price.conf) * BASIS_POINTS) / uint256(uint64(price.price));

        require(
            confidenceRatioBps <= maxConfThreshold,
            "PythOracle: confidence interval too wide"
        );
    }

    /**
     * @notice Convert Pyth price to standard 8-decimal format
     * @param price Pyth price struct
     * @return Price in 8 decimals
     */
    function _convertPythPrice(PythStructs.Price memory price) internal pure returns (uint256) {
        require(price.price > 0, "PythOracle: invalid price");

        // Convert to 8 decimal places
        // If expo = -6 and we want -8, we need to multiply by 10^2
        // If expo = -10 and we want -8, we need to divide by 10^2

        int256 normalizedPrice;
        int32 targetExpo = -8;

        if (price.expo == targetExpo) {
            normalizedPrice = price.price;
        } else if (price.expo > targetExpo) {
            // expo is less negative (fewer decimals), need to add decimals
            // expo=-6, target=-8: multiply by 10^2
            uint256 scaleFactor = 10 ** uint256(int256(price.expo - targetExpo));
            normalizedPrice = price.price * int256(scaleFactor);
        } else {
            // expo is more negative (more decimals), need to remove decimals
            // expo=-10, target=-8: divide by 10^2
            uint256 scaleFactor = 10 ** uint256(int256(targetExpo - price.expo));
            normalizedPrice = price.price / int256(scaleFactor);
        }

        require(normalizedPrice > 0, "PythOracle: price conversion failed");
        return uint256(normalizedPrice);
    }

    /**
     * @notice Convert Pyth price to 18-decimal format for high precision calculations
     * @param price Pyth price struct
     * @return Price in 18 decimals
     */
    function _convertPythPriceTo18Decimals(PythStructs.Price memory price) internal pure returns (uint256) {
        require(price.price > 0, "PythOracle: invalid price");

        // First convert to 8 decimals using existing logic
        uint256 price8Decimals = _convertPythPrice(price);

        // Then convert from 8 decimals to 18 decimals
        return price8Decimals * 1e10; // 18 - 8 = 10
    }

    /**
     * @notice Get maximum of two values
     * @param a First value
     * @param b Second value
     * @return Maximum value
     */
    function max(uint8 a, uint8 b) internal pure returns (uint8) {
        return a > b ? a : b;
    }

    /**
     * @notice Normalize decimals for calculations
     * @param amount Amount to normalize
     * @param fromDecimals Current decimals
     * @param toDecimals Target decimals
     * @return Normalized amount
     */
    function _normalizeDecimals(uint256 amount, uint8 fromDecimals, uint8 toDecimals) internal pure returns (uint256) {
        if (fromDecimals == toDecimals) {
            return amount;
        }

        if (fromDecimals > toDecimals) {
            return amount / (10 ** (fromDecimals - toDecimals));
        } else {
            return amount * (10 ** (toDecimals - fromDecimals));
        }
    }

    // ========== ADMIN FUNCTIONS ==========

    /**
     * @notice Update Pyth contract address
     * @param _pyth New Pyth contract address
     */
    function setPythContract(address _pyth) external onlyTimelock {
        require(_pyth != address(0), "PythOracle: zero address");
        PythPriceOracleStorage storage $ = _getPythPriceOracleStorage();
        $.pyth = IPyth(_pyth);
        emit PythContractUpdated(_pyth);
    }

    /**
     * @notice Update underlying asset
     * @param _underlyingAsset New underlying asset address
     */
    function setUnderlyingAsset(address _underlyingAsset) external onlyTimelock {
        require(_underlyingAsset != address(0), "PythOracle: zero address");
        PythPriceOracleStorage storage $ = _getPythPriceOracleStorage();
        $.underlyingAsset = _underlyingAsset;
        emit UnderlyingAssetSet(_underlyingAsset);
    }

    /**
     * @notice Update maximum price age
     * @param _maxPriceAge New maximum age in seconds
     */
    function setMaxPriceAge(uint96 _maxPriceAge) external onlyTimelock {
        require(_maxPriceAge > 0, "PythOracle: zero max age");
        PythPriceOracleStorage storage $ = _getPythPriceOracleStorage();
        $.maxPriceAge = _maxPriceAge;
        emit MaxPriceAgeUpdated(_maxPriceAge);
    }

    /**
     * @notice Set the timelock controller
     * @param _timeLockController New timelock controller address
     * @dev Can only be called by the current timelock (with delay enforced by VaultTimelockController)
     */
    function setTimelockController(address _timeLockController) external onlyTimelock {
        require(_timeLockController != address(0), "PythOracle: zero timelock");

        PythPriceOracleStorage storage $ = _getPythPriceOracleStorage();
        address oldTimelock = $.timeLockController;
        $.timeLockController = _timeLockController;

        emit TimelockControllerSet(oldTimelock, _timeLockController);
    }

     /**
     * @notice Update maximum confidence interval threshold
     * @param _maxConfidenceBps New maximum confidence interval in basis points
     */
    function setMaxConfidenceBps(uint256 _maxConfidenceBps) external onlyTimelock {
        require(_maxConfidenceBps > 0, "PythOracle: zero confidence threshold");
        require(_maxConfidenceBps <= BASIS_POINTS, "PythOracle: confidence threshold too high");
        PythPriceOracleStorage storage $ = _getPythPriceOracleStorage();
        $.maxConfidenceBps = _maxConfidenceBps;
        emit MaxConfidenceBpsUpdated(_maxConfidenceBps);
    }


    /**
     * @notice Check if asset has price feed configured
     * @param asset Asset address
     * @return True if price ID is set
     */
    function hasPriceFeed(address asset) external view returns (bool) {
        PythPriceOracleStorage storage $ = _getPythPriceOracleStorage();
        return $.priceIds[asset] != bytes32(0);
    }

    /**
     * @notice Get the latest price update fee for Pyth
     * @param updateData Array of price update data
     * @return fee Update fee in wei
     */
    function getUpdateFee(bytes[] calldata updateData) external view returns (uint256) {
        PythPriceOracleStorage storage $ = _getPythPriceOracleStorage();
        return $.pyth.getUpdateFee(updateData);
    }

    // ========== GETTER FUNCTIONS ==========

    /// @notice Get timelock controller address
    function timeLockController() external view returns (address) {
        return _getPythPriceOracleStorage().timeLockController;
    }

    /// @notice Get Pyth contract address
    function pyth() external view returns (IPyth) {
        return _getPythPriceOracleStorage().pyth;
    }

    /// @notice Get price ID for an asset
    function priceIds(address asset) external view returns (bytes32) {
        return _getPythPriceOracleStorage().priceIds[asset];
    }

    /// @notice Get asset decimals
    function assetDecimals(address asset) external view returns (uint8) {
        return _getPythPriceOracleStorage().assetDecimals[asset];
    }

    /// @notice Get underlying asset address
    function underlyingAsset() external view returns (address) {
        return _getPythPriceOracleStorage().underlyingAsset;
    }

    /// @notice Get maximum price age
    function maxPriceAge() external view returns (uint96) {
        return _getPythPriceOracleStorage().maxPriceAge;
    }

    /// @notice Get maximum confidence interval threshold
    function maxConfidenceBps() external view returns (uint256) {
        return _getPythPriceOracleStorage().maxConfidenceBps;
    }
}
