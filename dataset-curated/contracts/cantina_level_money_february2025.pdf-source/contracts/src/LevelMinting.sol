// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.19;

/**
 * solhint-disable private-vars-leading-underscore
 */
import {SingleAdminAccessControl} from "./auth/v4/SingleAdminAccessControl.sol";
import "@openzeppelin-4.9.0/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import "./interfaces/AggregatorV3Interface.sol";
import "./interfaces/IlvlUSD.sol";
import "./interfaces/ILevelMinting.sol";

/**
 * @title Level Minting Contract
 * @notice This contract issues and redeems lvlUSD for/from other accepted stablecoins
 * @dev Changelog: change name to LevelMinting and lvlUSD, update solidity versions
 */
contract LevelMinting is ILevelMinting, SingleAdminAccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.AddressSet;

    /* --------------- CONSTANTS --------------- */

    /// @notice role enabling to disable mint and redeem
    bytes32 private constant GATEKEEPER_ROLE = keccak256("GATEKEEPER_ROLE");

    /// @notice role for minting lvlUSD
    bytes32 private constant MINTER_ROLE = keccak256("MINTER_ROLE");

    /// @notice role for redeeming lvlUSD
    bytes32 private constant REDEEMER_ROLE = keccak256("REDEEMER_ROLE");

    /* --------------- STATE VARIABLES --------------- */

    /// @notice lvlusd stablecoin
    IlvlUSD public immutable lvlusd;

    /// @notice Supported assets
    EnumerableSet.AddressSet internal _supportedAssets;

    /// @notice Redeemable assets
    EnumerableSet.AddressSet internal _redeemableAssets;

    // @notice reserve addresses
    EnumerableSet.AddressSet internal _reserveAddresses;

    /// @notice lvlUSD minted per block
    mapping(uint256 => uint256) public mintedPerBlock;
    /// @notice lvlUSD redeemed per block
    mapping(uint256 => uint256) public redeemedPerBlock;

    /// @notice max minted lvlUSD allowed per block
    uint256 public maxMintPerBlock;
    /// @notice max redeemed lvlUSD allowed per block
    uint256 public maxRedeemPerBlock;

    bool public checkMinterRole = false;
    bool public checkRedeemerRole = false;

    uint24 public constant MAX_COOLDOWN_DURATION = 21 days;
    uint24 public cooldownDuration;

    mapping(address => mapping(address => UserCooldown)) public cooldowns;
    // mapping from collateral asset address to total amount of lvlUSD locked for redemptions
    mapping(address => uint256) public pendingRedemptionlvlUSDAmounts;

    Route _route;

    // collateral token address to chainlink oracle address map
    mapping(address => address) public oracles;
    mapping(address => uint256) public heartbeats;

    // oracle heart beat (used for staleness check)
    // this is the chainlink heartbeat for USDC and USDT
    // other tokens may have different heartbeats, which can be set using setHeartBeat
    uint256 public DEFAULT_HEART_BEAT = 86400;

    /* --------------- MODIFIERS --------------- */

    /// @notice ensure that the already minted lvlUSD in the actual block plus the amount to be minted is below the maxMintPerBlock var
    /// @param mintAmount The lvlUSD amount to be minted
    modifier belowMaxMintPerBlock(uint256 mintAmount) {
        if (mintedPerBlock[block.number] + mintAmount > maxMintPerBlock) {
            revert MaxMintPerBlockExceeded();
        }
        _;
    }

    /// @notice ensure that the already redeemed lvlUSD in the actual block plus the amount to be redeemed is below the maxRedeemPerBlock var
    /// @param redeemAmount The lvlUSD amount to be redeemed
    modifier belowMaxRedeemPerBlock(uint256 redeemAmount) {
        if (redeemedPerBlock[block.number] + redeemAmount > maxRedeemPerBlock) {
            revert MaxRedeemPerBlockExceeded();
        }
        _;
    }

    modifier onlyMinterWhenEnabled() {
        if (checkMinterRole) {
            _checkRole(MINTER_ROLE);
        }
        _;
    }

    modifier onlyRedeemerWhenEnabled() {
        if (checkRedeemerRole) {
            _checkRole(REDEEMER_ROLE);
        }
        _;
    }

    /// @notice ensure cooldownDuration is zero
    modifier ensureCooldownOff() {
        if (cooldownDuration != 0) revert OperationNotAllowed();
        _;
    }

    /// @notice ensure cooldownDuration is gt 0
    modifier ensureCooldownOn() {
        if (cooldownDuration == 0) revert OperationNotAllowed();
        _;
    }

    /* --------------- CONSTRUCTOR --------------- */

    // Note: It is required that _assets.length == _oracles.length
    // Note: It is required that _reserves.length == _ratios.length
    constructor(
        IlvlUSD _lvlusd,
        address[] memory _assets,
        address[] memory _oracles, // oracle addresses
        address[] memory _reserves,
        uint256[] memory _ratios,
        address _admin,
        uint256 _maxMintPerBlock,
        uint256 _maxRedeemPerBlock
    ) {
        if (address(_lvlusd) == address(0)) revert InvalidlvlUSDAddress();
        if (_assets.length == 0) revert NoAssetsProvided();
        if (_admin == address(0)) revert InvalidZeroAddress();
        if (_assets.length != _oracles.length) {
            revert OraclesLengthNotEqualToAssetsLength();
        }

        lvlusd = _lvlusd;

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);

        for (uint256 i = 0; i < _assets.length; i++) {
            addSupportedAsset(_assets[i]);
        }

        for (uint256 i = 0; i < _assets.length; i++) {
            addOracle(_assets[i], _oracles[i]);
        }

        for (uint256 j = 0; j < _reserves.length; j++) {
            addReserveAddress(_reserves[j]);
        }

        // Set the max mint/redeem limits per block
        _setMaxMintPerBlock(_maxMintPerBlock);
        _setMaxRedeemPerBlock(_maxRedeemPerBlock);

        if (msg.sender != _admin) {
            _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        }

        cooldownDuration = 9 days;

        if (!verifyRatios(_ratios)) {
            revert InvalidRatios();
        }
        require(_ratios.length == _reserves.length, "ratios and reserves must have same length");
        _route = Route(_reserves, _ratios);

        emit lvlUSDSet(address(_lvlusd));
    }

    /* --------------- EXTERNAL --------------- */

    /**
     * @notice Mint stablecoins from assets
     * @param order struct containing order details and confirmation from server
     * @param route the addresses to which the collateral should be sent (and ratios describing the amount to send to each address)
     */
    function _mint(Order memory order, Route memory route)
        internal
        nonReentrant
        belowMaxMintPerBlock(order.lvlusd_amount)
    {
        require(!(lvlusd.denylisted(msg.sender)));
        if (order.order_type != OrderType.MINT) revert InvalidOrder();
        verifyOrder(order);
        if (!verifyRoute(route, order.order_type)) revert InvalidRoute();
        // Add to the minted amount in this block
        mintedPerBlock[block.number] += order.lvlusd_amount;
        _transferCollateral(
            order.collateral_amount, order.collateral_asset, order.benefactor, route.addresses, route.ratios
        );
        lvlusd.mint(order.beneficiary, order.lvlusd_amount);
        emit Mint(
            msg.sender,
            order.benefactor,
            order.beneficiary,
            order.collateral_asset,
            order.collateral_amount,
            order.lvlusd_amount
        );
    }

    function mint(Order memory order, Route calldata route) external virtual onlyMinterWhenEnabled {
        if (msg.sender != order.benefactor) {
            revert MsgSenderIsNotBenefactor();
        }
        Order memory _order = computeCollateralOrlvlUSDAmount(order);
        _mint(_order, route);
    }

    function mintDefault(Order memory order) external virtual onlyMinterWhenEnabled {
        if (msg.sender != order.benefactor) {
            revert MsgSenderIsNotBenefactor();
        }
        Order memory _order = computeCollateralOrlvlUSDAmount(order);
        _mint(_order, _route);
    }

    function setCooldownDuration(uint24 newDuration) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(newDuration <= MAX_COOLDOWN_DURATION, "newDuration exceeds MAX_COOLDOWN_DURATION");
        cooldownDuration = newDuration;
    }

    /**
     * @notice Redeem stablecoins for assets
     * @param order struct containing order details and confirmation from server
     */
    function _redeem(Order memory order) internal nonReentrant belowMaxRedeemPerBlock(order.lvlusd_amount) {
        // Add to the redeemed amount in this block
        redeemedPerBlock[block.number] += order.lvlusd_amount;

        _transferToBeneficiary(order.beneficiary, order.collateral_asset, order.collateral_amount);

        emit Redeem(
            msg.sender,
            order.benefactor,
            order.beneficiary,
            order.collateral_asset,
            order.collateral_amount,
            order.lvlusd_amount
        );
    }

    // Given an order object, computes either the lvlUSD or collateral asset amount
    // using price from chainlink oracle
    // Note: when minting, the price is taken to be min(oracle_price, 1)
    // Note: when redeeming, the price is taken to be max(oracle_price, 1)
    // These ensure that the protocol remains fully collateralized.
    function computeCollateralOrlvlUSDAmount(Order memory order) private view returns (Order memory) {
        (int256 price, uint256 decimals) = getPriceAndDecimals(order.collateral_asset);
        if (price == 0) {
            revert OraclePriceIsZero();
        }
        Order memory newOrder = Order({
            order_type: order.order_type,
            collateral_asset: order.collateral_asset,
            benefactor: order.benefactor,
            beneficiary: order.beneficiary,
            collateral_amount: order.collateral_amount,
            lvlusd_amount: order.lvlusd_amount
        });

        uint8 collateral_asset_decimals = ERC20(order.collateral_asset).decimals();
        uint8 lvlusd_decimals = lvlusd.decimals();
        if (order.order_type == OrderType.MINT) {
            uint256 new_lvlusd_amount;
            // Note: it is assumed that only stablecoins are used as collateral, which
            // is why we compare the price to $1
            if (uint256(price) < 10 ** decimals) {
                new_lvlusd_amount = (order.collateral_amount * uint256(price) * 10 ** (lvlusd_decimals))
                    / 10 ** (decimals) / 10 ** (collateral_asset_decimals);
            } else {
                // assume unit price ($1)
                new_lvlusd_amount =
                    (order.collateral_amount * (10 ** (lvlusd_decimals))) / (10 ** (collateral_asset_decimals));
            }
            // ensure that calculated lvlusd amount exceeds the user-specified minimum
            if (new_lvlusd_amount < order.lvlusd_amount) {
                revert MinimumlvlUSDAmountNotMet();
            }
            newOrder.lvlusd_amount = new_lvlusd_amount;
        } else {
            // redeem
            uint256 new_collateral_amount;
            if (uint256(price) > 10 ** decimals) {
                new_collateral_amount = (order.lvlusd_amount * (10 ** (decimals)) * (10 ** (collateral_asset_decimals)))
                    / uint256(price) / (10 ** (lvlusd_decimals));
            } else {
                // assume unit price
                new_collateral_amount =
                    (order.lvlusd_amount * (10 ** (collateral_asset_decimals))) / (10 ** (lvlusd_decimals));
            }
            // ensure that calculated collateral amount exceeds the user-specified minimum
            if (new_collateral_amount < order.collateral_amount) {
                revert MinimumCollateralAmountNotMet();
            }
            newOrder.collateral_amount = new_collateral_amount;
        }
        return newOrder;
    }

    function initiateRedeem(Order memory order) external ensureCooldownOn onlyRedeemerWhenEnabled {
        if (order.order_type != OrderType.REDEEM) revert InvalidOrder();

        if (!_redeemableAssets.contains(order.collateral_asset)) {
            revert UnsupportedAsset();
        }
        if (msg.sender != order.benefactor) {
            revert MsgSenderIsNotBenefactor();
        }
        UserCooldown memory newCooldown = UserCooldown({cooldownStart: uint104(block.timestamp), order: order});

        cooldowns[msg.sender][order.collateral_asset] = newCooldown;

        pendingRedemptionlvlUSDAmounts[order.collateral_asset] += order.lvlusd_amount;

        // lock lvlUSD in this contract while user waits to redeem collateral
        lvlusd.transferFrom(order.benefactor, address(this), order.lvlusd_amount);

        emit RedeemInitiated(msg.sender, order.collateral_asset, order.collateral_amount, order.lvlusd_amount);
    }

    function completeRedeem(
        address token // collateral
    ) external virtual onlyRedeemerWhenEnabled {
        UserCooldown memory userCooldown = cooldowns[msg.sender][token];
        if (block.timestamp >= userCooldown.cooldownStart + cooldownDuration) {
            userCooldown.cooldownStart = type(uint104).max;
            cooldowns[msg.sender][token] = userCooldown;
            Order memory _order = computeCollateralOrlvlUSDAmount(userCooldown.order);
            _redeem(_order);
            // burn user-provided lvlUSD that is locked in this contract
            lvlusd.burn(userCooldown.order.lvlusd_amount);
            pendingRedemptionlvlUSDAmounts[userCooldown.order.collateral_asset] -= userCooldown.order.lvlusd_amount;
            emit RedeemCompleted(
                msg.sender,
                userCooldown.order.collateral_asset,
                userCooldown.order.collateral_amount,
                userCooldown.order.lvlusd_amount
            );
        } else {
            revert InvalidCooldown();
        }
    }

    function redeem(Order memory order) external virtual ensureCooldownOff onlyRedeemerWhenEnabled {
        if (order.order_type != OrderType.REDEEM) revert InvalidOrder();
        if (msg.sender != order.benefactor) {
            revert MsgSenderIsNotBenefactor();
        }
        Order memory _order = computeCollateralOrlvlUSDAmount(order);
        _redeem(_order);
        lvlusd.burnFrom(order.benefactor, order.lvlusd_amount);
    }

    /// @notice Sets the max mintPerBlock limit
    function setMaxMintPerBlock(uint256 _maxMintPerBlock) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setMaxMintPerBlock(_maxMintPerBlock);
    }

    /// @notice Sets the max redeemPerBlock limit
    function setMaxRedeemPerBlock(uint256 _maxRedeemPerBlock) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setMaxRedeemPerBlock(_maxRedeemPerBlock);
    }

    /// @notice Disables the mint and redeem
    function disableMintRedeem() external onlyRole(GATEKEEPER_ROLE) {
        _setMaxMintPerBlock(0);
        _setMaxRedeemPerBlock(0);
    }

    /// @notice transfers an asset to a reserve wallet
    function transferToReserve(address wallet, address asset, uint256 amount)
        external
        nonReentrant
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        if (wallet == address(0) || !_reserveAddresses.contains(wallet)) {
            revert InvalidAddress();
        }
        IERC20(asset).safeTransfer(wallet, amount);
        emit ReserveTransfer(wallet, asset, amount);
    }

    /// @notice Removes an asset from the supported assets list
    function removeSupportedAsset(address asset) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (!_supportedAssets.remove(asset)) revert InvalidAssetAddress();
        emit AssetRemoved(asset);
    }

    function removeRedeemableAssets(address asset) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (!_redeemableAssets.remove(asset)) revert InvalidAssetAddress();
        emit RedeemableAssetRemoved(asset);
    }

    /// @notice Checks if an asset is supported.
    function isSupportedAsset(address asset) external view returns (bool) {
        return _supportedAssets.contains(asset);
    }

    /// @notice Removes a reserve from the reserve address list
    function removeReserveAddress(address reserve) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (!_reserveAddresses.remove(reserve)) revert InvalidReserveAddress();
        emit ReserveAddressRemoved(reserve);
    }

    /// @notice Removes the minter role from an account, this can ONLY be executed by the gatekeeper role
    /// @param minter The address to remove the minter role from
    function removeMinterRole(address minter) external onlyRole(GATEKEEPER_ROLE) {
        _revokeRole(MINTER_ROLE, minter);
    }

    /// @notice Removes the redeemer role from an account, this can ONLY be executed by the gatekeeper role
    /// @param redeemer The address to remove the redeemer role from
    function removeRedeemerRole(address redeemer) external onlyRole(GATEKEEPER_ROLE) {
        _revokeRole(REDEEMER_ROLE, redeemer);
    }

    /* --------------- PUBLIC --------------- */

    function getPriceAndDecimals(address collateralToken) public view returns (int256, uint256) {
        address oracle = oracles[collateralToken];
        if (oracle == address(0)) {
            revert OracleUndefined();
        }
        uint8 decimals = AggregatorV3Interface(oracle).decimals();
        (, int256 answer,, uint256 updatedAt,) = AggregatorV3Interface(oracle).latestRoundData();
        require(answer > 0, "invalid price");
        uint256 heartBeat = heartbeats[collateralToken];
        if (heartBeat == 0) {
            heartBeat = DEFAULT_HEART_BEAT;
        }
        require(block.timestamp <= updatedAt + heartBeat, "stale price");
        return (answer, decimals);
    }

    /// @notice Adds an asset to the supported assets list.
    function addSupportedAsset(address asset) public onlyRole(DEFAULT_ADMIN_ROLE) {
        if (asset == address(0) || asset == address(lvlusd) || !_supportedAssets.add(asset)) {
            revert InvalidAssetAddress();
        }
        _redeemableAssets.add(asset);
        emit AssetAdded(asset);
    }

    function addOracle(address collateral, address oracle) public onlyRole(DEFAULT_ADMIN_ROLE) {
        oracles[collateral] = oracle;
    }

    function setHeartBeat(address collateral, uint256 heartBeat) public onlyRole(DEFAULT_ADMIN_ROLE) {
        heartbeats[collateral] = heartBeat;
    }

    /// @notice Adds a reserve to the supported reserves list.
    function addReserveAddress(address reserve) public onlyRole(DEFAULT_ADMIN_ROLE) {
        if (reserve == address(0) || reserve == address(lvlusd) || !_reserveAddresses.add(reserve)) {
            revert InvalidReserveAddress();
        }
        emit ReserveAddressAdded(reserve);
    }

    /// @notice assert validity of order
    function verifyOrder(Order memory order) public pure override returns (bool) {
        if (order.beneficiary == address(0)) revert InvalidAmount();
        if (order.collateral_amount == 0) revert InvalidAmount();
        if (order.lvlusd_amount == 0) revert InvalidAmount();
        return true;
    }

    function verifyRatios(uint256[] memory ratios) public pure returns (bool) {
        uint256 total = 0;
        for (uint256 i = 0; i < ratios.length; i++) {
            total += ratios[i];
        }
        return total == 10_000;
    }

    /// @notice assert validity of route object per type
    function verifyRoute(Route memory route, OrderType orderType) public view override returns (bool) {
        // routes only used to mint
        if (orderType == OrderType.REDEEM) {
            return true;
        }
        if (route.addresses.length != route.ratios.length) {
            return false;
        }
        if (route.addresses.length == 0) {
            return false;
        }
        for (uint256 i = 0; i < route.addresses.length; ++i) {
            if (
                !_reserveAddresses.contains(route.addresses[i]) || route.addresses[i] == address(0)
                    || route.ratios[i] == 0
            ) {
                return false;
            }
        }
        if (!verifyRatios(route.ratios)) {
            return false;
        }
        return true;
    }

    function setCheckMinterRole(bool _check) external onlyRole(DEFAULT_ADMIN_ROLE) {
        checkMinterRole = _check;
    }

    function setCheckRedeemerRole(bool _check) external onlyRole(DEFAULT_ADMIN_ROLE) {
        checkRedeemerRole = _check;
    }

    function setRoute(address[] memory _reserves, uint256[] memory _ratios) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_reserves.length == _ratios.length, "Reserves and ratios must have the same length");
        for (uint256 i = 0; i < _reserves.length; i++) {
            require(_reserveAddresses.contains(_reserves[i]), "Reserve address not found in _reserveAddresses");
        }
        require(verifyRatios(_ratios), "ratios do not add up to 10,000");
        _route = Route(_reserves, _ratios);
    }

    /* --------------- INTERNAL --------------- */

    /// @notice transfer supported asset to beneficiary address
    function _transferToBeneficiary(address beneficiary, address asset, uint256 amount) internal {
        if (!_redeemableAssets.contains(asset)) revert UnsupportedAsset();
        IERC20(asset).safeTransfer(beneficiary, amount);
    }

    /// @notice transfer supported asset to array of reserve addresses per defined ratio
    function _transferCollateral(
        uint256 amount,
        address asset,
        address benefactor,
        address[] memory addresses,
        uint256[] memory ratios
    ) internal {
        // cannot mint using unsupported asset or native ETH even if it is supported for redemptions
        if (!_supportedAssets.contains(asset)) revert UnsupportedAsset();
        IERC20 token = IERC20(asset);
        uint256 totalTransferred;
        uint256 amountToTransfer;
        for (uint256 i = 0; i < addresses.length - 1; ++i) {
            amountToTransfer = (amount * ratios[i]) / 10_000;
            totalTransferred += amountToTransfer;
            token.safeTransferFrom(benefactor, addresses[i], amountToTransfer);
        }
        token.safeTransferFrom(benefactor, addresses[addresses.length - 1], amount - totalTransferred);
    }

    /// @notice Sets the max mintPerBlock limit
    function _setMaxMintPerBlock(uint256 _maxMintPerBlock) internal {
        uint256 oldMaxMintPerBlock = maxMintPerBlock;
        maxMintPerBlock = _maxMintPerBlock;
        emit MaxMintPerBlockChanged(oldMaxMintPerBlock, maxMintPerBlock);
    }

    /// @notice Sets the max redeemPerBlock limit
    function _setMaxRedeemPerBlock(uint256 _maxRedeemPerBlock) internal {
        uint256 oldMaxRedeemPerBlock = maxRedeemPerBlock;
        maxRedeemPerBlock = _maxRedeemPerBlock;
        emit MaxRedeemPerBlockChanged(oldMaxRedeemPerBlock, maxRedeemPerBlock);
    }
}
