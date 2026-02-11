// SPDX-FileCopyrightText: 2024 Lido <info@lido.fi>
// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {Pausable} from "@openzeppelin/contracts/security/Pausable.sol";

import {Order} from "./Order.sol";
import {AssetRecoverer} from "./AssetRecoverer.sol";
import {IStonks} from "./interfaces/IStonks.sol";
import {IAmountConverter} from "./interfaces/IAmountConverter.sol";
import {IOracleRouter} from "./interfaces/IOracleRouter.sol";

/**
 * @title Stonks Trading Management Contract
 * @dev Centralizes the management of CoW Swap trading orders, interfacing with the Order contract.
 *
 * Features:
 *  - Stores key trading parameters: token pair, margin, price tolerance and order duration in immutable variables.
 *  - Creates a minimum proxy from the Order contract and passes params for individual trades.
 *  - Provides asset recovery functionality.
 *  - Protected against reentrancy on order creation paths.
 *
 * @notice Orchestrates the setup and execution of trades on CoW Swap, utilizing Order contracts for each trade.
 */
contract Stonks is IStonks, AssetRecoverer, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;

    // ==================== Types ====================

    /// @notice Struct containing all initialization parameters for the Stonks contract.
    struct InitParams {
        /// @notice Address of the Lido DAO agent.
        address agent;
        /// @notice Address of the manager authorized to place orders.
        address manager;
        /// @notice Address of the token being sold in trades.
        address tokenFrom;
        /// @notice Address of the token being bought in trades.
        address tokenTo;
        /// @notice Address of the AmountConverter contract used for price calculations.
        address amountConverter;
        /// @notice Address of the Order contract implementation used as a template for cloning.
        address orderSample;
        /// @notice Address of the OracleRouter contract.
        address oracleRouter;
        /// @notice Duration in seconds for which orders remain valid.
        uint256 orderDurationInSeconds;
        /// @notice Margin in basis points subtracted from expected output to account for fees and volatility.
        uint256 marginInBasisPoints;
        /// @notice Price tolerance in basis points allowed for price changes before order becomes invalid.
        uint256 priceToleranceInBasisPoints;
        /// @notice Maximum price improvement allowed in basis points (type(uint256).max = no cap, 0 = strict mode).
        uint256 maxImprovementInBasisPoints;
        /// @notice Whether orders should allow partial fills (useful for rebasable tokens).
        bool allowPartialFill;
    }

    // ==================== Immutables ====================

    /// @notice Address of the AmountConverter contract used for price calculations.
    address public immutable AMOUNT_CONVERTER;
    /// @notice Address of the Order contract implementation used as a template for cloning.
    address public immutable ORDER_SAMPLE;
    /// @notice Address of the token being sold in trades.
    address public immutable TOKEN_FROM;
    /// @notice Address of the token being bought in trades.
    address public immutable TOKEN_TO;
    /// @notice Duration in seconds for which orders remain valid.
    uint256 public immutable ORDER_DURATION_IN_SECONDS;
    /// @notice Margin in basis points subtracted from expected output to account for fees and volatility.
    uint256 public immutable MARGIN_IN_BASIS_POINTS;
    /// @notice Complement of margin in basis points (10000 - MARGIN_IN_BASIS_POINTS).
    uint256 public immutable MARGIN_DIFFERENCE_IN_BASIS_POINTS;
    /// @notice Price tolerance in basis points allowed for price changes before order becomes invalid.
    uint256 public immutable PRICE_TOLERANCE_IN_BASIS_POINTS;
    /// @notice Maximum price improvement allowed in basis points (type(uint256).max = no cap, 0 = strict mode).
    uint256 public immutable MAX_IMPROVEMENT_IN_BASIS_POINTS;
    /// @notice Whether orders should allow partial fills (useful for rebasable tokens).
    bool public immutable ALLOW_PARTIAL_FILL;

    /// @notice Oracle router contract used for quotability checks.
    IOracleRouter public immutable ORACLE_ROUTER;

    // ==================== Constants ====================

    /// @notice Maximum basis points value (100%).
    uint16 private constant MAX_BASIS_POINTS = 1e4;
    /// @notice Upper limit for basis points parameters (10%).
    uint16 private constant BASIS_POINTS_PARAMETERS_LIMIT = 1e3;
    /// @notice Minimum possible balance for placing an order.
    uint256 private constant MIN_POSSIBLE_BALANCE = 10;
    /// @notice Minimum possible order duration in seconds.
    uint256 private constant MIN_POSSIBLE_ORDER_DURATION_IN_SECONDS = 1 minutes;
    /// @notice Maximum possible order duration in seconds.
    uint256 private constant MAX_POSSIBLE_ORDER_DURATION_IN_SECONDS = 1 days;

    // ==================== Events ====================

    event AmountConverterSet(address amountConverter);
    event OrderSampleSet(address orderSample);
    event TokenFromSet(address tokenFrom);
    event TokenToSet(address tokenTo);
    event OrderDurationInSecondsSet(uint256 orderDurationInSeconds);
    event MarginInBasisPointsSet(uint256 marginInBasisPoints);
    event PriceToleranceInBasisPointsSet(uint256 priceToleranceInBasisPoints);
    event OrderContractCreated(address indexed orderContract, uint256 minBuyAmount);
    event OracleRouterSet(address oracleRouter);
    event SignaturesPaused(address indexed by);
    event SignaturesUnpaused(address indexed by);
    event KillEngaged(address indexed by);

    // ==================== Errors ====================

    error InvalidManagerAddress(address manager);
    error InvalidTokenFromAddress(address tokenFrom);
    error InvalidTokenToAddress(address tokenTo);
    error InvalidAmountConverterAddress(address amountConverter);
    error InvalidOrderSampleAddress(address orderSample);
    error InvalidOracleRouterAddress(address oracleRouter);
    error TokensCannotBeSame();
    error InvalidOrderDuration(uint256 min, uint256 max, uint256 received);
    error MarginOverflowsAllowedLimit(uint256 limit, uint256 received);
    error PriceToleranceOverflowsAllowedLimit(uint256 limit, uint256 received);
    error MinimumPossibleBalanceNotMet(uint256 min, uint256 received);
    error InvalidAmount(uint256 amount);
    error SellAmountExceedsBalance(uint256 available, uint256 requested);
    error StonksKilled();

    // ==================== Emergency State ====================

    bool private _signaturesPaused;
    bool private _killed;

    modifier notKilled() {
        if (_killed) {
            revert StonksKilled();
        }
        _;
    }

    // ==================== Constructor ====================

    /**
     * @notice Initializes the Stonks contract with key trading parameters.
     * @param initParams_ Struct containing all initialization parameters.
     * @dev Stores essential parameters for trade execution in immutable variables, ensuring consistency and security of trades.
     */
    constructor(InitParams memory initParams_) AssetRecoverer(initParams_.agent) {
        _validateAddresses(
            initParams_.manager,
            initParams_.tokenFrom,
            initParams_.tokenTo,
            initParams_.amountConverter,
            initParams_.orderSample,
            initParams_.oracleRouter
        );
        _validateDurations(initParams_.orderDurationInSeconds);
        _validateBps(
            initParams_.marginInBasisPoints,
            initParams_.priceToleranceInBasisPoints,
            initParams_.maxImprovementInBasisPoints
        );

        manager = initParams_.manager;
        ORDER_SAMPLE = initParams_.orderSample;
        AMOUNT_CONVERTER = initParams_.amountConverter;
        TOKEN_FROM = initParams_.tokenFrom;
        TOKEN_TO = initParams_.tokenTo;
        ORDER_DURATION_IN_SECONDS = initParams_.orderDurationInSeconds;
        MARGIN_IN_BASIS_POINTS = initParams_.marginInBasisPoints;

        unchecked {
            MARGIN_DIFFERENCE_IN_BASIS_POINTS = MAX_BASIS_POINTS - MARGIN_IN_BASIS_POINTS;
        }

        PRICE_TOLERANCE_IN_BASIS_POINTS = initParams_.priceToleranceInBasisPoints;
        MAX_IMPROVEMENT_IN_BASIS_POINTS = initParams_.maxImprovementInBasisPoints;
        ALLOW_PARTIAL_FILL = initParams_.allowPartialFill;
        ORACLE_ROUTER = IOracleRouter(initParams_.oracleRouter);

        emit ManagerSet(initParams_.manager);
        emit AmountConverterSet(initParams_.amountConverter);
        emit OrderSampleSet(initParams_.orderSample);
        emit TokenFromSet(initParams_.tokenFrom);
        emit TokenToSet(initParams_.tokenTo);
        emit OrderDurationInSecondsSet(initParams_.orderDurationInSeconds);
        emit MarginInBasisPointsSet(initParams_.marginInBasisPoints);
        emit PriceToleranceInBasisPointsSet(initParams_.priceToleranceInBasisPoints);
        emit OracleRouterSet(initParams_.oracleRouter);
    }

    // ==================== External Functions ====================

    /**
     * @notice Initiates a new trading order by creating an Order contract clone with the current token balance.
     * @dev Transfers the tokenFrom balance to the new Order instance and initializes it with the Stonks' manager settings for execution.
     *      Protected against reentrancy attacks.
     * @param minBuyAmount_ Minimum amount of tokenTo to be received as a result of the trade.
     * @return Address of the newly created Order contract.
     */
    function placeOrder(
        uint256 minBuyAmount_
    ) external nonReentrant onlyAgentOrManager notKilled whenNotPaused returns (address) {
        uint256 balance = IERC20(TOKEN_FROM).balanceOf(address(this));

        return _placeOrder(balance, minBuyAmount_, balance);
    }

    /**
     * @notice Initiates a new trading order by creating an Order contract clone with the specified sell amount.
     * @dev Protected against reentrancy attacks.
     * @param sellAmount_ Amount of `TOKEN_FROM` to transfer into the Order for this trade.
     * @param minBuyAmount_ Minimum acceptable `TOKEN_TO` received.
     */
    function placeOrderWithAmount(
        uint256 sellAmount_,
        uint256 minBuyAmount_
    ) external nonReentrant onlyAgentOrManager notKilled whenNotPaused returns (address) {
        uint256 balance = IERC20(TOKEN_FROM).balanceOf(address(this));

        return _placeOrder(sellAmount_, minBuyAmount_, balance);
    }

    // ==================== External View Functions ====================

    /**
     * @notice Estimates trade output based on current input token balance.
     * @dev Uses current balance for output estimation via `estimateTradeOutput`.
     * @return Estimated trade output amount.
     */
    function estimateTradeOutputFromCurrentBalance() external view returns (uint256) {
        uint256 balance = IERC20(TOKEN_FROM).balanceOf(address(this));

        return estimateTradeOutput(balance);
    }

    /**
     * @notice Returns trading parameters from Stonks for use in the Order contract.
     * @dev Facilitates gas efficiency by allowing Order to access existing parameters in Stonks without redundant storage.
     * @return Tuple of order parameters (tokenFrom, tokenTo, orderDurationInSeconds).
     */
    function getOrderParameters() external view returns (address, address, uint256) {
        return (TOKEN_FROM, TOKEN_TO, ORDER_DURATION_IN_SECONDS);
    }

    /**
     * @notice Returns price tolerance parameter from Stonks for use in the Order contract.
     * @dev Facilitates gas efficiency by allowing Order to access existing parameters in Stonks without redundant storage.
     * @return Price tolerance in basis points.
     */
    function getPriceTolerance() external view returns (uint256) {
        return PRICE_TOLERANCE_IN_BASIS_POINTS;
    }

    /**
     * @notice Returns maximum price improvement parameter from Stonks for use in the Order contract.
     * @dev Facilitates gas efficiency by allowing Order to access existing parameters in Stonks without redundant storage.
     * @return Maximum improvement in basis points (type(uint256).max = no cap, 0 = strict mode).
     */
    function getMaxImprovementBps() external view returns (uint256) {
        return MAX_IMPROVEMENT_IN_BASIS_POINTS;
    }

    /**
     * @notice Asserts that a price path exists for the pair; used by Order to fail fast.
     * @dev Reads via OracleRouter which reverts if a token is not configured or the bridge is missing.
     */
    function assertQuotable() external view {
        ORACLE_ROUTER.getUsdPrices(TOKEN_FROM, TOKEN_TO); // reverts internally if unquotable
    }

    // ==================== Emergency Control Views ====================

    function areSignaturesPaused() external view returns (bool) {
        return _signaturesPaused;
    }

    function isCreationPaused() external view returns (bool) {
        return paused();
    }

    function isKilled() external view returns (bool) {
        return _killed;
    }

    // ==================== Emergency Admin Functions ====================

    /**
     * @notice Pause order creation. Does not affect recovery or existing orders' validation.
     */
    function pauseCreation() external onlyAgentOrManager {
        _pause();
    }

    /**
     * @notice Unpause order creation. No effect if killSwitch was engaged.
     */
    function unpauseCreation() external onlyAgentOrManager {
        _unpause();
    }

    /**
     * @notice Pause signatures globally (halts fills).
     */
    function pauseSignatures() external onlyAgentOrManager {
        if (_signaturesPaused) {
            return;
        }

        _signaturesPaused = true;

        emit SignaturesPaused(msg.sender);
    }

    /**
     * @notice Unpause signatures globally (resume fills).
     */
    function unpauseSignatures() external onlyAgentOrManager {
        if (!_signaturesPaused) {
            return;
        }

        _signaturesPaused = false;

        emit SignaturesUnpaused(msg.sender);
    }

    /**
     * @notice Engage irreversible kill switch: pauses creation, pauses signatures, marks killed.
     */
    function killSwitch() external onlyAgentOrManager {
        // Set signatures paused if not already, emit telemetry when it changes
        if (!_signaturesPaused) {
            _signaturesPaused = true;

            emit SignaturesPaused(msg.sender);
        }
        // Pause creation if not already paused
        if (!paused()) {
            _pause();
        }

        // Mark killed (irreversible)
        if (!_killed) {
            _killed = true;
        }

        emit KillEngaged(msg.sender);
    }

    // ==================== Public Functions ====================

    /**
     * @notice Estimates output amount for a given trade input amount.
     * @param amount_ Input token amount for trade.
     * @dev Uses token amount converter for output estimation.
     * @return estimatedTradeOutput Estimated trade output amount.
     * Subtracts the amount that corresponds to the margin parameter from the result obtained from the amount converter.
     *
     * |       estimatedTradeOutput        expectedBuyAmount
     * |  --------------*--------------------------*-----------------> amount
     * |                 <-------- margin -------->
     *
     * where:
     *      expectedBuyAmount - amount received from the amountConverter based on Chainlink price feed.
     *      margin - % taken from the expectedBuyAmount includes CoW Protocol fees and maximum accepted losses
     *               to handle market volatility.
     *      estimatedTradeOutput - expectedBuyAmount subtracted by the margin that is expected to be result of the trade.
     */
    function estimateTradeOutput(
        uint256 amount_
    ) public view returns (uint256 estimatedTradeOutput) {
        if (amount_ == 0) {
            revert InvalidAmount(amount_);
        }

        uint256 expectedBuyAmount = IAmountConverter(AMOUNT_CONVERTER).getExpectedOut(
            TOKEN_FROM,
            TOKEN_TO,
            amount_
        );

        estimatedTradeOutput =
            (expectedBuyAmount * MARGIN_DIFFERENCE_IN_BASIS_POINTS) /
            MAX_BASIS_POINTS;
    }

    // ==================== Internal Functions ====================

    function _placeOrder(
        uint256 sellAmount_,
        uint256 minBuyAmount_,
        uint256 availableBalance_
    ) internal returns (address) {
        if (minBuyAmount_ == 0) {
            revert InvalidAmount(minBuyAmount_);
        }

        if (sellAmount_ < MIN_POSSIBLE_BALANCE) {
            revert MinimumPossibleBalanceNotMet(MIN_POSSIBLE_BALANCE, sellAmount_);
        }

        if (sellAmount_ > availableBalance_) {
            revert SellAmountExceedsBalance(availableBalance_, sellAmount_);
        }

        Order orderCopy = Order(Clones.clone(ORDER_SAMPLE));

        IERC20(TOKEN_FROM).safeTransfer(address(orderCopy), sellAmount_);
        orderCopy.initialize(minBuyAmount_, manager);

        emit OrderContractCreated(address(orderCopy), minBuyAmount_);

        return address(orderCopy);
    }

    // ==================== Private Functions ====================

    function _validateAddresses(
        address manager_,
        address tokenFrom_,
        address tokenTo_,
        address amountConverter_,
        address orderSample_,
        address oracleRouter_
    ) private pure {
        if (manager_ == address(0)) {
            revert InvalidManagerAddress(manager_);
        }

        if (tokenFrom_ == address(0)) {
            revert InvalidTokenFromAddress(tokenFrom_);
        }

        if (tokenTo_ == address(0)) {
            revert InvalidTokenToAddress(tokenTo_);
        }

        if (tokenFrom_ == tokenTo_) {
            revert TokensCannotBeSame();
        }

        if (amountConverter_ == address(0)) {
            revert InvalidAmountConverterAddress(amountConverter_);
        }

        if (orderSample_ == address(0)) {
            revert InvalidOrderSampleAddress(orderSample_);
        }

        if (oracleRouter_ == address(0)) {
            revert InvalidOracleRouterAddress(oracleRouter_);
        }
    }

    function _validateDurations(uint256 orderDurationInSeconds_) private pure {
        if (
            orderDurationInSeconds_ > MAX_POSSIBLE_ORDER_DURATION_IN_SECONDS ||
            orderDurationInSeconds_ < MIN_POSSIBLE_ORDER_DURATION_IN_SECONDS
        ) {
            revert InvalidOrderDuration(
                MIN_POSSIBLE_ORDER_DURATION_IN_SECONDS,
                MAX_POSSIBLE_ORDER_DURATION_IN_SECONDS,
                orderDurationInSeconds_
            );
        }
    }

    function _validateBps(
        uint256 marginInBasisPoints_,
        uint256 priceToleranceInBasisPoints_,
        uint256 maxImprovementInBasisPoints_
    ) private pure {
        if (marginInBasisPoints_ > BASIS_POINTS_PARAMETERS_LIMIT) {
            revert MarginOverflowsAllowedLimit(BASIS_POINTS_PARAMETERS_LIMIT, marginInBasisPoints_);
        }

        if (priceToleranceInBasisPoints_ > BASIS_POINTS_PARAMETERS_LIMIT) {
            revert PriceToleranceOverflowsAllowedLimit(
                BASIS_POINTS_PARAMETERS_LIMIT,
                priceToleranceInBasisPoints_
            );
        }

        if (
            maxImprovementInBasisPoints_ != type(uint256).max &&
            maxImprovementInBasisPoints_ > BASIS_POINTS_PARAMETERS_LIMIT
        ) {
            revert MarginOverflowsAllowedLimit(
                BASIS_POINTS_PARAMETERS_LIMIT,
                maxImprovementInBasisPoints_
            );
        }
    }
}
