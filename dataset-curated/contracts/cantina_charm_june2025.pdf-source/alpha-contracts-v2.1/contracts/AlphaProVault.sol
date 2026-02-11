// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.0;
pragma abicoder v2;

import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {IUniswapV3MintCallback} from "@uniswap/v3-core/contracts/interfaces/callback/IUniswapV3MintCallback.sol";
import {IUniswapV3SwapCallback} from "@uniswap/v3-core/contracts/interfaces/callback/IUniswapV3SwapCallback.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {PositionKey} from "@uniswap/v3-periphery/contracts/libraries/PositionKey.sol";
import {TickMath} from "@uniswap/v3-core/contracts/libraries/TickMath.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {LiquidityAmounts} from "./library/LiquidityAmounts.sol";

import "./AlphaProVaultFactory.sol";
import "../interfaces/IVault.sol";

/**
 * @param pool Underlying Uniswap V3 pool address
 * @param manager Address of manager who can set parameters and call rebalance
 * @param rebalanceDelegate Address of an additional wallet that can call rebalance
 * @param managerFee % Fee charge by the vault manager multiplied by 1e4
 * @param maxTotalSupply Cap on the total supply of vault shares
 * @param wideRangeWeight Proportion of liquidity in wide range multiplied by 1e6
 * @param wideThreshold Wide range threshold in ticks
 * @param baseThreshold Half of the base order width in ticks
 * @param limitThreshold Limit order width in ticks
 * @param period Can only rebalance if this length of time (in seconds) has passed
 * @param minTickMove Can only rebalance if price has moved at least this much
 * @param maxTwapDeviation Max deviation (in ticks) from the TWAP during rebalance
 * @param twapDuration TWAP duration in seconds for maxTwapDeviation check
 * @param name name of the vault to be created
 * @param symbol symbol of the vault to be created
 * @param factory Address of AlphaProFactory contract
 */
struct VaultParams {
    address pool;
    address manager;
    uint24 managerFee;
    uint256 maxTotalSupply;
    uint24 wideRangeWeight;
    int24 wideThreshold;
    int24 baseThreshold;
    int24 limitThreshold;
    uint32 period;
    int24 minTickMove;
    int24 maxTwapDeviation;
    uint32 twapDuration;
    string name;
    string symbol;
}

/**
 * @title   Alpha Pro Vault
 * @notice  A vault that provides liquidity on Uniswap V3.
 */
contract AlphaProVault is
    IVault,
    IUniswapV3MintCallback,
    IUniswapV3SwapCallback,
    ERC20Upgradeable,
    ReentrancyGuardUpgradeable
{
    using SafeERC20 for IERC20;

    event Deposit(address indexed sender, address indexed to, uint256 shares, uint256 amount0, uint256 amount1);
    event Withdraw(address indexed sender, address indexed to, uint256 shares, uint256 amount0, uint256 amount1);
    event CollectFees(
        uint256 feesToVault0,
        uint256 feesToVault1,
        uint256 feesToProtocol0,
        uint256 feesToProtocol1,
        uint256 feesToManager0,
        uint256 feesToManager1
    );
    event Snapshot(int24 tick, uint256 totalAmount0, uint256 totalAmount1, uint256 totalSupply);
    event CollectProtocol(uint256 amount0, uint256 amount1);
    event CollectManager(uint256 amount0, uint256 amount1);

    event UpdateManager(address manager);
    event UpdatePendingManager(address manager);
    event UpdateRebalanceDelegate(address delegate);
    event UpdateDepositDelegate(address delegate);
    event UpdateManagerFee(uint24 managerFee);
    event UpdateProtocolFee(uint24 protocolFee);
    event UpdateBaseThreshold(int24 threshold);
    event UpdateLimitThreshold(int24 threshold);
    event UpdateWideRangeWeight(uint24 weight);
    event UpdateWideThreshold(int24 threshold);
    event UpdatePeriod(uint32 period);
    event UpdateMinTickMove(int24 minTickMove);
    event UpdateMaxTwapDeviation(int24 maxTwapDeviation);
    event UpdateTwapDuration(uint32 twapDuration);
    event UpdateMaxTotalSupply(uint256 maxTotalSupply);

    IUniswapV3Pool public override pool;
    IERC20 public token0;
    IERC20 public token1;
    AlphaProVaultFactory public factory;

    uint256 public constant MINIMUM_LIQUIDITY = 1e3;
    uint24 public constant HUNDRED_PERCENT = 1e6;

    address public override manager;
    address public override pendingManager;
    address public override rebalanceDelegate;
    address public override depositDelegate;
    uint256 public override maxTotalSupply;
    uint128 public override accruedProtocolFees0;
    uint128 public override accruedProtocolFees1;
    uint104 public override accruedManagerFees0;
    uint104 public override accruedManagerFees1;
    uint40 public override lastTimestamp;

    uint32 public override period;
    uint24 public override protocolFee;
    uint24 public override managerFee;
    uint24 public override pendingManagerFee;
    uint24 public override pendingProtocolFee;
    uint24 public override wideRangeWeight;
    int24 public override baseThreshold;
    int24 public override limitThreshold;
    int24 public override wideThreshold;
    int24 public override minTickMove;
    int24 public override tickSpacing;
    int24 public override maxTwapDeviation;
    uint32 public override twapDuration;
    int24 public override wideLower;
    int24 public override wideUpper;
    int24 public override baseLower;
    int24 public override baseUpper;
    int24 public override limitLower;
    int24 public override limitUpper;
    int24 public override lastTick;
    int24 public maxTick;

    function initialize(VaultParams memory _params, address _factory) public initializer {
        __ERC20_init(_params.name, _params.symbol);
        __ReentrancyGuard_init();

        pool = IUniswapV3Pool(_params.pool);
        token0 = IERC20(pool.token0());
        token1 = IERC20(pool.token1());

        int24 _tickSpacing = tickSpacing = pool.tickSpacing();
        maxTick = TickMath.MAX_TICK / _tickSpacing * _tickSpacing;

        manager = _params.manager;
        rebalanceDelegate = _params.manager;
        depositDelegate = _params.manager;
        pendingManagerFee = _params.managerFee;
        maxTotalSupply = _params.maxTotalSupply;
        baseThreshold = _params.baseThreshold;
        limitThreshold = _params.limitThreshold;
        wideRangeWeight = _params.wideRangeWeight;
        wideThreshold = _params.wideThreshold;
        period = _params.period;
        minTickMove = _params.minTickMove;
        maxTwapDeviation = _params.maxTwapDeviation;
        twapDuration = _params.twapDuration;

        factory = AlphaProVaultFactory(_factory);
        protocolFee = factory.protocolFee();

        _checkThreshold(_params.baseThreshold, _tickSpacing);
        _checkThreshold(_params.limitThreshold, _tickSpacing);
        _checkThreshold(_params.wideThreshold, _tickSpacing);
        require(_params.wideRangeWeight <= 1e6, "wideRangeWeight must be <= 1e6");
        require(_params.minTickMove >= 0, "minTickMove must be >= 0");
        require(_params.maxTwapDeviation >= 0, "maxTwapDeviation must be >= 0");
        require(_params.twapDuration > 0, "twapDuration must be > 0");
        require(_params.managerFee <= HUNDRED_PERCENT, "managerFee must be <= 1000000");
        require(_params.wideThreshold != _params.baseThreshold, "wideThreshold must be != baseThreshold");
    }

    /**
     * @notice Deposits tokens in proportion to the vault's current holdings.
     * @dev These tokens sit in the vault and are not used for liquidity on
     * Uniswap until the next rebalance. Also note it's not necessary to check
     * if user manipulated price to deposit cheaper, as the value of range
     * orders can only by manipulated higher.
     * @param amount0Desired Max amount of token0 to deposit
     * @param amount1Desired Max amount of token1 to deposit
     * @param amount0Min Revert if resulting `amount0` is less than this
     * @param amount1Min Revert if resulting `amount1` is less than this
     * @param to Recipient of shares
     * @return shares Number of shares minted
     * @return amount0 Amount of token0 deposited
     * @return amount1 Amount of token1 deposited
     */
    function deposit(uint256 amount0Desired, uint256 amount1Desired, uint256 amount0Min, uint256 amount1Min, address to)
        external
        override
        nonReentrant
        returns (uint256 shares, uint256 amount0, uint256 amount1)
    {
        if (depositDelegate != address(0)) {
            require(msg.sender == depositDelegate, "depositDelegate");
        }
        require(amount0Desired > 0 || amount1Desired > 0, "amount0Desired or amount1Desired");
        require(to != address(0) && to != address(this), "to");
        checkPriceNearTwap();

        // Poke positions so vault's current holdings are up-to-date
        int24[2][3] memory positions = [[wideLower, wideUpper], [baseLower, baseUpper], [limitLower, limitUpper]];
        uint128[3] memory liquidities;
        for (uint256 i = 0; i < 3; i++) {
            (liquidities[i],,,,) = _position(positions[i][0], positions[i][1]);
            if (liquidities[i] > 0) {
                pool.burn(positions[i][0], positions[i][1], 0);
            }
        }

        // Calculate amounts proportional to vault's holdings
        (shares, amount0, amount1) = _calcSharesAndAmounts(amount0Desired, amount1Desired);
        require(shares > 0, "shares");
        require(amount0 >= amount0Min, "amount0Min");
        require(amount1 >= amount1Min, "amount1Min");

        // Permanently lock the first MINIMUM_LIQUIDITY tokens
        if (totalSupply() == 0) {
            _mint(address(factory), MINIMUM_LIQUIDITY);
        }

        // Pull in tokens from sender
        if (amount0 > 0) token0.safeTransferFrom(msg.sender, address(this), amount0);
        if (amount1 > 0) token1.safeTransferFrom(msg.sender, address(this), amount1);

        uint256 _totalSupply = totalSupply();
        (uint160 sqrtRatioX96,,,,,,) = pool.slot0();
        (uint256 depositAmount0, uint256 depositAmount1) = (amount0, amount1);

        for (uint256 i = 0; i < 3; i++) {
            int24 tickLower = positions[i][0];
            int24 tickUpper = positions[i][1];

            if (liquidities[i] > 0) {
                uint128 liquidityToMint = uint128(Math.mulDiv(liquidities[i], shares, _totalSupply));
                uint128 liquidityFromAmounts =
                    _liquidityForAmounts(tickLower, tickUpper, depositAmount0, depositAmount1, sqrtRatioX96);
                liquidityToMint = liquidityToMint > liquidityFromAmounts ? liquidityFromAmounts : liquidityToMint;
                (uint256 mintAmount0, uint256 mintAmount1) = _mintLiquidity(tickLower, tickUpper, liquidityToMint);
                depositAmount0 -= mintAmount0;
                depositAmount1 -= mintAmount1;
            }
        }

        // Mint shares to recipient
        _mint(to, shares);
        emit Deposit(msg.sender, to, shares, amount0, amount1);
        require(totalSupply() <= maxTotalSupply, "maxTotalSupply");
    }

    /// @dev Calculates the largest possible `amount0` and `amount1` such that
    /// they're in the same proportion as total amounts, but not greater than
    /// `amount0Desired` and `amount1Desired` respectively.
    function _calcSharesAndAmounts(uint256 amount0Desired, uint256 amount1Desired)
        internal
        view
        returns (uint256 shares, uint256 amount0, uint256 amount1)
    {
        uint256 _totalSupply = totalSupply();
        (uint256 total0, uint256 total1) = getTotalAmounts(true);

        // If total supply > 0, vault can't be empty
        assert(_totalSupply == 0 || total0 > 0 || total1 > 0);

        if (_totalSupply == 0) {
            // For first deposit, just use the amounts desired
            amount0 = amount0Desired;
            amount1 = amount1Desired;
            shares = (amount0 > amount1 ? amount0 : amount1) - MINIMUM_LIQUIDITY;
        } else if (total0 == 0) {
            amount1 = amount1Desired;
            shares = amount1 * _totalSupply / total1;
        } else if (total1 == 0) {
            amount0 = amount0Desired;
            shares = amount0 * _totalSupply / total0;
        } else {
            uint256 cross0 = amount0Desired * total1;
            uint256 cross1 = amount1Desired * total0;
            uint256 cross = cross0 > cross1 ? cross1 : cross0;
            require(cross > 0, "cross");

            // Round up amounts
            amount0 = (cross - 1) / total1 + 1;
            amount1 = (cross - 1) / total0 + 1;
            shares = cross * _totalSupply / total0 / total1;
        }
    }

    /**
     * @notice Withdraws tokens in proportion to the vault's holdings.
     * @param shares Shares burned by sender
     * @param amount0Min Revert if resulting `amount0` is smaller than this
     * @param amount1Min Revert if resulting `amount1` is smaller than this
     * @param to Recipient of tokens
     * @return amount0 Amount of token0 sent to recipient
     * @return amount1 Amount of token1 sent to recipient
     */
    function withdraw(uint256 shares, uint256 amount0Min, uint256 amount1Min, address to)
        external
        override
        nonReentrant
        returns (uint256 amount0, uint256 amount1)
    {
        require(shares > 0, "shares");
        require(to != address(0) && to != address(this), "to");
        uint256 _totalSupply = totalSupply();

        // Burn shares
        _burn(msg.sender, shares);

        // Calculate token amounts proportional to unused balances
        amount0 = (getBalance0() * shares) / _totalSupply;
        amount1 = (getBalance1() * shares) / _totalSupply;

        // Withdraw proportion of liquidity from Uniswap pool
        (uint256 wideAmount0, uint256 wideAmount1) = _burnLiquidityShare(wideLower, wideUpper, shares, _totalSupply);
        (uint256 baseAmount0, uint256 baseAmount1) = _burnLiquidityShare(baseLower, baseUpper, shares, _totalSupply);
        (uint256 limitAmount0, uint256 limitAmount1) = _burnLiquidityShare(limitLower, limitUpper, shares, _totalSupply);

        // Sum up total amounts owed to recipient
        amount0 = amount0 + wideAmount0 + baseAmount0 + limitAmount0;
        amount1 = amount1 + wideAmount1 + baseAmount1 + limitAmount1;
        require(amount0 >= amount0Min, "amount0Min");
        require(amount1 >= amount1Min, "amount1Min");

        // Push tokens to recipient
        if (amount0 > 0) token0.safeTransfer(to, amount0);
        if (amount1 > 0) token1.safeTransfer(to, amount1);

        emit Withdraw(msg.sender, to, shares, amount0, amount1);
    }

    /// @dev Withdraws share of liquidity in a range from Uniswap pool.
    function _burnLiquidityShare(int24 tickLower, int24 tickUpper, uint256 shares, uint256 totalSupply)
        internal
        returns (uint256 amount0, uint256 amount1)
    {
        (uint128 totalLiquidity,,,,) = _position(tickLower, tickUpper);
        uint128 liquidity = uint128(Math.mulDiv(totalLiquidity, shares, totalSupply));

        if (liquidity > 0) {
            (uint256 burned0, uint256 burned1, uint128 fees0, uint128 fees1) =
                _burnAndCollect(tickLower, tickUpper, liquidity);

            // Add share of fees
            amount0 = burned0 + ((fees0 * shares) / totalSupply);
            amount1 = burned1 + ((fees1 * shares) / totalSupply);
        }
    }

    /**
     * @notice Updates vault's positions.
     * @dev Three orders are placed - a full-range order, a base order and a
     * limit order. The full-range order is placed first. Then the base
     * order is placed with as much remaining liquidity as possible. This order
     * should use up all of one token, leaving only the other one. This excess
     * amount is then placed as a single-sided bid or ask order.
     */
    function rebalance() external override nonReentrant {
        checkCanRebalance();
        if (rebalanceDelegate != address(0)) {
            require(msg.sender == manager || msg.sender == rebalanceDelegate, "rebalanceDelegate");
        }

        // Withdraw all current liquidity from Uniswap pool
        {
            int24 _wideLower = wideLower;
            int24 _wideUpper = wideUpper;
            (uint128 wideLiquidity,,,,) = _position(_wideLower, _wideUpper);
            (uint128 baseLiquidity,,,,) = _position(baseLower, baseUpper);
            (uint128 limitLiquidity,,,,) = _position(limitLower, limitUpper);
            _burnAndCollect(_wideLower, _wideUpper, wideLiquidity);
            _burnAndCollect(baseLower, baseUpper, baseLiquidity);
            _burnAndCollect(limitLower, limitUpper, limitLiquidity);
        }

        // Calculate new ranges
        (uint160 sqrtRatioX96, int24 tick,,,,,) = pool.slot0();
        int24 _bidLower;
        int24 _bidUpper;
        int24 _askLower;
        int24 _askUpper;
        {
            int24 tickFloor = _floor(tick);
            int24 tickCeil = tickFloor + tickSpacing;
            int24 _maxTick = maxTick;
            wideLower = _boundTick(tickFloor - wideThreshold, _maxTick);
            wideUpper = _boundTick(tickCeil + wideThreshold, _maxTick);
            baseLower = tickFloor - baseThreshold;
            baseUpper = tickCeil + baseThreshold;
            _bidLower = tickFloor - limitThreshold;
            _bidUpper = tickFloor;
            _askLower = tickCeil;
            _askUpper = tickCeil + limitThreshold;
        }

        // Emit snapshot to record balances and supply
        uint256 balance0 = getBalance0();
        uint256 balance1 = getBalance1();
        emit Snapshot(tick, balance0, balance1, totalSupply());

        // Place wide range order on Uniswap
        if (wideRangeWeight > 0) {
            uint128 wideLiquidity = _liquidityForAmounts(wideLower, wideUpper, balance0, balance1, sqrtRatioX96);
            wideLiquidity = _toUint128((uint256(wideLiquidity) * wideRangeWeight) / 1e6);
            (uint256 mintAmount0, uint256 mintAmount1) = _mintLiquidity(wideLower, wideUpper, wideLiquidity);
            balance0 -= mintAmount0;
            balance1 -= mintAmount1;
        }

        // Place base order on Uniswap
        {
            uint128 baseLiquidity = _liquidityForAmounts(baseLower, baseUpper, balance0, balance1, sqrtRatioX96);
            (uint256 mintAmount0, uint256 mintAmount1) = _mintLiquidity(baseLower, baseUpper, baseLiquidity);
            balance0 -= mintAmount0;
            balance1 -= mintAmount1;
        }

        //  Place bid or ask order on Uniswap depending on which token is left
        {
            uint128 bidLiquidity = _liquidityForAmounts(_bidLower, _bidUpper, balance0, balance1, sqrtRatioX96);
            uint128 askLiquidity = _liquidityForAmounts(_askLower, _askUpper, balance0, balance1, sqrtRatioX96);
            if (bidLiquidity > askLiquidity) {
                _mintLiquidity(_bidLower, _bidUpper, bidLiquidity);
                limitLower = _bidLower;
                limitUpper = _bidUpper;
            } else {
                _mintLiquidity(_askLower, _askUpper, askLiquidity);
                limitLower = _askLower;
                limitUpper = _askUpper;
            }
        }

        lastTimestamp = uint40(block.timestamp);
        lastTick = tick;

        // Update fee only at each rebalance, so that if fee is increased
        // it won't be applied retroactively to current open positions
        uint24 _protocolFee = protocolFee = pendingProtocolFee > 0 ? pendingProtocolFee : factory.protocolFee();
        // Manager + protocol fee must be <= 100%
        if (pendingManagerFee + _protocolFee <= HUNDRED_PERCENT) {
            managerFee = pendingManagerFee;
        } else {
            managerFee = HUNDRED_PERCENT - _protocolFee;
        }
    }

    function checkCanRebalance() public view override {
        checkPriceNearTwap();
        uint256 _lastTimestamp = lastTimestamp;

        // check enough time has passed
        require(block.timestamp >= (_lastTimestamp + period), "PE");

        // check price has moved enough
        (, int24 tick,,,,,) = pool.slot0();
        int24 tickMove = tick > lastTick ? tick - lastTick : lastTick - tick;
        require(_lastTimestamp == 0 || tickMove >= minTickMove, "TM");

        // check price not too close to boundary
        int24 maxThreshold = baseThreshold > limitThreshold ? baseThreshold : limitThreshold;
        require(
            tick >= TickMath.MIN_TICK + maxThreshold + tickSpacing
                && tick <= TickMath.MAX_TICK - maxThreshold - tickSpacing,
            "PB"
        );
    }

    function checkPriceNearTwap() public view {
        (, int24 tick,,,,,) = pool.slot0();
        int24 twap = getTwap();
        int24 twapDeviation = tick > twap ? tick - twap : twap - tick;
        require(twapDeviation <= maxTwapDeviation, "TP");
    }

    /// @dev Fetches time-weighted average price in ticks from Uniswap pool.
    function getTwap() public view returns (int24) {
        uint32 _twapDuration = twapDuration;
        uint32[] memory secondsAgo = new uint32[](2);
        secondsAgo[0] = _twapDuration;
        secondsAgo[1] = 0;

        (int56[] memory tickCumulatives,) = pool.observe(secondsAgo);
        return int24((tickCumulatives[1] - tickCumulatives[0]) / int56(uint56((_twapDuration))));
    }

    /// @dev Verifies that tick is within the range boundaries
    function _boundTick(int24 tick, int24 _maxTick) internal pure returns (int24) {
        if (tick < -_maxTick) {
            return -_maxTick;
        }
        if (tick > _maxTick) {
            return _maxTick;
        }
        return tick;
    }

    /// @dev Rounds tick down towards negative infinity so that it's a multiple
    /// of `tickSpacing`.
    function _floor(int24 tick) internal view returns (int24) {
        int24 compressed = tick / tickSpacing;
        if (tick < 0 && tick % tickSpacing != 0) compressed--;
        return compressed * tickSpacing;
    }

    function _checkThreshold(int24 threshold, int24 _tickSpacing) internal pure {
        require(threshold > 0, "threshold must be > 0");
        require(threshold % _tickSpacing == 0, "threshold must be multiple of tickSpacing");
    }

    /// @dev Withdraws liquidity from a range and collects all fees in the
    /// process.
    function _burnAndCollect(int24 tickLower, int24 tickUpper, uint128 liquidity)
        internal
        returns (uint256 burned0, uint256 burned1, uint128 feesToVault0, uint128 feesToVault1)
    {
        if (liquidity > 0) {
            (burned0, burned1) = pool.burn(tickLower, tickUpper, liquidity);
        }

        // Collect all owed tokens including earned fees
        (uint128 collect0, uint128 collect1) =
            pool.collect(address(this), tickLower, tickUpper, type(uint128).max, type(uint128).max);

        feesToVault0 = uint128(collect0 - burned0);
        feesToVault1 = uint128(collect1 - burned1);

        // Update accrued protocol fees
        uint24 _protocolFee = protocolFee;
        uint128 feesToProtocol0 = feesToVault0 * _protocolFee / 1e6;
        uint128 feesToProtocol1 = feesToVault1 * _protocolFee / 1e6;
        accruedProtocolFees0 += feesToProtocol0;
        accruedProtocolFees1 += feesToProtocol1;

        // Update accrued manager fees
        uint24 _managerFee = managerFee;
        uint128 feesToManager0;
        uint128 feesToManager1;
        if (_managerFee > 0) {
            feesToManager0 = feesToVault0 * _managerFee / 1e6;
            feesToManager1 = feesToVault1 * _managerFee / 1e6;
            accruedManagerFees0 += uint104(feesToManager0);
            accruedManagerFees1 += uint104(feesToManager1);
        }
        feesToVault0 -= feesToProtocol0 + feesToManager0;
        feesToVault1 -= feesToProtocol1 + feesToManager1;
        emit CollectFees(feesToVault0, feesToVault1, feesToProtocol0, feesToProtocol1, feesToManager0, feesToManager1);
    }

    /// @dev Deposits liquidity in a range on the Uniswap pool.
    function _mintLiquidity(int24 tickLower, int24 tickUpper, uint128 liquidity)
        internal
        returns (uint256 amount0, uint256 amount1)
    {
        if (liquidity > 0) {
            (amount0, amount1) = pool.mint(address(this), tickLower, tickUpper, liquidity, "");
        }
    }

    /**
     * @notice Calculates the vault's total holdings of token0 and token1 - in
     * other words, how much of each token the vault would hold if it withdrew
     * all its liquidity from Uniswap.
     */
    function getTotalAmounts() public view override returns (uint256 total0, uint256 total1) {
        (total0, total1) = getTotalAmounts(false);
    }

    function getTotalAmounts(bool roundUp) public view override returns (uint256 total0, uint256 total1) {
        (uint256 wideAmount0, uint256 wideAmount1) = getPositionAmounts(wideLower, wideUpper, roundUp);
        (uint256 baseAmount0, uint256 baseAmount1) = getPositionAmounts(baseLower, baseUpper, roundUp);
        (uint256 limitAmount0, uint256 limitAmount1) = getPositionAmounts(limitLower, limitUpper, roundUp);
        total0 = getBalance0() + wideAmount0 + baseAmount0 + limitAmount0;
        total1 = getBalance1() + wideAmount1 + baseAmount1 + limitAmount1;
    }

    /**
     * @notice Amounts of token0 and token1 held in vault's position. Includes
     * owed fees but excludes the proportion of fees that will be paid to the
     * protocol. Doesn't include fees accrued since last poke.
     */
    function getPositionAmounts(int24 tickLower, int24 tickUpper, bool roundUp)
        public
        view
        returns (uint256 amount0, uint256 amount1)
    {
        (uint128 liquidity,,, uint128 tokensOwed0, uint128 tokensOwed1) = _position(tickLower, tickUpper);
        (amount0, amount1) = _amountsForLiquidity(tickLower, tickUpper, liquidity, roundUp);

        // Subtract protocol and manager fees
        uint128 managerFees0;
        uint128 managerFees1;
        uint24 _managerFee = managerFee;
        if (_managerFee > 0) {
            managerFees0 = tokensOwed0 * _managerFee / 1e6;
            managerFees1 = tokensOwed1 * _managerFee / 1e6;
        }
        uint24 _protocolFee = protocolFee;
        uint128 protocolFees0 = tokensOwed0 * _protocolFee / 1e6;
        uint128 protocolFees1 = tokensOwed1 * _protocolFee / 1e6;

        amount0 += tokensOwed0 - protocolFees0 - managerFees0;
        amount1 += tokensOwed1 - protocolFees1 - managerFees1;
    }

    /**
     * @notice Balance of token0 in vault not used in any position.
     */
    function getBalance0() public view override returns (uint256) {
        return token0.balanceOf(address(this)) - accruedProtocolFees0 - accruedManagerFees0;
    }

    /**
     * @notice Balance of token1 in vault not used in any position.
     */
    function getBalance1() public view override returns (uint256) {
        return token1.balanceOf(address(this)) - accruedProtocolFees1 - accruedManagerFees1;
    }

    /// @dev Wrapper around `IUniswapV3Pool.positions()`.
    function _position(int24 tickLower, int24 tickUpper)
        internal
        view
        returns (uint128, uint256, uint256, uint128, uint128)
    {
        bytes32 positionKey = PositionKey.compute(address(this), tickLower, tickUpper);
        return pool.positions(positionKey);
    }

    /// @dev Wrapper around `LiquidityAmounts.getAmountsForLiquidity()`.
    function _amountsForLiquidity(int24 tickLower, int24 tickUpper, uint128 liquidity, bool roundUp)
        internal
        view
        returns (uint256, uint256)
    {
        (uint160 sqrtRatioX96,,,,,,) = pool.slot0();
        return LiquidityAmounts.getAmountsForLiquidity(
            sqrtRatioX96,
            TickMath.getSqrtRatioAtTick(tickLower),
            TickMath.getSqrtRatioAtTick(tickUpper),
            liquidity,
            roundUp
        );
    }

    /// @dev Wrapper around `LiquidityAmounts.getLiquidityForAmounts()`.
    function _liquidityForAmounts(
        int24 tickLower,
        int24 tickUpper,
        uint256 amount0,
        uint256 amount1,
        uint160 sqrtRatioX96
    ) internal pure returns (uint128) {
        return LiquidityAmounts.getLiquidityForAmounts(
            sqrtRatioX96,
            TickMath.getSqrtRatioAtTick(tickLower),
            TickMath.getSqrtRatioAtTick(tickUpper),
            amount0,
            amount1
        );
    }

    /// @dev Casts uint256 to uint128 with overflow check.
    function _toUint128(uint256 x) internal pure returns (uint128) {
        assert(x <= type(uint128).max);
        return uint128(x);
    }

    /// @dev Callback for Uniswap V3 pool.
    function uniswapV3MintCallback(uint256 amount0, uint256 amount1, bytes calldata data) external override {
        require(msg.sender == address(pool));
        if (amount0 > 0) token0.safeTransfer(msg.sender, amount0);
        if (amount1 > 0) token1.safeTransfer(msg.sender, amount1);
    }

    /// @dev Callback for Uniswap V3 pool.
    function uniswapV3SwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata data) external override {
        require(msg.sender == address(pool));
        if (amount0Delta > 0) token0.safeTransfer(msg.sender, uint256(amount0Delta));
        if (amount1Delta > 0) token1.safeTransfer(msg.sender, uint256(amount1Delta));
    }

    /**
     * @notice Used to collect accumulated protocol fees.
     */
    function collectProtocol(address to) external {
        require(msg.sender == factory.governance(), "governance");
        uint256 _accruedProtocolFees0 = accruedProtocolFees0;
        uint256 _accruedProtocolFees1 = accruedProtocolFees1;
        accruedProtocolFees0 = 0;
        accruedProtocolFees1 = 0;
        if (_accruedProtocolFees0 > 0) token0.safeTransfer(to, _accruedProtocolFees0);
        if (_accruedProtocolFees1 > 0) token1.safeTransfer(to, _accruedProtocolFees1);
        emit CollectProtocol(_accruedProtocolFees0, _accruedProtocolFees1);
    }

    /**
     * @notice Change the protocol fee charged on pool fees earned from
     * Uniswap, expressed as multiple of 1e-6. Fee is hard capped at 25%.
     */
    function setProtocolFee(uint24 _pendingProtocolFee) external {
        require(msg.sender == factory.governance(), "governance");
        require(_pendingProtocolFee <= 25e4, "protocolFee must be <= 250000");
        pendingProtocolFee = _pendingProtocolFee;
        emit UpdateProtocolFee(_pendingProtocolFee);
    }

    /*
     * @notice Used to collect accumulated manager fees.
     */
    function collectManager(address to) external onlyManager {
        uint256 _accruedManagerFees0 = accruedManagerFees0;
        uint256 _accruedManagerFees1 = accruedManagerFees1;
        accruedManagerFees0 = 0;
        accruedManagerFees1 = 0;
        if (_accruedManagerFees0 > 0) token0.safeTransfer(to, _accruedManagerFees0);
        if (_accruedManagerFees1 > 0) token1.safeTransfer(to, _accruedManagerFees1);
        emit CollectManager(_accruedManagerFees0, _accruedManagerFees1);
    }

    /**
     * @notice Removes tokens accidentally sent to this vault.
     */
    function sweep(IERC20 token, uint256 amount, address to) external onlyManager {
        require(token != token0 && token != token1, "token");
        token.safeTransfer(to, amount);
    }

    function setBaseThreshold(int24 _baseThreshold) external onlyManager {
        require(_baseThreshold != wideThreshold, "baseThreshold must be != wideThreshold");
        _checkThreshold(_baseThreshold, tickSpacing);
        baseThreshold = _baseThreshold;
        emit UpdateBaseThreshold(_baseThreshold);
    }

    function setLimitThreshold(int24 _limitThreshold) external onlyManager {
        _checkThreshold(_limitThreshold, tickSpacing);
        limitThreshold = _limitThreshold;
        emit UpdateLimitThreshold(_limitThreshold);
    }

    function setWideRangeWeight(uint24 _wideRangeWeight) external onlyManager {
        require(_wideRangeWeight <= 1e6, "wideRangeWeight must be <= 1e6");
        wideRangeWeight = _wideRangeWeight;
        emit UpdateWideRangeWeight(_wideRangeWeight);
    }

    function setWideThreshold(int24 _wideThreshold) external onlyManager {
        require(_wideThreshold != baseThreshold, "wideThreshold must be != baseThreshold");
        _checkThreshold(_wideThreshold, tickSpacing);
        wideThreshold = _wideThreshold;
        emit UpdateWideThreshold(_wideThreshold);
    }

    function setPeriod(uint32 _period) external onlyManager {
        period = _period;
        emit UpdatePeriod(_period);
    }

    function setMinTickMove(int24 _minTickMove) external onlyManager {
        require(_minTickMove >= 0, "minTickMove must be >= 0");
        minTickMove = _minTickMove;
        emit UpdateMinTickMove(_minTickMove);
    }

    function setMaxTwapDeviation(int24 _maxTwapDeviation) external onlyManager {
        require(_maxTwapDeviation >= 0, "maxTwapDeviation must be >= 0");
        maxTwapDeviation = _maxTwapDeviation;
        emit UpdateMaxTwapDeviation(_maxTwapDeviation);
    }

    function setTwapDuration(uint32 _twapDuration) external onlyManager {
        require(_twapDuration > 0, "twapDuration must be > 0");
        twapDuration = _twapDuration;
        emit UpdateTwapDuration(_twapDuration);
    }

    /**
     * @notice Used to change deposit cap for a guarded launch or to ensure
     * vault doesn't grow too large relative to the pool. Cap is on total
     * supply rather than amounts of token0 and token1 as those amounts
     * fluctuate naturally over time.
     */
    function setMaxTotalSupply(uint256 _maxTotalSupply) external onlyManager {
        maxTotalSupply = _maxTotalSupply;
        emit UpdateMaxTotalSupply(_maxTotalSupply);
    }

    /**
     * @notice Removes liquidity in case of emergency.
     */
    function emergencyBurn(int24 tickLower, int24 tickUpper, uint128 liquidity) external onlyManager {
        pool.burn(tickLower, tickUpper, liquidity);
        pool.collect(address(this), tickLower, tickUpper, type(uint128).max, type(uint128).max);
    }

    /**
     * @notice Manager address is not updated until the new manager
     * address has called `acceptManager()` to accept this responsibility.
     */
    function setManager(address _manager) external onlyManager {
        pendingManager = _manager;
        emit UpdatePendingManager(_manager);
    }

    function setDepositDelegate(address _depositDelegate) external onlyManager {
        depositDelegate = _depositDelegate;
        emit UpdateDepositDelegate(_depositDelegate);
    }

    function setRebalanceDelegate(address _rebalanceDelegate) external onlyManager {
        rebalanceDelegate = _rebalanceDelegate;
        emit UpdateRebalanceDelegate(_rebalanceDelegate);
    }

    /**
     * @notice Change the manager fee charged on pool fees earned from
     * Uniswap, expressed as multiple of 1e-6. Fee is hard capped at 20%.
     */
    function setManagerFee(uint24 _pendingManagerFee) external onlyManager {
        require(_pendingManagerFee <= HUNDRED_PERCENT, "managerFee must be <= 100%");
        pendingManagerFee = _pendingManagerFee;
        emit UpdateManagerFee(_pendingManagerFee);
    }

    /**
     * @notice `setManager()` should be called by the existing manager
     * address prior to calling this function.
     */
    function acceptManager() external {
        if (pendingManager == address(0) && msg.sender == manager) {
            manager = address(0);
            emit UpdateManager(address(0));
        } else {
            require(msg.sender == pendingManager, "pendingManager");
            manager = msg.sender;
            emit UpdateManager(msg.sender);
        }
    }

    modifier onlyManager() {
        require(msg.sender == manager, "manager");
        _;
    }
}
