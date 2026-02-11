// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.0 <0.9.0;

import {IPositionManager} from "../../interfaces/IPositionManager.sol";

import {IOptionPricingV2} from "./pricing/IOptionPricingV2.sol";
import {IHandler} from "../../interfaces/IHandler.sol";
import {IClammFeeStrategyV2} from "./pricing/fees/IClammFeeStrategyV2.sol";
import {ISwapper} from "../../interfaces/ISwapper.sol";
import {ITokenURIFetcher} from "../../interfaces/ITokenURIFetcher.sol";
import {IVerifiedSpotPrice} from "../../interfaces/IVerifiedSpotPrice.sol";

import {ERC721} from "../../libraries/tokens/ERC721.sol";
import {ERC20} from "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import {Multicall} from "openzeppelin-contracts/contracts/utils/Multicall.sol";

import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {LiquidityAmounts} from "v3-periphery/libraries/LiquidityAmounts.sol";
import {TickMath} from "@uniswap/v3-core/contracts/libraries/TickMath.sol";
import {FullMath} from "@uniswap/v3-core/contracts/libraries/FullMath.sol";

/// @title OptionMarketOTMFE (Option Market Out-of-the-Money Fixed Expiry)
/// @author 0xcarrot
/// @notice This contract implements an options market for out-of-the-money (OTM) options with fixed expiry
/// @dev Inherits from ReentrancyGuard, Multicall, Ownable, and ERC721
contract OptionMarketOTMFE is ReentrancyGuard, Multicall, Ownable, ERC721 {
    using TickMath for int24;
    using SafeERC20 for ERC20;

    /// @notice Struct to store option data
    struct OptionData {
        uint256 opTickArrayLen;
        uint256 expiry;
        int24 tickLower;
        int24 tickUpper;
        bool isCall;
    }

    /// @notice Struct to store option ticks data
    struct OptionTicks {
        IHandler _handler;
        IUniswapV3Pool pool;
        address hook;
        int24 tickLower;
        int24 tickUpper;
        uint256 liquidityToUse;
    }

    /// @notice Struct for option parameters
    struct OptionParams {
        OptionTicks[] optionTicks;
        uint256 ttl;
        uint256 maxCostAllowance;
        int24 tickLower;
        int24 tickUpper;
        bool isCall;
    }

    /// @notice Struct for settling option parameters
    struct SettleOptionParams {
        uint256 optionId;
        ISwapper[] swapper;
        bytes[] swapData;
        uint256[] liquidityToSettle;
    }

    /// @notice Struct for position splitter parameters
    struct PositionSplitterParams {
        uint256 optionId;
        address to;
        uint256[] liquidityToSplit;
    }

    // Events
    event LogMintOption(
        OptionParams _params, uint256 optionId, uint256 premiumAmount, uint256 size, uint256 protocolFees
    );
    event LogSettleOption(AssetsCache assetsCache, uint256[] liquiditySettled, address owner, uint256 optionId);
    event LogSplitOption(PositionSplitterParams params, uint256 newOptionId, address oldOwner);
    event LogUpdateExerciseDelegate(address owner, address delegate, bool status);
    event LogOptionsMarketInitialized(
        address primePool, address optionPricing, address dpFee, address callAsset, address putAsset
    );
    event LogUpdatePoolApprovals(
        address settler,
        bool statusSettler,
        address pool,
        bool statusPools,
        uint256 ttl,
        uint256 ttlStartTime,
        bool ttlStatus,
        uint256 bufferTime
    );
    event LogUpdatePoolSettings(address feeTo, address tokenURIFetcher, address dpFee, address optionPricing);
    event LogUpdateApprovedSwapper(address swapper, bool status);
    event LogUpdateApprovedHook(address hook, bool status);
    event LogUpdateApprovedMinter(address minter, bool status);

    // Errors
    error MaxOptionBuyReached();
    error IVNotSet();
    error NotValidStrikeTick();
    error PoolNotApproved();
    error MaxCostAllowanceExceeded();
    error NotOwnerOrDelegator();
    error ArrayLenMismatch();
    error NotEnoughAfterSwap();
    error NotApprovedSettler();
    error InvalidPool();
    error NotApprovedTTL();
    error InBUFFER_TIME();
    error Expired();
    error TTLNotSet();
    error NotApprovedSwapper();
    error NotApprovedHook();
    error MinLiquidityToUse();
    error NotApprovedMinter();

    /// @notice Counter for option IDs
    uint256 public optionIds;

    /// @notice Buffer time for option expiry
    uint256 BUFFER_TIME = 10 minutes;

    /// @notice Interface for fee strategy
    IClammFeeStrategyV2 public dpFee;
    /// @notice Interface for option pricing
    IOptionPricingV2 public optionPricing;

    /// @notice Interface for verified spot price
    IVerifiedSpotPrice public verifiedSpotPrice;

    /// @notice Interface for position manager
    IPositionManager public immutable positionManager;
    /// @notice Interface for prime pool
    IUniswapV3Pool public immutable primePool;

    /// @notice Address of the call asset
    address public immutable callAsset;
    /// @notice Address of the put asset
    address public immutable putAsset;

    /// @notice Address to receive fees
    address public feeTo;

    /// @notice Address of the token URI fetcher
    address public tokenURIFetcher;

    /// @notice Decimals of the call asset
    uint8 public immutable callAssetDecimals;
    /// @notice Decimals of the put asset
    uint8 public immutable putAssetDecimals;

    /// @notice Maximum tick difference
    uint24 public maxTickDiff;

    /// @notice Maximum upper tick
    int24 maxUpperTick;
    /// @notice Minimum lower tick
    int24 minLowerTick;

    /// @notice Minimum liquidity to use
    uint128 minLiquidityToUse;

    /// @notice Mapping of option ID to option data
    mapping(uint256 => OptionData) public opData;
    /// @notice Mapping of option ID to option ticks
    mapping(uint256 => OptionTicks[]) public opTickMap;
    /// @notice Mapping of pool address to approval status
    mapping(address => bool) public approvedPools;
    /// @notice Mapping of settler address to approval status
    mapping(address => bool) public settlers;
    /// @notice Mapping of TTL to approval status
    mapping(uint256 => bool) public approvedTTLs;
    /// @notice Mapping of TTL to start time
    mapping(uint256 => uint256) public ttlStartTime;
    /// @notice Mapping of swapper address to approval status
    mapping(address => bool) public approvedSwapper;
    /// @notice Mapping of approved hooks
    mapping(address => bool) public approvedHooks;
    /// @notice Mapping of minter address to approval status
    mapping(address => bool) public approvedMinters;

    /// @notice Constructor for the OptionMarketOTM_Fixed_Expiry_V1 contract
    /// @param _pm Address of the position manager
    /// @param _optionPricing Address of the option pricing contract
    /// @param _dpFee Address of the fee strategy contract
    /// @param _callAsset Address of the call asset
    /// @param _putAsset Address of the put asset
    /// @param _primePool Address of the prime pool
    constructor(
        address _pm,
        address _optionPricing,
        address _dpFee,
        address _callAsset,
        address _putAsset,
        address _primePool,
        address _verifiedSpotPrice
    ) Ownable(msg.sender) {
        positionManager = IPositionManager(_pm);
        callAsset = _callAsset;
        putAsset = _putAsset;

        dpFee = IClammFeeStrategyV2(_dpFee);

        optionPricing = IOptionPricingV2(_optionPricing);

        primePool = IUniswapV3Pool(_primePool);

        verifiedSpotPrice = IVerifiedSpotPrice(_verifiedSpotPrice);

        if (primePool.token0() != _callAsset && primePool.token1() != _callAsset) revert InvalidPool();
        if (primePool.token0() != _putAsset && primePool.token1() != _putAsset) {
            revert InvalidPool();
        }

        callAssetDecimals = ERC20(_callAsset).decimals();
        putAssetDecimals = ERC20(_putAsset).decimals();

        emit LogOptionsMarketInitialized(_primePool, _optionPricing, _dpFee, _callAsset, _putAsset);
    }

    /// @notice Returns the name of the contract
    /// @return string The name of the contract
    function name() public view override returns (string memory) {
        return "MarginZero Option Market OTM FE";
    }

    /// @notice Returns the symbol of the contract
    /// @return string The symbol of the contract
    function symbol() public view override returns (string memory) {
        return "MZ-OM-OTM-FE";
    }

    /// @notice Returns the token URI for a given token ID
    /// @param id The token ID
    /// @return string The token URI
    function tokenURI(uint256 id) public view override returns (string memory) {
        return ITokenURIFetcher(tokenURIFetcher).onFetchTokenURIData(id);
    }

    /// @notice Mints a new option
    /// @param _params The option parameters
    function mintOption(OptionParams calldata _params) external nonReentrant {
        optionIds += 1;

        if (_params.optionTicks.length > 20) {
            revert MaxOptionBuyReached();
        }

        if (!approvedTTLs[_params.ttl]) {
            revert NotApprovedTTL();
        }

        if (_params.tickUpper > maxUpperTick || _params.tickLower < minLowerTick) {
            revert NotValidStrikeTick();
        }

        uint256 expiry = block.timestamp + (_params.ttl - ((block.timestamp - ttlStartTime[_params.ttl]) % _params.ttl));

        if (expiry - block.timestamp > _params.ttl - BUFFER_TIME) {
            revert InBUFFER_TIME();
        }

        if (!approvedMinters[msg.sender]) {
            revert NotApprovedMinter();
        }

        uint256[] memory amountsPerOptionTicks = new uint256[](_params.optionTicks.length);
        uint256 totalAssetWithdrawn;

        bool isAmount0;

        address assetToUse = _params.isCall ? callAsset : putAsset;

        OptionTicks memory opTick;

        for (uint256 i; i < _params.optionTicks.length; i++) {
            opTick = _params.optionTicks[i];

            if ((_params.tickUpper != opTick.tickUpper || _params.tickLower != opTick.tickLower)) {
                revert NotValidStrikeTick();
            }

            if (opTick.tickUpper > 0 && opTick.tickLower > 0 || opTick.tickUpper < 0 && opTick.tickLower < 0) {
                if (uint24(opTick.tickUpper - opTick.tickLower) > maxTickDiff) {
                    revert NotValidStrikeTick();
                }
            } else {
                if (uint24(opTick.tickUpper + opTick.tickLower) > maxTickDiff) {
                    revert NotValidStrikeTick();
                }
            }

            if (
                (
                    opTick.tickLower < TickMath.getTickAtSqrtRatio(_getCurrentSqrtPriceX96(opTick.pool))
                        && opTick.tickUpper > TickMath.getTickAtSqrtRatio(_getCurrentSqrtPriceX96(opTick.pool))
                )
                    || (
                        TickMath.getSqrtRatioAtTick(opTick.tickLower) < _getCurrentSqrtPriceX96(opTick.pool)
                            && TickMath.getSqrtRatioAtTick(opTick.tickUpper) > _getCurrentSqrtPriceX96(opTick.pool)
                    )
            ) {
                revert NotValidStrikeTick();
            }

            opTickMap[optionIds].push(
                OptionTicks({
                    _handler: opTick._handler,
                    pool: opTick.pool,
                    hook: opTick.hook,
                    tickLower: opTick.tickLower,
                    tickUpper: opTick.tickUpper,
                    liquidityToUse: opTick.liquidityToUse
                })
            );

            if (!approvedPools[address(opTick.pool)]) {
                revert PoolNotApproved();
            }

            if (!approvedHooks[opTick.hook]) {
                revert NotApprovedHook();
            }

            if (opTick.liquidityToUse < minLiquidityToUse) {
                revert MinLiquidityToUse();
            }

            bytes memory usePositionData = abi.encode(
                opTick.pool,
                opTick.hook,
                opTick.tickLower,
                opTick.tickUpper,
                opTick.liquidityToUse,
                abi.encode(
                    address(this),
                    expiry,
                    _params.isCall,
                    opTick.pool,
                    opTick.tickLower,
                    opTick.tickUpper,
                    opTick.liquidityToUse
                )
            );

            (address[] memory tokens, uint256[] memory amounts,) =
                positionManager.usePosition(opTick._handler, usePositionData);

            if (tokens[0] == assetToUse) {
                require(amounts[0] > 0 && amounts[1] == 0);
                amountsPerOptionTicks[i] = (amounts[0]);
                totalAssetWithdrawn += amounts[0];
                isAmount0 = true;
            } else {
                require(amounts[1] > 0 && amounts[0] == 0);
                amountsPerOptionTicks[i] = (amounts[1]);
                totalAssetWithdrawn += amounts[1];
                isAmount0 = false;
            }
        }

        uint256 strike = getPricePerCallAssetViaTick(primePool, _params.isCall ? _params.tickUpper : _params.tickLower);

        uint256 premiumAmount = _getPremiumAmount(
            opTick.hook,
            _params.isCall ? false : true, // isPut
            expiry, // expiry
            _params.ttl, // ttl
            strike, // Strike
            verifiedSpotPrice.getSpotPrice(primePool, callAsset, callAssetDecimals), // Current price
            _params.isCall ? totalAssetWithdrawn : (totalAssetWithdrawn * (10 ** putAssetDecimals)) / strike
        );

        if (premiumAmount == 0) revert IVNotSet();

        uint256 protocolFees;
        if (feeTo != address(0)) {
            protocolFees = getFee(totalAssetWithdrawn, premiumAmount);
            ERC20(assetToUse).safeTransferFrom(msg.sender, feeTo, protocolFees);
        }

        if (premiumAmount + protocolFees > _params.maxCostAllowance) {
            revert MaxCostAllowanceExceeded();
        }

        ERC20(assetToUse).safeTransferFrom(msg.sender, address(this), premiumAmount);
        ERC20(assetToUse).safeIncreaseAllowance(address(positionManager), premiumAmount);

        for (uint256 i; i < _params.optionTicks.length; i++) {
            opTick = _params.optionTicks[i];
            uint256 premiumAmountEarned = (amountsPerOptionTicks[i] * premiumAmount) / totalAssetWithdrawn;

            bytes memory donatePositionData = abi.encode(
                opTick.pool,
                opTick.hook,
                opTick.tickLower,
                opTick.tickUpper,
                isAmount0 ? premiumAmountEarned : 0,
                isAmount0 ? 0 : premiumAmountEarned,
                abi.encode("")
            );
            positionManager.donateToPosition(opTick._handler, donatePositionData);
        }

        opData[optionIds] = OptionData({
            opTickArrayLen: _params.optionTicks.length,
            tickLower: _params.tickLower,
            tickUpper: _params.tickUpper,
            expiry: expiry,
            isCall: _params.isCall
        });

        _safeMint(msg.sender, optionIds);

        emit LogMintOption(_params, optionIds, premiumAmount, totalAssetWithdrawn, protocolFees);
    }

    /// @notice Struct to cache asset-related data during option settlement
    struct AssetsCache {
        uint256 totalProfit;
        uint256 totalAssetRelocked;
        ERC20 assetToUse;
        ERC20 assetToGet;
        bool isSettle;
    }

    /// @notice Settles an option
    /// @param _params The settlement parameters
    /// @return ac The assets cache containing settlement results
    function settleOption(SettleOptionParams calldata _params) external nonReentrant returns (AssetsCache memory ac) {
        OptionData memory oData = opData[_params.optionId];

        if (oData.opTickArrayLen != _params.liquidityToSettle.length) {
            revert ArrayLenMismatch();
        }

        if (!settlers[msg.sender]) {
            revert NotApprovedSettler();
        }

        if (block.timestamp >= oData.expiry) {
            ac.isSettle = true;
        }

        bool isAmount0 = oData.isCall ? primePool.token0() == callAsset : primePool.token0() == putAsset;

        ac.assetToUse = ERC20(oData.isCall ? callAsset : putAsset);
        ac.assetToGet = ERC20(oData.isCall ? putAsset : callAsset);

        for (uint256 i; i < oData.opTickArrayLen; i++) {
            if (_params.liquidityToSettle[i] == 0) continue;

            OptionTicks storage opTick = opTickMap[_params.optionId][i];

            uint256 liquidityToSettle = _params.liquidityToSettle[i];

            (uint256 amount0, uint256 amount1) = LiquidityAmounts.getAmountsForLiquidity(
                _getCurrentSqrtPriceX96(opTick.pool),
                opTick.tickLower.getSqrtRatioAtTick(),
                opTick.tickUpper.getSqrtRatioAtTick(),
                uint128(liquidityToSettle)
            );

            if (
                ((amount0 > 0 && amount1 == 0) || (amount1 > 0 && amount0 == 0))
                    && !(
                        (
                            opTick.tickLower < TickMath.getTickAtSqrtRatio(_getCurrentSqrtPriceX96(opTick.pool))
                                && opTick.tickUpper > TickMath.getTickAtSqrtRatio(_getCurrentSqrtPriceX96(opTick.pool))
                        )
                            || (
                                TickMath.getSqrtRatioAtTick(opTick.tickLower) < _getCurrentSqrtPriceX96(opTick.pool)
                                    && TickMath.getSqrtRatioAtTick(opTick.tickUpper) > _getCurrentSqrtPriceX96(opTick.pool)
                            )
                    )
            ) {
                if (isAmount0 && amount0 > 0 && ac.isSettle == true) {
                    ac.assetToUse.safeIncreaseAllowance(address(positionManager), amount0);
                    ac.totalAssetRelocked += amount0;
                } else if (!isAmount0 && amount1 > 0 && ac.isSettle == true) {
                    ac.assetToUse.safeIncreaseAllowance(address(positionManager), amount1);
                    ac.totalAssetRelocked += amount1;
                } else {
                    uint256 amountToSwap = isAmount0
                        ? LiquidityAmounts.getAmount0ForLiquidity(
                            opTick.tickLower.getSqrtRatioAtTick(),
                            opTick.tickUpper.getSqrtRatioAtTick(),
                            uint128(liquidityToSettle)
                        )
                        : LiquidityAmounts.getAmount1ForLiquidity(
                            opTick.tickLower.getSqrtRatioAtTick(),
                            opTick.tickUpper.getSqrtRatioAtTick(),
                            uint128(liquidityToSettle)
                        );

                    ac.totalAssetRelocked += amountToSwap;

                    uint256 prevBalance = ac.assetToGet.balanceOf(address(this));

                    if (!approvedSwapper[address(_params.swapper[i])]) {
                        revert NotApprovedSwapper();
                    }

                    ac.assetToUse.transfer(address(_params.swapper[i]), amountToSwap);

                    _params.swapper[i].onSwapReceived(
                        address(ac.assetToUse), address(ac.assetToGet), amountToSwap, _params.swapData[i]
                    );

                    uint256 amountReq = isAmount0
                        ? LiquidityAmounts.getAmount1ForLiquidity(
                            opTick.tickLower.getSqrtRatioAtTick(),
                            opTick.tickUpper.getSqrtRatioAtTick(),
                            uint128(liquidityToSettle)
                        )
                        : LiquidityAmounts.getAmount0ForLiquidity(
                            opTick.tickLower.getSqrtRatioAtTick(),
                            opTick.tickUpper.getSqrtRatioAtTick(),
                            uint128(liquidityToSettle)
                        );

                    uint256 currentBalance = ac.assetToGet.balanceOf(address(this));

                    if (currentBalance < prevBalance + amountReq) {
                        revert NotEnoughAfterSwap();
                    }

                    ac.assetToGet.safeIncreaseAllowance(address(positionManager), amountReq);

                    ac.totalProfit += currentBalance - (prevBalance + amountReq);
                }
            } else {
                if (isAmount0 && ac.isSettle == true) {
                    ac.assetToUse.safeIncreaseAllowance(address(positionManager), amount0);
                    ac.assetToGet.safeIncreaseAllowance(address(positionManager), amount1);

                    uint256 actualAmount0 = LiquidityAmounts.getAmount0ForLiquidity(
                        opTick.tickLower.getSqrtRatioAtTick(),
                        opTick.tickUpper.getSqrtRatioAtTick(),
                        uint128(liquidityToSettle)
                    );

                    ac.assetToGet.safeTransferFrom(msg.sender, address(this), amount1);

                    ac.assetToUse.safeTransfer(msg.sender, actualAmount0 - amount0);
                } else if (!isAmount0 && ac.isSettle == true) {
                    ac.assetToUse.safeIncreaseAllowance(address(positionManager), amount1);
                    ac.assetToGet.safeIncreaseAllowance(address(positionManager), amount0);

                    uint256 actualAmount1 = LiquidityAmounts.getAmount1ForLiquidity(
                        opTick.tickLower.getSqrtRatioAtTick(),
                        opTick.tickUpper.getSqrtRatioAtTick(),
                        uint128(liquidityToSettle)
                    );

                    ac.assetToGet.safeTransferFrom(msg.sender, address(this), amount0);

                    ac.assetToUse.safeTransfer(msg.sender, actualAmount1 - amount1);
                }
            }

            bytes memory unusePositionData = abi.encode(
                opTick.pool, opTick.hook, opTick.tickLower, opTick.tickUpper, liquidityToSettle, abi.encode("")
            );

            positionManager.unusePosition(opTick._handler, unusePositionData);

            opTick.liquidityToUse -= liquidityToSettle;
        }

        if (ac.totalProfit > 0) {
            ac.assetToGet.transfer(msg.sender, ac.totalProfit);
        }

        emit LogSettleOption(ac, _params.liquidityToSettle, ownerOf(_params.optionId), _params.optionId);
    }

    /// @notice Splits a position into a new option
    /// @param _params The position splitter parameters
    function positionSplitter(PositionSplitterParams calldata _params) external nonReentrant {
        optionIds += 1;

        if (ownerOf(_params.optionId) != msg.sender) {
            revert NotOwnerOrDelegator();
        }
        OptionData memory oData = opData[_params.optionId];

        if (oData.opTickArrayLen != _params.liquidityToSplit.length) {
            revert ArrayLenMismatch();
        }

        if (oData.expiry <= block.timestamp) {
            revert Expired();
        }

        for (uint256 i; i < _params.liquidityToSplit.length; i++) {
            OptionTicks storage opTick = opTickMap[_params.optionId][i];
            opTick.liquidityToUse -= _params.liquidityToSplit[i];

            opTickMap[optionIds].push(
                OptionTicks({
                    _handler: opTick._handler,
                    pool: opTick.pool,
                    hook: opTick.hook,
                    tickLower: opTick.tickLower,
                    tickUpper: opTick.tickUpper,
                    liquidityToUse: _params.liquidityToSplit[i]
                })
            );
        }

        opData[optionIds] = OptionData({
            opTickArrayLen: _params.liquidityToSplit.length,
            tickLower: oData.tickLower,
            tickUpper: oData.tickUpper,
            expiry: oData.expiry,
            isCall: oData.isCall
        });

        _safeMint(_params.to, optionIds);

        emit LogSplitOption(_params, optionIds, ownerOf(_params.optionId));
    }

    /// @notice Gets the price per call asset via a specific tick
    /// @param _pool The Uniswap V3 pool
    /// @param _tick The tick to get the price for
    /// @return uint256 The price per call asset
    function getPricePerCallAssetViaTick(IUniswapV3Pool _pool, int24 _tick) public view returns (uint256) {
        uint160 sqrtPriceX96 = TickMath.getSqrtRatioAtTick(_tick);
        return _getPrice(_pool, sqrtPriceX96);
    }

    /// @notice Gets the premium amount for an option
    /// @param hook The hook address
    /// @param isPut Whether the option is a put
    /// @param expiry The expiry timestamp
    /// @param strike The strike price
    /// @param lastPrice The last price
    /// @param amount The option amount
    /// @return uint256 The premium amount
    function getPremiumAmount(
        address hook,
        bool isPut,
        uint256 expiry,
        uint256 ttl,
        uint256 strike,
        uint256 lastPrice,
        uint256 amount
    ) external view returns (uint256) {
        return _getPremiumAmount(hook, isPut, expiry, ttl, strike, lastPrice, amount);
    }

    /// @notice Gets the current sqrt price X96
    /// @param pool The Uniswap V3 pool
    /// @return sqrtPriceX96 The current sqrt price X96
    function _getCurrentSqrtPriceX96(IUniswapV3Pool pool) internal view returns (uint160 sqrtPriceX96) {
        (, bytes memory result) = address(pool).staticcall(abi.encodeWithSignature("slot0()"));
        sqrtPriceX96 = abi.decode(result, (uint160));
    }

    /// @notice Internal function to get the premium amount
    /// @param hook The hook address
    /// @param isPut Whether the option is a put
    /// @param expiry The expiry timestamp
    /// @param strike The strike price
    /// @param lastPrice The last price
    /// @param amount The option amount
    /// @return premiumAmount The premium amount
    function _getPremiumAmount(
        address hook,
        bool isPut,
        uint256 expiry,
        uint256 ttl,
        uint256 strike,
        uint256 lastPrice,
        uint256 amount
    ) internal view returns (uint256 premiumAmount) {
        uint256 premiumInQuote = (amount * optionPricing.getOptionPrice(hook, isPut, expiry, ttl, strike, lastPrice))
            / (isPut ? 10 ** putAssetDecimals : 10 ** callAssetDecimals);

        if (isPut) {
            return premiumInQuote;
        }
        return (premiumInQuote * (10 ** callAssetDecimals)) / lastPrice;
    }

    /// @notice Internal function to get the price
    /// @param _pool The Uniswap V3 pool
    /// @param sqrtPriceX96 The sqrt price X96
    /// @return price The calculated price
    function _getPrice(IUniswapV3Pool _pool, uint160 sqrtPriceX96) internal view returns (uint256 price) {
        if (sqrtPriceX96 <= type(uint128).max) {
            uint256 priceX192 = uint256(sqrtPriceX96) * sqrtPriceX96;
            price = callAsset == _pool.token0()
                ? FullMath.mulDiv(priceX192, 10 ** callAssetDecimals, 1 << 192)
                : FullMath.mulDiv(1 << 192, 10 ** callAssetDecimals, priceX192);
        } else {
            uint256 priceX128 = FullMath.mulDiv(sqrtPriceX96, sqrtPriceX96, 1 << 64);

            price = callAsset == _pool.token0()
                ? FullMath.mulDiv(priceX128, 10 ** callAssetDecimals, 1 << 128)
                : FullMath.mulDiv(1 << 128, 10 ** callAssetDecimals, priceX128);
        }
    }

    /// @notice Gets the fee for a given amount and premium
    /// @param amount The option amount
    /// @param premium The option premium
    /// @return uint256 The calculated fee
    function getFee(uint256 amount, uint256 premium) public view returns (uint256) {
        return dpFee.onFeeReqReceive(address(this), amount, premium);
    }

    /// @notice Updates pool approvals and settings
    /// @param _settler The settler address
    /// @param _statusSettler The settler status
    /// @param _pool The pool address
    /// @param _statusPools The pool status
    /// @param _ttl The time-to-live
    /// @param _ttlStartTime The start time for the TTL
    /// @param ttlStatus The TTL status
    /// @param _BUFFER_TIME The buffer time
    function updatePoolApporvals(
        address _settler,
        bool _statusSettler,
        address _pool,
        bool _statusPools,
        uint256 _ttl,
        uint256 _ttlStartTime,
        bool ttlStatus,
        uint256 _BUFFER_TIME
    ) external onlyOwner {
        settlers[_settler] = _statusSettler;
        approvedPools[_pool] = _statusPools;
        approvedTTLs[_ttl] = ttlStatus;
        BUFFER_TIME = _BUFFER_TIME;

        if (_ttlStartTime == 0) revert TTLNotSet();

        ttlStartTime[_ttl] = _ttlStartTime;

        IUniswapV3Pool pool = IUniswapV3Pool(_pool);

        if (pool.token0() != callAsset && pool.token1() != callAsset) {
            revert InvalidPool();
        }

        if (pool.token0() != putAsset && pool.token1() != putAsset) {
            revert InvalidPool();
        }

        emit LogUpdatePoolApprovals(
            _settler, _statusSettler, _pool, _statusPools, _ttl, _ttlStartTime, ttlStatus, _BUFFER_TIME
        );
    }

    /// @notice Updates pool settings
    /// @param _feeTo The fee recipient address
    /// @param _tokenURIFetcher The token URI fetcher address
    /// @param _dpFee The fee strategy address
    /// @param _optionPricing The option pricing address
    /// @param _verifiedSpotPrice The verified spot price address
    /// @param _maxTickDiff The maximum tick difference
    function updatePoolSettings(
        address _feeTo,
        address _tokenURIFetcher,
        address _dpFee,
        address _optionPricing,
        address _verifiedSpotPrice,
        uint24 _maxTickDiff,
        int24 _maxUpperTick,
        int24 _minLowerTick,
        uint128 _minLiquidityToUse
    ) external onlyOwner {
        feeTo = _feeTo;
        tokenURIFetcher = _tokenURIFetcher;
        dpFee = IClammFeeStrategyV2(_dpFee);
        optionPricing = IOptionPricingV2(_optionPricing);
        verifiedSpotPrice = IVerifiedSpotPrice(_verifiedSpotPrice);
        maxTickDiff = _maxTickDiff;
        maxUpperTick = _maxUpperTick;
        minLowerTick = _minLowerTick;
        minLiquidityToUse = _minLiquidityToUse;
        emit LogUpdatePoolSettings(_feeTo, _tokenURIFetcher, _dpFee, _optionPricing);
    }

    function setApprovedSwapperAndHook(address swapper, bool statusSwapper, address hook, bool statusHook)
        external
        onlyOwner
    {
        approvedSwapper[swapper] = statusSwapper;
        approvedHooks[hook] = statusHook;
        emit LogUpdateApprovedSwapper(swapper, statusSwapper);
        emit LogUpdateApprovedHook(hook, statusHook);
    }

    function setApprovedMinter(address minter, bool statusMinter) external onlyOwner {
        approvedMinters[minter] = statusMinter;
        emit LogUpdateApprovedMinter(minter, statusMinter);
    }

    /// @notice Emergency withdraw function
    /// @param token The token address to withdraw
    function emergencyWithdraw(address token) external onlyOwner {
        ERC20(token).safeTransfer(msg.sender, ERC20(token).balanceOf(address(this)));
    }
}
