// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "v3-core/interfaces/IUniswapV3Factory.sol";
import "./interfaces/aerodrome/IAerodromeSlipstreamPool.sol";

import "v3-core/libraries/FullMath.sol";
import "v3-core/libraries/TickMath.sol";

import "v3-periphery/libraries/PoolAddress.sol";
import "v3-periphery/libraries/LiquidityAmounts.sol";

import "v3-periphery/interfaces/INonfungiblePositionManager.sol";

import "./interfaces/aerodrome/IAerodromeSlipstreamFactory.sol";
import "./interfaces/aerodrome/IAerodromeSlipstreamPool.sol";
import "./interfaces/aerodrome/IAerodromeNonfungiblePositionManager.sol";
import "./utils/AerodromePoolAddress.sol";
import "./utils/AerodromeHelper.sol";

import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/utils/math/SafeCast.sol";

import "../lib/AggregatorV3Interface.sol";

import "./interfaces/IV3Oracle.sol";
import "./utils/Constants.sol";

/// @title V3Oracle to be used in V3Vault to calculate position values
/// @notice It uses both chainlink and Aerodrome Slipstream TWAP and provides emergency fallback mode
contract V3Oracle is IV3Oracle, Ownable2Step, Constants {
    uint256 private constant SEQUENCER_GRACE_PERIOD_TIME = 600; // 10mins

    event TokenConfigUpdated(address indexed token, TokenConfig config);
    event OracleModeUpdated(address indexed token, Mode mode);
    event SetMaxPoolPriceDifference(uint16 maxPoolPriceDifference);
    event SetEmergencyAdmin(address emergencyAdmin);
    event SetSequencerUptimeFeed(address sequencerUptimeFeed);

    enum Mode {
        NOT_SET,
        CHAINLINK_TWAP_VERIFY, // using chainlink for price and TWAP to verify
        TWAP_CHAINLINK_VERIFY, // using TWAP for price and chainlink to verify
        CHAINLINK, // using only chainlink directly
        TWAP // using TWAP directly

    }

    address public immutable factory;
    IAerodromeNonfungiblePositionManager public immutable nonfungiblePositionManager;

    // common token which is used in TWAP pools
    address public immutable referenceToken;
    uint8 public immutable referenceTokenDecimals;

    // common token which is used in chainlink feeds as "pair" (address(0) if USD or another non-token reference)
    address public immutable chainlinkReferenceToken;

    struct TokenConfig {
        AggregatorV3Interface feed; // chainlink feed
        uint32 maxFeedAge;
        uint8 feedDecimals;
        uint8 tokenDecimals;
        uint32 twapSeconds;
        IAerodromeSlipstreamPool pool; // reference pool
        bool isToken0;
        Mode mode;
        uint16 maxDifference; // max price difference x10000
    }

    // token => config mapping
    mapping(address => TokenConfig) public feedConfigs;

    uint16 public maxPoolPriceDifference; // max price difference between oracle derived price and pool price x10000

    // address which can call special emergency actions without timelock
    address public emergencyAdmin;

    // feed to check sequencer up on L2s - address(0) when not needed
    address public sequencerUptimeFeed;

    // constructor: sets owner of contract
    constructor(
        IAerodromeNonfungiblePositionManager _nonfungiblePositionManager,
        address _referenceToken,
        address _chainlinkReferenceToken
    ) {
        nonfungiblePositionManager = _nonfungiblePositionManager;
        factory = _nonfungiblePositionManager.factory();
        referenceToken = _referenceToken;
        referenceTokenDecimals = IERC20Metadata(_referenceToken).decimals();
        chainlinkReferenceToken = _chainlinkReferenceToken;
    }

    /// @notice Gets value and prices of a uniswap v3 lp position in specified token
    /// @dev uses configured oracles and verfies price on second oracle - if fails - reverts
    /// @dev all involved tokens must be configured in oracle - otherwise reverts
    /// @param tokenId tokenId of position
    /// @param token address of token in which value and prices should be given
    /// @return value value of complete position at current oracle prices
    /// @return feeValue value of positions fees only at current oracle prices
    /// @return price0X96 price of token0
    /// @return price1X96 price of token1
    function getValue(uint256 tokenId, address token)
        external
        view
        override
        returns (uint256 value, uint256 feeValue, uint256 price0X96, uint256 price1X96)
    {
        PositionState memory state = _loadPositionState(tokenId);
        _populatePrices(state);
        (uint256 amount0, uint256 amount1) = _getAmounts(state);
        (uint128 fees0, uint128 fees1) = _getFees(state);

        // get price of quote token
        uint256 priceTokenX96;
        if (state.token0 == token) {
            priceTokenX96 = state.price0X96;
        } else if (state.token1 == token) {
            priceTokenX96 = state.price1X96;
        } else {
            (priceTokenX96,) = _getReferenceTokenPriceX96(token, state.cachedChainlinkReferencePriceX96);
        }

        // calculate outputs
        value = (state.price0X96 * (amount0 + fees0) + state.price1X96 * (amount1 + fees1)) / priceTokenX96;
        feeValue = (state.price0X96 * fees0 + state.price1X96 * fees1) / priceTokenX96;
        price0X96 = state.price0X96 * Q96 / priceTokenX96;
        price1X96 = state.price1X96 * Q96 / priceTokenX96;
    }

    function _requireMaxDifference(uint256 priceX96, uint256 verifyPriceX96, uint16 maxDifferenceX10000)
        internal
        pure
    {
        uint256 differenceX10000 =
            priceX96 >= verifyPriceX96 ? (priceX96 - verifyPriceX96) * 10000 : (verifyPriceX96 - priceX96) * 10000;

        // if invalid price or too big difference - revert
        if (
            (verifyPriceX96 == 0 || differenceX10000 / verifyPriceX96 > maxDifferenceX10000)
                && maxDifferenceX10000 < type(uint16).max
        ) {
            revert PriceDifferenceExceeded();
        }
    }

    /// @notice Gets breakdown of a uniswap v3 position (tokens and fee tier, liquidity, current liquidity amounts, uncollected fees)
    /// @param tokenId tokenId of position
    /// @return token0 token0 of position
    /// @return token1 token1 of position
    /// @return fee fee tier of position
    /// @return liquidity liquidity of position
    /// @return amount0 current amount token0
    /// @return amount1 current amount token1
    /// @return fees0 current token0 fees of position
    /// @return fees1 current token1 fees of position
    function getPositionBreakdown(uint256 tokenId)
        external
        view
        override
        returns (
            address token0,
            address token1,
            uint24 fee,
            uint128 liquidity,
            uint256 amount0,
            uint256 amount1,
            uint128 fees0,
            uint128 fees1
        )
    {
        PositionState memory state = _loadPositionState(tokenId);
        _populatePrices(state);
        (token0, token1, fee) = (state.token0, state.token1, state.fee);
        (amount0, amount1) = _getAmounts(state);
        (fees0, fees1) = _getFees(state);
        liquidity = state.liquidity;
    }

    /// @notice Gets liquidity and uncollected fees
    /// @param tokenId tokenId of position
    /// @return liquidity liquidity of position
    /// @return fees0 current token0 fees of position
    /// @return fees1 current token1 fees of position
    function getLiquidityAndFees(uint256 tokenId)
        external
        view
        override
        returns (uint128 liquidity, uint128 fees0, uint128 fees1)
    {
        PositionState memory state = _loadPositionState(tokenId);
        liquidity = state.liquidity;
        (fees0, fees1) = _getFees(state);
    }

    /// @notice Sets the max pool difference parameter (onlyOwner)
    /// @param _maxPoolPriceDifference Set max allowable difference between pool price and derived oracle pool price
    function setMaxPoolPriceDifference(uint16 _maxPoolPriceDifference) external onlyOwner {
        maxPoolPriceDifference = _maxPoolPriceDifference;
        emit SetMaxPoolPriceDifference(_maxPoolPriceDifference);
    }

    /// @notice Sets or updates the feed configuration for a token (onlyOwner)
    /// @param token Token to configure
    /// @param feed Chainlink feed to this token (matching chainlinkReferenceToken)
    /// @param maxFeedAge Max allowable chainlink feed age
    /// @param pool TWAP reference pool (matching referenceToken)
    /// @param twapSeconds TWAP period to use
    /// @param mode Mode how both oracle should be used
    /// @param maxDifference Max allowable difference between both oracle prices
    function setTokenConfig(
        address token,
        AggregatorV3Interface feed,
        uint32 maxFeedAge,
        IAerodromeSlipstreamPool pool,
        uint32 twapSeconds,
        Mode mode,
        uint16 maxDifference
    ) external onlyOwner {
        // can not be unset
        if (mode == Mode.NOT_SET) {
            revert InvalidConfig();
        }

        uint8 feedDecimals = feed.decimals();
        uint8 tokenDecimals = IERC20Metadata(token).decimals();

        TokenConfig memory config;

        if (token != referenceToken) {
            address token0 = pool.token0();
            address token1 = pool.token1();
            if (!(token0 == token && token1 == referenceToken || token0 == referenceToken && token1 == token)) {
                revert InvalidPool();
            }
            bool isToken0 = token0 == token;
            config = TokenConfig(
                feed, maxFeedAge, feedDecimals, tokenDecimals, twapSeconds, pool, isToken0, mode, maxDifference
            );
        } else {
            config = TokenConfig(
                feed, maxFeedAge, feedDecimals, tokenDecimals, 0, IAerodromeSlipstreamPool(address(0)), false, Mode.CHAINLINK, 0
            );
        }

        feedConfigs[token] = config;

        emit TokenConfigUpdated(token, config);
        emit OracleModeUpdated(token, mode);
    }

    /// @notice Updates the oracle mode for a given token  - this method can be called by owner OR emergencyAdmin
    /// @param token Token to configure
    /// @param mode Mode to set
    function setOracleMode(address token, Mode mode) external {
        if (msg.sender != emergencyAdmin && msg.sender != owner()) {
            revert Unauthorized();
        }

        // can not be unset
        if (mode == Mode.NOT_SET) {
            revert InvalidConfig();
        }

        feedConfigs[token].mode = mode;
        emit OracleModeUpdated(token, mode);
    }

    /// @notice Sets sequencer uptime feed for L2 where needed
    /// @param feed Sequencer uptime feed
    function setSequencerUptimeFeed(address feed) external onlyOwner {
        sequencerUptimeFeed = feed;
        emit SetSequencerUptimeFeed(feed);
    }

    /// @notice Updates emergency admin address (onlyOwner)
    /// @param admin Emergency admin address
    function setEmergencyAdmin(address admin) external onlyOwner {
        emergencyAdmin = admin;
        emit SetEmergencyAdmin(admin);
    }

    // Returns the price for a token using the selected oracle mode given as reference token value
    // The price is calculated using Chainlink, Uniswap v3 TWAP, or both based on the mode
    function _getReferenceTokenPriceX96(address token, uint256 cachedChainlinkReferencePriceX96)
        internal
        view
        returns (uint256 priceX96, uint256 chainlinkReferencePriceX96)
    {
        if (token == referenceToken) {
            return (Q96, cachedChainlinkReferencePriceX96);
        }

        TokenConfig memory feedConfig = feedConfigs[token];
        Mode mode = feedConfig.mode;

        if (mode == Mode.NOT_SET) {
            revert NotConfigured();
        }

        uint256 verifyPriceX96;

        bool usesChainlink = (
            mode == Mode.CHAINLINK_TWAP_VERIFY || mode == Mode.TWAP_CHAINLINK_VERIFY
                || mode == Mode.CHAINLINK
        );
        bool usesTWAP = (
            mode == Mode.CHAINLINK_TWAP_VERIFY || mode == Mode.TWAP_CHAINLINK_VERIFY
                || mode == Mode.TWAP
        );

        if (usesChainlink) {
            uint256 chainlinkPriceX96 = _getChainlinkPriceX96(token);
            chainlinkReferencePriceX96 = cachedChainlinkReferencePriceX96 == 0
                ? _getChainlinkPriceX96(referenceToken)
                : cachedChainlinkReferencePriceX96;

            if (referenceTokenDecimals > feedConfig.tokenDecimals) {
                chainlinkPriceX96 = (10 ** (referenceTokenDecimals - feedConfig.tokenDecimals)) * chainlinkPriceX96
                    * Q96 / chainlinkReferencePriceX96;
            } else if (referenceTokenDecimals < feedConfig.tokenDecimals) {
                chainlinkPriceX96 = chainlinkPriceX96 * Q96 / chainlinkReferencePriceX96
                    / (10 ** (feedConfig.tokenDecimals - referenceTokenDecimals));
            } else {
                chainlinkPriceX96 = chainlinkPriceX96 * Q96 / chainlinkReferencePriceX96;
            }

            if (mode == Mode.TWAP_CHAINLINK_VERIFY) {
                verifyPriceX96 = chainlinkPriceX96;
            } else {
                priceX96 = chainlinkPriceX96;
            }
        }

        if (usesTWAP) {
            uint256 twapPriceX96 = _getTWAPPriceX96(feedConfig);
            if (mode == Mode.CHAINLINK_TWAP_VERIFY) {
                verifyPriceX96 = twapPriceX96;
            } else {
                priceX96 = twapPriceX96;
            }
        }

        if (mode == Mode.CHAINLINK_TWAP_VERIFY || mode == Mode.TWAP_CHAINLINK_VERIFY) {
            _requireMaxDifference(priceX96, verifyPriceX96, feedConfig.maxDifference);
        }
    }

    // calculates chainlink price given feedConfig
    function _getChainlinkPriceX96(address token) internal view returns (uint256) {
        if (token == chainlinkReferenceToken) {
            return Q96;
        }

        // sequencer check on chains where needed
        if (sequencerUptimeFeed != address(0)) {
            (, int256 sequencerAnswer, uint256 startedAt,,) =
                AggregatorV3Interface(sequencerUptimeFeed).latestRoundData();

            // Answer == 0: Sequencer is up
            // Answer == 1: Sequencer is down
            if (sequencerAnswer == 1) {
                revert SequencerDown();
            }

            // Make sure - feed result is valid
            if (startedAt == 0) {
                revert SequencerUptimeFeedInvalid();
            }

            // Make sure the grace period has passed after the
            // sequencer is back up.
            uint256 timeSinceUp = block.timestamp - startedAt;
            if (timeSinceUp <= SEQUENCER_GRACE_PERIOD_TIME) {
                revert SequencerGracePeriodNotOver();
            }
        }

        TokenConfig memory feedConfig = feedConfigs[token];

        // if stale data - revert
        (, int256 answer,, uint256 updatedAt,) = feedConfig.feed.latestRoundData();
        if (updatedAt + feedConfig.maxFeedAge < block.timestamp || answer <= 0) {
            revert ChainlinkPriceError();
        }

        return uint256(answer) * Q96 / (10 ** feedConfig.feedDecimals);
    }

    // calculates TWAP price given feedConfig
    function _getTWAPPriceX96(TokenConfig memory feedConfig) internal view returns (uint256 poolTWAPPriceX96) {
        // get reference pool price
        uint256 priceX96 = _getReferencePoolPriceX96(feedConfig.pool, feedConfig.twapSeconds);

        if (feedConfig.isToken0) {
            poolTWAPPriceX96 = priceX96;
        } else {
            poolTWAPPriceX96 = Q96 * Q96 / priceX96;
        }
    }

    // Calculates the reference pool price with scaling factor of 2^96
    // It uses either the latest slot price or TWAP based on twapSeconds
    function _getReferencePoolPriceX96(IAerodromeSlipstreamPool pool, uint32 twapSeconds) internal view returns (uint256) {
        uint160 sqrtPriceX96;
        // if twap seconds set to 0 just use pool price
        if (twapSeconds == 0) {
            (sqrtPriceX96,,,,,) = pool.slot0();
        } else {
            uint32[] memory secondsAgos = new uint32[](2);
            secondsAgos[0] = 0; // from (before)
            secondsAgos[1] = twapSeconds; // from (before)
            (int56[] memory tickCumulatives,) = pool.observe(secondsAgos); // pool observe may fail when there is not enough history available (only use pool with enough history!)
            int24 tick = int24((tickCumulatives[0] - tickCumulatives[1]) / int56(uint56(twapSeconds)));
            if (
                tickCumulatives[0] - tickCumulatives[1] < 0
                    && (tickCumulatives[0] - tickCumulatives[1]) % int32(twapSeconds) != 0
            ) tick--;
            sqrtPriceX96 = TickMath.getSqrtRatioAtTick(tick);
        }

        return FullMath.mulDiv(sqrtPriceX96, sqrtPriceX96, Q96);
    }

    struct PositionState {
        uint256 tokenId;
        address token0;
        address token1;
        uint24 fee; // For Aerodrome: this is actually tickSpacing (immutable pool parameter)
        int24 tickLower;
        int24 tickUpper;
        uint128 liquidity;
        uint256 feeGrowthInside0LastX128;
        uint256 feeGrowthInside1LastX128;
        uint128 tokensOwed0;
        uint128 tokensOwed1;
        IAerodromeSlipstreamPool pool;
        uint160 sqrtPriceX96;
        int24 tick;
        uint160 sqrtPriceX96Lower;
        uint160 sqrtPriceX96Upper;
        uint256 price0X96;
        uint256 price1X96;
        uint160 derivedSqrtPriceX96;
        uint256 cachedChainlinkReferencePriceX96;
    }

    function _loadPositionState(uint256 tokenId) internal view returns (PositionState memory state) {
        (
            ,
            ,
            address token0,
            address token1,
            uint24 feeOrTickSpacing, // Aerodrome: tickSpacing (immutable), Uniswap: fee tier
            int24 tickLower,
            int24 tickUpper,
            uint128 liquidity,
            uint256 feeGrowthInside0LastX128,
            uint256 feeGrowthInside1LastX128,
            uint128 tokensOwed0,
            uint128 tokensOwed1
        ) = nonfungiblePositionManager.positions(tokenId);
        state.tokenId = tokenId;
        state.token0 = token0;
        state.token1 = token1;
        state.fee = feeOrTickSpacing; // Stores tickSpacing for Aerodrome pools
        state.tickLower = tickLower;
        state.tickUpper = tickUpper;
        state.liquidity = liquidity;
        state.feeGrowthInside0LastX128 = feeGrowthInside0LastX128;
        state.feeGrowthInside1LastX128 = feeGrowthInside1LastX128;
        state.tokensOwed0 = tokensOwed0;
        state.tokensOwed1 = tokensOwed1;
        state.pool = _getPool(state.token0, state.token1, state.fee);
        (state.sqrtPriceX96, state.tick,,,,) = state.pool.slot0();
    }

    // gets prices according to oracle configuration (this reverts if any price is configured wrongly)
    function _populatePrices(PositionState memory state) internal view {
        (state.price0X96, state.cachedChainlinkReferencePriceX96) =
            _getReferenceTokenPriceX96(state.token0, state.cachedChainlinkReferencePriceX96);
        (state.price1X96, state.cachedChainlinkReferencePriceX96) =
            _getReferenceTokenPriceX96(state.token1, state.cachedChainlinkReferencePriceX96);

        // checks derived pool price for price manipulation attacks
        // this prevents manipulations of pool to get distorted proportions of collateral tokens - for borrowing
        // when a pool is in this state, liquidations will be disabled - but arbitrageurs (or liquidator himself)
        // will move price back to reasonable range and enable liquidation
        uint256 derivedPoolPriceX96 = state.price0X96 * Q96 / state.price1X96;

        // current pool price
        uint256 priceX96 = FullMath.mulDiv(state.sqrtPriceX96, state.sqrtPriceX96, Q96);
        _requireMaxDifference(priceX96, derivedPoolPriceX96, maxPoolPriceDifference);

        // calculate derived sqrt price
        state.derivedSqrtPriceX96 = SafeCast.toUint160(Math.sqrt(derivedPoolPriceX96) * (2 ** 48));
    }

    // calculate position amounts given derived price from oracle
    function _getAmounts(PositionState memory state) internal pure returns (uint256 amount0, uint256 amount1) {
        if (state.liquidity != 0) {
            state.sqrtPriceX96Lower = TickMath.getSqrtRatioAtTick(state.tickLower);
            state.sqrtPriceX96Upper = TickMath.getSqrtRatioAtTick(state.tickUpper);
            (amount0, amount1) = LiquidityAmounts.getAmountsForLiquidity(
                state.derivedSqrtPriceX96, state.sqrtPriceX96Lower, state.sqrtPriceX96Upper, state.liquidity
            );
        }
    }

    // calculate uncollected position fees
    function _getFees(PositionState memory state) internal view returns (uint128 fees0, uint128 fees1) {
        (fees0, fees1) = _getUncollectedFees(state, state.tick);
        fees0 += state.tokensOwed0;
        fees1 += state.tokensOwed1;
    }

    // calculate uncollected fees
    function _getUncollectedFees(PositionState memory position, int24 tick)
        internal
        view
        returns (uint128 fees0, uint128 fees1)
    {
        (uint256 feeGrowthInside0LastX128, uint256 feeGrowthInside1LastX128) = _getFeeGrowthInside(
            position.pool,
            position.tickLower,
            position.tickUpper,
            tick,
            position.pool.feeGrowthGlobal0X128(),
            position.pool.feeGrowthGlobal1X128()
        );

        // allow overflow - this is as designed by uniswap - see PositionValue library (for solidity < 0.8)
        uint256 feeGrowth0;
        uint256 feeGrowth1;
        unchecked {
            feeGrowth0 = feeGrowthInside0LastX128 - position.feeGrowthInside0LastX128;
            feeGrowth1 = feeGrowthInside1LastX128 - position.feeGrowthInside1LastX128;
        }

        fees0 = SafeCast.toUint128(FullMath.mulDiv(feeGrowth0, position.liquidity, Q128));
        fees1 = SafeCast.toUint128(FullMath.mulDiv(feeGrowth1, position.liquidity, Q128));
    }

    // calculate fee growth for uncollected fees calculation
    function _getFeeGrowthInside(
        IAerodromeSlipstreamPool pool,
        int24 tickLower,
        int24 tickUpper,
        int24 tickCurrent,
        uint256 feeGrowthGlobal0X128,
        uint256 feeGrowthGlobal1X128
    ) internal view returns (uint256 feeGrowthInside0X128, uint256 feeGrowthInside1X128) {
        // Aerodrome ticks() returns 10 values (includes stakedLiquidityNet at index 2 and rewardGrowthOutsideX128 at index 5)
        (,,, uint256 lowerFeeGrowthOutside0X128, uint256 lowerFeeGrowthOutside1X128,,,,,) = pool.ticks(tickLower);
        (,,, uint256 upperFeeGrowthOutside0X128, uint256 upperFeeGrowthOutside1X128,,,,,) = pool.ticks(tickUpper);

        // allow overflow - this is as designed by uniswap - see PositionValue library (for solidity < 0.8)
        unchecked {
            if (tickCurrent < tickLower) {
                feeGrowthInside0X128 = lowerFeeGrowthOutside0X128 - upperFeeGrowthOutside0X128;
                feeGrowthInside1X128 = lowerFeeGrowthOutside1X128 - upperFeeGrowthOutside1X128;
            } else if (tickCurrent < tickUpper) {
                feeGrowthInside0X128 = feeGrowthGlobal0X128 - lowerFeeGrowthOutside0X128 - upperFeeGrowthOutside0X128;
                feeGrowthInside1X128 = feeGrowthGlobal1X128 - lowerFeeGrowthOutside1X128 - upperFeeGrowthOutside1X128;
            } else {
                feeGrowthInside0X128 = upperFeeGrowthOutside0X128 - lowerFeeGrowthOutside0X128;
                feeGrowthInside1X128 = upperFeeGrowthOutside1X128 - lowerFeeGrowthOutside1X128;
            }
        }
    }

    // helper method to get pool for token
    function _getPool(address tokenA, address tokenB, uint24 fee) internal view returns (IAerodromeSlipstreamPool) {
        // For Aerodrome: 'fee' parameter contains the immutable tickSpacing value
        int24 tickSpacing = int24(uint24(fee));
        
        // Get pool from factory (Aerodrome uses getPool instead of computing address)
        address poolAddress = IAerodromeSlipstreamFactory(factory).getPool(tokenA, tokenB, tickSpacing);
        require(poolAddress != address(0), "Pool does not exist");
        
        return IAerodromeSlipstreamPool(poolAddress);
    }
}
