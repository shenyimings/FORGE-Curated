// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.0 <0.9.0;

import {IHandler} from "../interfaces/IHandler.sol";
import {IHook} from "../interfaces/IHook.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IV3Pool} from "../interfaces/handlers/V3/IV3Pool.sol";

import {ERC6909} from "../libraries/tokens/ERC6909.sol";
import {Math} from "openzeppelin-contracts/contracts/utils/math/Math.sol";
import {SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {LiquidityAmounts} from "v3-periphery/libraries/LiquidityAmounts.sol";
import {TickMath} from "v3-core/libraries/TickMath.sol";
import {FullMath} from "v3-core/libraries/FullMath.sol";
import {FixedPoint128} from "v3-core/libraries/FixedPoint128.sol";

import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";

/// @title V3BaseHandler
/// @author 0xcarrot
/// @notice Abstract contract for handling Uniswap V3 liquidity positions
/// @dev Implements IHandler interface and inherits from ERC6909 and Ownable
abstract contract V3BaseHandler is IHandler, ERC6909, Ownable {
    using Math for uint128;
    using TickMath for int24;
    using SafeERC20 for IERC20;

    /// @notice Struct to store information about a token ID
    struct TokenIdInfo {
        uint128 totalLiquidity;
        uint128 liquidityUsed;
        uint256 feeGrowthInside0LastX128;
        uint256 feeGrowthInside1LastX128;
        uint128 tokensOwed0;
        uint128 tokensOwed1;
        address token0;
        address token1;
        uint24 fee;
        uint128 reservedLiquidity;
    }

    /// @notice Struct for minting a new position
    struct MintPositionParams {
        IV3Pool pool;
        address hook;
        int24 tickLower;
        int24 tickUpper;
        uint128 liquidity;
    }

    /// @notice Struct for burning an existing position
    struct BurnPositionParams {
        IV3Pool pool;
        address hook;
        int24 tickLower;
        int24 tickUpper;
        uint128 liquidity;
    }

    /// @notice Struct for reserving liquidity
    struct ReserveOperation {
        IV3Pool pool;
        address hook;
        int24 tickLower;
        int24 tickUpper;
        uint128 liquidity;
        bool isReserve;
    }

    /// @notice Struct for using a position
    struct UsePositionParams {
        IV3Pool pool;
        address hook;
        int24 tickLower;
        int24 tickUpper;
        uint128 liquidityToUse;
    }

    /// @notice Struct for un-using a position
    struct UnusePositionParams {
        IV3Pool pool;
        address hook;
        int24 tickLower;
        int24 tickUpper;
        uint128 liquidityToUnuse;
    }

    /// @notice Struct for donating to a position
    struct DonateParams {
        IV3Pool pool;
        address hook;
        int24 tickLower;
        int24 tickUpper;
        uint128 amount0;
        uint128 amount1;
    }

    /// @notice Enum for wildcard actions
    enum WildcardActions {
        RESERVE_LIQUIDITY,
        COLLECT_FEES
    }

    /// @notice Struct for reserved liquidity information
    struct ReserveLiquidityInfo {
        uint128 liquidity;
        uint64 lastReserve;
    }

    /// @notice Mapping of token IDs to their information
    mapping(uint256 => TokenIdInfo) public tokenIds;
    /// @notice Mapping of whitelisted applications
    mapping(address => bool) public whitelistedApps;
    /// @notice Mapping of reserved liquidity per user for each token ID
    mapping(uint256 => mapping(address => ReserveLiquidityInfo)) public reservedLiquidityPerUser;

    /// @notice Mapping of reserve cooldown per hook
    mapping(address => uint64) public reserveCooldownHook;

    /// @notice Mapping of registered hooks
    mapping(address => bool) public hookRegistered;

    /// @notice Mapping of hook permissions
    mapping(address => HookPermInfo) public hookPerms;

    /// @notice Address of the fee receiver
    address public feeReceiver;

    /// @notice Pause state of the contract
    bool pause;

    error NotWhitelisted();
    error InsufficientLiquidity();
    error BeforeReserveCooldown();
    error InvalidTicks();
    error HookNotRegistered();
    error Paused();
    error HookAlreadyRegistered();

    event LogMintPositionHandler(MintPositionParams params, address context, uint256 amount0, uint256 amount1);
    event LogBurnPositionHandler(BurnPositionParams params, address context, uint256 amount0, uint256 amount1);
    event LogUsePositionHandler(UsePositionParams params, address context, uint256 amount0, uint256 amount1);
    event LogUnusePositionHandler(UnusePositionParams params, address context, uint256 amount0, uint256 amount1);
    event LogDonateToPosition(DonateParams params, address context);
    event LogReservedLiquidity(ReserveOperation params, address context, uint256 lastReserve);
    event LogWithdrawReserveLiquidity(ReserveOperation params, address context, uint256 amount0, uint256 amount1);
    event LogCollectedFees(
        IV3Pool pool, address hook, int24 tickLower, int24 tickUpper, uint256 tokensOwed0, uint256 tokensOwed1
    );

    /// @notice Constructor for V3BaseHandler
    /// @param _feeReceiver Address to receive fees
    constructor(address _feeReceiver) Ownable(msg.sender) {
        feeReceiver = _feeReceiver;
    }

    /// @notice Checks if the caller is whitelisted
    function onlyWhitelisted() private view {
        if (!whitelistedApps[msg.sender]) revert NotWhitelisted();
        if (pause) revert Paused();
    }

    /// @notice Registers a new hook
    /// @param _hook Address of the hook to register
    /// @param _info Permission information for the hook
    function registerHook(address _hook, IHandler.HookPermInfo memory _info) external onlyOwner {
        if (hookRegistered[_hook]) {
            revert HookAlreadyRegistered();
        }

        hookPerms[_hook] = _info;
        hookRegistered[_hook] = true;
    }

    struct MintLiquidityInternalCache {
        bool self;
        uint256 tokenId;
        IV3Pool pool;
        address hook;
        uint128 liquidity;
        uint256 amount0;
        uint256 amount1;
        int24 tickLower;
        int24 tickUpper;
        address context;
    }

    /// @notice Mints a new position in the Uniswap V3 pool
    /// @param context The address context for minting
    /// @param _mintPositionData Encoded data for minting position
    /// @return sharesMinted The amount of shares minted
    function mintPositionHandler(address context, bytes calldata _mintPositionData) external returns (uint256) {
        onlyWhitelisted();

        (MintPositionParams memory _params, bytes memory hookData) =
            abi.decode(_mintPositionData, (MintPositionParams, bytes));

        if (hookPerms[_params.hook].onMint && hookRegistered[_params.hook]) {
            IHook(_params.hook).onMintBefore(hookData);
        }

        (uint128 liquidity,,) = mintInternal(
            MintLiquidityInternalCache({
                self: false,
                tokenId: uint256(
                    keccak256(abi.encode(address(this), _params.pool, _params.hook, _params.tickLower, _params.tickUpper))
                ),
                pool: _params.pool,
                hook: _params.hook,
                liquidity: _params.liquidity,
                amount0: 0,
                amount1: 0,
                tickLower: _params.tickLower,
                tickUpper: _params.tickUpper,
                context: context
            })
        );

        return liquidity;
    }

    function mintInternal(MintLiquidityInternalCache memory cache) private returns (uint128, uint256, uint256) {
        TokenIdInfo storage tki = tokenIds[cache.tokenId];

        if (tki.token0 == address(0)) {
            tki.token0 = cache.pool.token0();
            tki.token1 = cache.pool.token1();
            tki.fee = cache.pool.fee();
        }

        (uint160 sqrtPriceX96,) = _getCurrentSqrtPriceX96(cache.pool);

        if (cache.liquidity == 0) {
            cache.liquidity = LiquidityAmounts.getLiquidityForAmounts(
                sqrtPriceX96,
                cache.tickLower.getSqrtRatioAtTick(),
                cache.tickUpper.getSqrtRatioAtTick(),
                cache.amount0,
                cache.amount1
            );
        }

        if (cache.amount0 == 0 && cache.amount1 == 0) {
            (cache.amount0, cache.amount1) = LiquidityAmounts.getAmountsForLiquidity(
                sqrtPriceX96,
                cache.tickLower.getSqrtRatioAtTick(),
                cache.tickUpper.getSqrtRatioAtTick(),
                cache.liquidity
            );
        }

        (cache.liquidity, cache.amount0, cache.amount1) =
            _addLiquidity(cache.self, tki, cache.tickLower, cache.tickUpper, cache.amount0, cache.amount1);

        _feeCalculation(tki, cache.pool, cache.tickLower, cache.tickUpper);

        tki.totalLiquidity += cache.liquidity;

        _mint(cache.context, cache.tokenId, cache.liquidity);

        emit LogMintPositionHandler(
            MintPositionParams(cache.pool, cache.hook, cache.tickLower, cache.tickUpper, cache.liquidity),
            cache.context,
            cache.amount0,
            cache.amount1
        );

        return (cache.liquidity, cache.amount0, cache.amount1);
    }

    struct BurnLiquidityInternalCache {
        uint256 tokenId;
        IV3Pool pool;
        address hook;
        int24 tickLower;
        int24 tickUpper;
        uint128 liquidity;
        address context;
        address receiver;
    }

    /// @notice Burns an existing position in the Uniswap V3 pool
    /// @param context The address context for burning
    /// @param _burnPositionData Encoded data for burning position
    /// @return The amount of liquidity burned
    function burnPositionHandler(address context, bytes calldata _burnPositionData) external returns (uint256) {
        onlyWhitelisted();

        (BurnPositionParams memory _params, bytes memory hookData) =
            abi.decode(_burnPositionData, (BurnPositionParams, bytes));

        if (hookPerms[_params.hook].onBurn && hookRegistered[_params.hook]) {
            IHook(_params.hook).onBurnBefore(hookData);
        }

        burnInternal(
            BurnLiquidityInternalCache({
                tokenId: uint256(
                    keccak256(abi.encode(address(this), _params.pool, _params.hook, _params.tickLower, _params.tickUpper))
                ),
                pool: _params.pool,
                hook: _params.hook,
                tickLower: _params.tickLower,
                tickUpper: _params.tickUpper,
                liquidity: _params.liquidity,
                context: context,
                receiver: context
            })
        );

        return _params.liquidity;
    }

    function burnInternal(BurnLiquidityInternalCache memory cache) private returns (uint256, uint256) {
        TokenIdInfo storage tki = tokenIds[cache.tokenId];

        if ((tki.totalLiquidity - tki.liquidityUsed) < cache.liquidity) {
            revert InsufficientLiquidity();
        }

        (uint256 amount0, uint256 amount1) = cache.pool.burn(cache.tickLower, cache.tickUpper, cache.liquidity);

        _feeCalculation(tki, cache.pool, cache.tickLower, cache.tickUpper);

        cache.pool.collect(cache.receiver, cache.tickLower, cache.tickUpper, uint128(amount0), uint128(amount1));

        tki.totalLiquidity -= cache.liquidity;

        _burn(cache.context, cache.tokenId, cache.liquidity);

        emit LogBurnPositionHandler(
            BurnPositionParams(cache.pool, cache.hook, cache.tickLower, cache.tickUpper, cache.liquidity),
            cache.context,
            amount0,
            amount1
        );

        return (amount0, amount1);
    }

    /// @notice Uses a portion of liquidity from an existing position
    /// @param _usePositionData Encoded data for using position
    /// @return An array of token addresses, an array of amounts, and the liquidity used
    function usePositionHandler(bytes calldata _usePositionData)
        external
        returns (address[] memory, uint256[] memory, uint256)
    {
        onlyWhitelisted();

        (UsePositionParams memory _params, bytes memory hookData) =
            abi.decode(_usePositionData, (UsePositionParams, bytes));

        uint256 tokenId = uint256(
            keccak256(abi.encode(address(this), _params.pool, _params.hook, _params.tickLower, _params.tickUpper))
        );

        TokenIdInfo storage tki = tokenIds[tokenId];

        if (hookPerms[_params.hook].onUse && hookRegistered[_params.hook]) {
            IHook(_params.hook).onPositionUseBefore(hookData);
        }

        if ((tki.totalLiquidity - tki.liquidityUsed) < _params.liquidityToUse) {
            revert InsufficientLiquidity();
        }

        (uint256 amount0, uint256 amount1) =
            _removeLiquidity(_params.pool, _params.tickLower, _params.tickUpper, _params.liquidityToUse);

        _params.pool.collect(msg.sender, _params.tickLower, _params.tickUpper, uint128(amount0), uint128(amount1));

        _feeCalculation(tki, _params.pool, _params.tickLower, _params.tickUpper);

        tki.liquidityUsed += _params.liquidityToUse;

        address[] memory tokens = new address[](2);
        tokens[0] = tki.token0;
        tokens[1] = tki.token1;

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = amount0;
        amounts[1] = amount1;

        emit LogUsePositionHandler(_params, msg.sender, amount0, amount1);

        return (tokens, amounts, _params.liquidityToUse);
    }

    /// @notice Returns previously used liquidity to a position
    /// @param _unusePositionData Encoded data for un-using position
    /// @return An array of amounts and the liquidity returned
    function unusePositionHandler(bytes calldata _unusePositionData) external returns (uint256[] memory, uint256) {
        onlyWhitelisted();

        (UnusePositionParams memory _params, bytes memory hookData) =
            abi.decode(_unusePositionData, (UnusePositionParams, bytes));

        uint256 tokenId = uint256(
            keccak256(abi.encode(address(this), _params.pool, _params.hook, _params.tickLower, _params.tickUpper))
        );

        TokenIdInfo storage tki = tokenIds[tokenId];

        if (hookPerms[_params.hook].onUnuse && hookRegistered[_params.hook]) {
            IHook(_params.hook).onPositionUnUseBefore(hookData);
        }

        (uint160 sqrtPriceX96,) = _getCurrentSqrtPriceX96(_params.pool);

        (uint256 amount0, uint256 amount1) = LiquidityAmounts.getAmountsForLiquidity(
            sqrtPriceX96,
            _params.tickLower.getSqrtRatioAtTick(),
            _params.tickUpper.getSqrtRatioAtTick(),
            uint128(_params.liquidityToUnuse)
        );

        (uint128 liquidity,,) = _addLiquidity(false, tki, _params.tickLower, _params.tickUpper, amount0, amount1);

        _feeCalculation(tki, _params.pool, _params.tickLower, _params.tickUpper);

        if (tki.liquidityUsed >= liquidity) {
            tki.liquidityUsed -= liquidity;
        } else {
            tki.totalLiquidity += (liquidity - tki.liquidityUsed);
            tki.liquidityUsed = 0;
        }

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = amount0;
        amounts[1] = amount1;

        _params.liquidityToUnuse = liquidity;

        emit LogUnusePositionHandler(_params, msg.sender, amount0, amount1);

        return (amounts, uint256(liquidity));
    }

    /// @notice Allows donation of tokens to a specific position
    /// @param _donateData Encoded data for donation
    /// @return An array of amounts and a placeholder value
    function donateToPosition(bytes calldata _donateData) external returns (uint256[] memory, uint256) {
        onlyWhitelisted();

        (DonateParams memory _params, bytes memory hookData) = abi.decode(_donateData, (DonateParams, bytes));

        uint256 tokenId = uint256(
            keccak256(abi.encode(address(this), _params.pool, _params.hook, _params.tickLower, _params.tickUpper))
        );

        if (hookPerms[_params.hook].onDonate && hookRegistered[_params.hook]) {
            IHook(_params.hook).onDonationBefore(hookData);
        }

        TokenIdInfo memory tki = tokenIds[tokenId];

        if (_params.amount0 > 0) {
            IERC20(tki.token0).safeTransferFrom(msg.sender, feeReceiver, _params.amount0);
        }

        if (_params.amount1 > 0) {
            IERC20(tki.token1).safeTransferFrom(msg.sender, feeReceiver, _params.amount1);
        }

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = _params.amount0;
        amounts[1] = _params.amount1;

        emit LogDonateToPosition(_params, msg.sender);

        return (amounts, 0);
    }

    /// @notice Handles various wildcard actions
    /// @param context The address context for the action
    /// @param _wildcardData Encoded data for the wildcard action
    /// @return Encoded result of the wildcard action
    function wildcardHandler(address context, bytes calldata _wildcardData) external returns (bytes memory) {
        onlyWhitelisted();

        (WildcardActions wca, bytes memory _data) = abi.decode(_wildcardData, (WildcardActions, bytes));

        if (wca == WildcardActions.RESERVE_LIQUIDITY) {
            _reserveOps(context, _data);
        } else if (wca == WildcardActions.COLLECT_FEES) {
            _collectFees(_data);
        }
        return bytes("");
    }

    /// @notice Internal function to reserve liquidity
    /// @param context The address context for the operation
    /// @param _reserveOperation Encoded data for the reserve operation
    function _reserveOps(address context, bytes memory _reserveOperation) private {
        ReserveOperation memory _params = abi.decode(_reserveOperation, (ReserveOperation));

        uint256 tokenId = uint256(
            keccak256(abi.encode(address(this), _params.pool, _params.hook, _params.tickLower, _params.tickUpper))
        );

        TokenIdInfo storage tki = tokenIds[tokenId];

        ReserveLiquidityInfo storage rld = reservedLiquidityPerUser[tokenId][context];

        if (_params.isReserve) {
            rld.liquidity += _params.liquidity;
            rld.lastReserve = uint64(block.timestamp);

            tki.totalLiquidity -= _params.liquidity;

            tki.reservedLiquidity += _params.liquidity;

            _burn(context, tokenId, _params.liquidity);

            emit LogReservedLiquidity(_params, context, rld.lastReserve);
        } else {
            if (rld.lastReserve + reserveCooldownHook[_params.hook] > block.timestamp) revert BeforeReserveCooldown();

            if (((tki.totalLiquidity + tki.reservedLiquidity) - tki.liquidityUsed) < _params.liquidity) {
                revert InsufficientLiquidity();
            }

            (uint256 amount0, uint256 amount1) =
                _params.pool.burn(_params.tickLower, _params.tickUpper, _params.liquidity);

            _params.pool.collect(context, _params.tickLower, _params.tickUpper, uint128(amount0), uint128(amount1));

            _feeCalculation(tki, _params.pool, _params.tickLower, _params.tickUpper);

            tki.reservedLiquidity -= _params.liquidity;
            rld.liquidity -= _params.liquidity;

            emit LogWithdrawReserveLiquidity(_params, context, amount1, amount1);
        }
    }

    /// @notice Calculates the tokens required for a position
    /// @param _positionData Encoded position data
    /// @return tokens An array of token addresses
    /// @return amounts An array of token amounts
    function _tokensToPull(bytes calldata _positionData) private view returns (address[] memory, uint256[] memory) {
        (MintPositionParams memory _params,) = abi.decode(_positionData, (MintPositionParams, bytes));

        (uint160 sqrtPriceX96,) = _getCurrentSqrtPriceX96(_params.pool);

        (uint256 amount0, uint256 amount1) = LiquidityAmounts.getAmountsForLiquidity(
            sqrtPriceX96,
            _params.tickLower.getSqrtRatioAtTick(),
            _params.tickUpper.getSqrtRatioAtTick(),
            uint128(_params.liquidity)
        );

        address[] memory tokens = new address[](2);
        tokens[0] = _params.pool.token0();
        tokens[1] = _params.pool.token1();

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = amount0;
        amounts[1] = amount1;

        return (tokens, amounts);
    }

    /// @notice Calculates tokens required for un-using a position
    /// @param _unusePositionData Encoded data for un-using a position
    /// @return tokens An array of token addresses
    /// @return amounts An array of token amounts
    function tokensToPullForUnUse(bytes calldata _unusePositionData)
        external
        view
        returns (address[] memory tokens, uint256[] memory amounts)
    {
        return _tokensToPull(_unusePositionData);
    }

    /// @notice Calculates tokens required for donating to a position
    /// @param _donatePosition Encoded data for donation
    /// @return tokens An array of token addresses
    /// @return amounts An array of token amounts
    function tokensToPullForDonate(bytes calldata _donatePosition)
        external
        view
        returns (address[] memory, uint256[] memory)
    {
        (DonateParams memory _params,) = abi.decode(_donatePosition, (DonateParams, bytes));

        address[] memory tokens = new address[](2);
        tokens[0] = _params.pool.token0();
        tokens[1] = _params.pool.token1();

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = _params.amount0;
        amounts[1] = _params.amount1;

        return (tokens, amounts);
    }

    /// @notice Calculates tokens required for wildcard actions
    /// @param _data wildcard data (unused in this implementation)
    /// @return tokens An array of token addresses (empty in this implementation)
    /// @return amounts An array of token amounts (empty in this implementation)
    function tokensToPullForWildcard(bytes calldata _data) external view returns (address[] memory, uint256[] memory) {
        address[] memory tokens = new address[](2);
        uint256[] memory amounts = new uint256[](2);
        return (tokens, amounts);
    }

    /// @notice Generates a unique identifier for a handler
    /// @param _data Encoded data for generating the identifier
    /// @return handlerIdentifierId The unique identifier
    function getHandlerIdentifier(bytes calldata _data) external view returns (uint256 handlerIdentifierId) {
        (address pool, address hook, int24 tickLower, int24 tickUpper) =
            abi.decode(_data, (address, address, int24, int24));

        return uint256(keccak256(abi.encode(address(this), pool, hook, tickLower, tickUpper)));
    }

    /// @notice Calculates tokens required for minting a position
    /// @param _mintPositionData Encoded data for minting a position
    /// @return tokens An array of token addresses
    /// @return amounts An array of token amounts
    function tokensToPullForMint(bytes calldata _mintPositionData)
        external
        view
        returns (address[] memory tokens, uint256[] memory amounts)
    {
        return _tokensToPull(_mintPositionData);
    }

    /// @notice Internal function to get the current sqrt price from a pool
    /// @param pool The Uniswap V3 pool
    /// @return sqrtPriceX96 The current sqrt price
    /// @return tick The current tick
    function _getCurrentSqrtPriceX96(IV3Pool pool) internal view returns (uint160 sqrtPriceX96, int24 tick) {
        (sqrtPriceX96, tick,,,,,) = pool.slot0();
    }

    /// @notice Internal function to add liquidity to a position
    /// @param self Whether the operation is performed by the contract itself
    /// @param tki Token ID information
    /// @param tickLower The lower tick of the position
    /// @param tickUpper The upper tick of the position
    /// @param amount0 The amount of token0
    /// @param amount1 The amount of token1
    /// @return liquidity The amount of liquidity added
    /// @return amount0 The actual amount of token0 used
    /// @return amount1 The actual amount of token1 used
    function _addLiquidity(
        bool self,
        TokenIdInfo memory tki,
        int24 tickLower,
        int24 tickUpper,
        uint256 amount0,
        uint256 amount1
    ) internal virtual returns (uint128, uint256, uint256) {}

    /// @notice Internal function to remove liquidity from a position
    /// @param _pool The Uniswap V3 pool
    /// @param tickLower The lower tick of the position
    /// @param tickUpper The upper tick of the position
    /// @param liquidity The amount of liquidity to remove
    /// @return amount0 The amount of token0 received
    /// @return amount1 The amount of token1 received
    function _removeLiquidity(IV3Pool _pool, int24 tickLower, int24 tickUpper, uint128 liquidity)
        internal
        virtual
        returns (uint256, uint256)
    {}

    /// @notice Internal function to compute the position key
    /// @param owner The owner of the position
    /// @param tickLower The lower tick of the position
    /// @param tickUpper The upper tick of the position
    /// @return The position key
    function _computePositionKey(address owner, int24 tickLower, int24 tickUpper) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(owner, tickLower, tickUpper));
    }

    /// @notice Internal function to collect fees from a position
    /// @param _collectFeesData Encoded data for fee collection
    function _collectFees(bytes memory _collectFeesData) internal virtual {
        (IV3Pool _pool, address _hook, int24 _tickLower, int24 _tickUpper) =
            abi.decode(_collectFeesData, (IV3Pool, address, int24, int24));

        uint256 tokenId = uint256(keccak256(abi.encode(address(this), _pool, _hook, _tickLower, _tickUpper)));

        TokenIdInfo storage tki = tokenIds[tokenId];

        _removeLiquidity(_pool, _tickLower, _tickUpper, 0);

        _feeCalculation(tki, _pool, _tickLower, _tickUpper);

        emit LogCollectedFees(_pool, _hook, _tickLower, _tickUpper, tki.tokensOwed0, tki.tokensOwed1);

        _pool.collect(feeReceiver, _tickLower, _tickUpper, tki.tokensOwed0, tki.tokensOwed1);

        tki.tokensOwed0 = 0;
        tki.tokensOwed1 = 0;
    }

    /// @notice Internal function to calculate fees for a position
    /// @param _tki Token ID information
    /// @param _pool The Uniswap V3 pool
    /// @param _tickLower The lower tick of the position
    /// @param _tickUpper The upper tick of the position
    function _feeCalculation(TokenIdInfo storage _tki, IV3Pool _pool, int24 _tickLower, int24 _tickUpper)
        internal
        virtual
    {
        bytes32 positionKey = _computePositionKey(address(this), _tickLower, _tickUpper);
        (, uint256 feeGrowthInside0LastX128, uint256 feeGrowthInside1LastX128,,) = _pool.positions(positionKey);
        unchecked {
            _tki.tokensOwed0 += uint128(
                FullMath.mulDiv(
                    feeGrowthInside0LastX128 - _tki.feeGrowthInside0LastX128,
                    _tki.totalLiquidity + _tki.reservedLiquidity - _tki.liquidityUsed,
                    FixedPoint128.Q128
                )
            );
            _tki.tokensOwed1 += uint128(
                FullMath.mulDiv(
                    feeGrowthInside1LastX128 - _tki.feeGrowthInside1LastX128,
                    _tki.totalLiquidity + _tki.reservedLiquidity - _tki.liquidityUsed,
                    FixedPoint128.Q128
                )
            );

            _tki.feeGrowthInside0LastX128 = feeGrowthInside0LastX128;
            _tki.feeGrowthInside1LastX128 = feeGrowthInside1LastX128;
        }
    }

    // Admin Functions

    /// @notice Updates various handler settings
    /// @param _app The app to update the whitelist status of
    /// @param _status The new whitelist status of the app
    /// @param _hook The hook to update the reserve cooldown for
    /// @param _newReserveCooldown The new reserve cooldown for the hook
    /// @param _newFeeReceiver The new fee receiver address
    function updateHandlerSettings(
        address _app,
        bool _status,
        address _hook,
        uint64 _newReserveCooldown,
        address _newFeeReceiver
    ) external onlyOwner {
        whitelistedApps[_app] = _status;
        reserveCooldownHook[_hook] = _newReserveCooldown;
        feeReceiver = _newFeeReceiver;
    }

    // SOS admin functions

    /// @notice Sweeps tokens from the contract
    /// @param _token The token to sweep
    /// @param _amount The amount of tokens to sweep
    function sweepTokens(address _token, uint256 _amount) external onlyOwner {
        IERC20(_token).safeTransfer(msg.sender, _amount);
    }

    /// @notice Emergency pauses the contract
    function emergencyPause() external onlyOwner {
        pause = true;
    }

    /// @notice Emergency unpauses the contract
    function emergencyUnpause() external onlyOwner {
        pause = false;
    }

    /// @notice Checks if the contract supports an interface
    /// @param interfaceId The Id of the interface
    /// @return bool True if the interface is supported
    function supportsInterface(bytes4 interfaceId) public view override(ERC6909) returns (bool) {
        return super.supportsInterface(interfaceId);
    }
}
