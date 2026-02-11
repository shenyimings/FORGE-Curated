// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Stores} from "../implementation/Stores.sol";
import {TokenHelper, TokenInterface} from "../../../libraries/TokenHelper.sol";

/**
 * @title IAmbientFinance
 * @notice Interface for interacting with Ambient Finance protocol
 * @dev Provides access to the main user command function
 */
interface IAmbientFinance {
    /// @notice Execute a user command on the Ambient Finance protocol
    /// @param callpath Protocol operation identifier
    /// @param cmd Encoded command data
    /// @return Response data from the protocol
    function userCmd(
        uint16 callpath,
        bytes calldata cmd
    ) external payable returns (bytes memory);
}

/**
 * @title AmbientFinanceResolver
 * @author Tadle Team
 * @notice Contract for interacting with Ambient Finance protocol
 * @dev Handles liquidity operations, pool management, and trading
 * @custom:security Implements token approval management and validation
 */
contract AmbientFinanceResolver is Stores {
    /// @dev Ambient Finance protocol contract address
    /// @notice Immutable reference to the main protocol contract
    address public immutable ambientFinance;

    /// @dev Native token address (ETH)
    /// @notice Standard representation for native ETH in the protocol
    address public constant NATIVE_TOKEN = address(0);

    /// @dev Command identifiers for Ambient Finance operations
    /// @notice Protocol-specific operation codes
    uint256 public constant REMOVE_LIQUIDITY = 2;
    uint256 public constant HARVEST = 5;
    uint256 public constant SWAP = 3;
    uint256 public constant CREATE_POOL = 71;

    /**
     * @dev Initializes the contract with Ambient Finance address
     * @param _ambientFinance Address of Ambient Finance protocol
     * @param _tadleMemory Address of storage contract
     * @notice Sets up the resolver with required protocol contracts
     * @custom:validation Inherits storage validation from Stores contract
     */
    constructor(
        address _ambientFinance,
        address _tadleMemory
    ) Stores(_tadleMemory) {
        ambientFinance = _ambientFinance;
    }

    /**
     * @dev Creates a new liquidity pool
     * @param callPath Protocol operation identifier
     * @param base Base token address
     * @param quote Quote token address
     * @param poolIndex Index of the pool
     * @param price Initial pool price
     * @param value ETH value to send with the transaction
     * @return _eventName Event name for logging
     * @return _eventParam Encoded event parameters
     * @notice Creates a new trading pool with specified parameters
     * @custom:validation Automatically approves tokens for future operations
     */
    function createPool(
        uint16 callPath,
        address base,
        address quote,
        uint256 poolIndex,
        uint128 price,
        uint256 value
    ) external returns (string memory _eventName, bytes memory _eventParam) {
        // Pre-approve tokens for future operations
        approve(base);
        approve(quote);

        // Encode pool creation parameters
        bytes memory cmd = abi.encode(
            CREATE_POOL,
            base,
            quote,
            poolIndex,
            price
        );

        // Execute pool creation command and get response
        _executeCommand(callPath, cmd, value);

        // Return standardized event data
        _eventName = "LogCreatePool(address,address,uint256,uint128)";
        _eventParam = abi.encode(base, quote, poolIndex, price);
    }

    /**
     * @dev Adds liquidity to a pool
     * @param callPath Protocol operation identifier
     * @param operation Specific liquidity operation type
     * @param base Base token address
     * @param quote Quote token address
     * @param poolIndex Index of the pool
     * @param bidTick Lower price tick
     * @param askTick Upper price tick
     * @param liq Amount of liquidity to add
     * @param limitLower Lower limit for position
     * @param limitHigher Upper limit for position
     * @return _eventName Event name for logging
     * @return _eventParam Encoded event parameters
     * @notice Adds liquidity to an existing pool within specified price range
     * @custom:validation Automatically approves tokens before operation
     */
    function addLiquidity(
        uint16 callPath,
        uint256 operation,
        address base,
        address quote,
        uint256 poolIndex,
        int24 bidTick,
        int24 askTick,
        uint128 liq,
        uint128 limitLower,
        uint128 limitHigher
    ) external returns (string memory _eventName, bytes memory _eventParam) {
        // Approve tokens before adding liquidity
        approve(base);
        approve(quote);

        // Encode command parameters
        bytes memory cmd = _encodeLiquidityCommand(
            operation,
            base,
            quote,
            poolIndex,
            bidTick,
            askTick,
            liq,
            limitLower,
            limitHigher
        );

        // Execute command with or without ETH value
        _executeCommand(callPath, cmd, base == NATIVE_TOKEN ? liq : 0);

        // Return event data
        _eventName = "LogAddLiquidity(address,address,address,uint256,int24,int24,uint128)";
        _eventParam = abi.encode(
            address(this),
            base,
            quote,
            poolIndex,
            bidTick,
            askTick,
            liq
        );
    }

    /**
     * @dev Internal helper to encode liquidity command parameters
     * @param operation Type of liquidity operation
     * @param base Base token address
     * @param quote Quote token address
     * @param poolIndex Pool identifier
     * @param bidTick Lower price tick
     * @param askTick Upper price tick
     * @param liq Liquidity amount
     * @param limitLower Lower position limit
     * @param limitHigher Upper position limit
     * @return Encoded command data for protocol
     * @notice Standardizes parameter encoding for liquidity operations
     */
    function _encodeLiquidityCommand(
        uint256 operation,
        address base,
        address quote,
        uint256 poolIndex,
        int24 bidTick,
        int24 askTick,
        uint128 liq,
        uint128 limitLower,
        uint128 limitHigher
    ) internal pure returns (bytes memory) {
        return
            abi.encode(
                operation,
                base,
                quote,
                poolIndex,
                bidTick,
                askTick,
                liq,
                limitLower,
                limitHigher,
                uint8(0),
                address(0)
            );
    }

    /**
     * @dev Internal helper to execute Ambient Finance commands
     * @param callPath Protocol operation identifier
     * @param cmd Encoded command data
     * @param value ETH value to send with the command
     * @return res Response data from the protocol
     * @notice Handles both payable and non-payable command execution
     * @custom:gas-optimization Conditionally sends ETH only when needed
     */
    function _executeCommand(
        uint16 callPath,
        bytes memory cmd,
        uint256 value
    ) internal returns (bytes memory res) {
        if (value > 0) {
            res = IAmbientFinance(ambientFinance).userCmd{value: value}(
                callPath,
                cmd
            );
        } else {
            res = IAmbientFinance(ambientFinance).userCmd(callPath, cmd);
        }
    }

    /**
     * @dev Removes liquidity from a pool
     * @param callPath Protocol operation identifier
     * @param base Base token address
     * @param quote Quote token address
     * @param poolIndex Index of the pool
     * @param bidTick Lower price tick
     * @param askTick Upper price tick
     * @param liq Amount of liquidity to remove
     * @param limitLower Lower limit for position
     * @param limitHigher Upper limit for position
     * @return _eventName Event name for logging
     * @return _eventParam Encoded event parameters
     * @notice Removes liquidity from an existing position
     */
    function removeLiquidity(
        uint16 callPath,
        address base,
        address quote,
        uint256 poolIndex,
        int24 bidTick,
        int24 askTick,
        uint128 liq,
        uint128 limitLower,
        uint128 limitHigher
    ) external returns (string memory _eventName, bytes memory _eventParam) {
        bytes memory cmd = _encodeLiquidityCommand(
            REMOVE_LIQUIDITY,
            base,
            quote,
            poolIndex,
            bidTick,
            askTick,
            liq,
            limitLower,
            limitHigher
        );

        // Execute and validate response
        _executeCommand(callPath, cmd, 0);

        // Return event data
        _eventName = "LogRemoveLiquidity(address,address,address,uint256,int24,int24,uint128)";
        _eventParam = abi.encode(
            address(this),
            base,
            quote,
            poolIndex,
            bidTick,
            askTick,
            liq
        );
    }

    /**
     * @dev Harvests rewards from a liquidity position
     * @param callPath Protocol operation identifier
     * @param base Base token address
     * @param quote Quote token address
     * @param poolIndex Index of the pool
     * @param bidTick Lower price tick
     * @param askTick Upper price tick
     * @param liq Position liquidity amount
     * @param limitLower Lower limit for position
     * @param limitHigher Upper limit for position
     * @return _eventName Event name for logging
     * @return _eventParam Encoded event parameters
     * @notice Collects accumulated fees from a liquidity position
     */
    function harvest(
        uint16 callPath,
        address base,
        address quote,
        uint256 poolIndex,
        int24 bidTick,
        int24 askTick,
        uint128 liq,
        uint128 limitLower,
        uint128 limitHigher
    ) external returns (string memory _eventName, bytes memory _eventParam) {
        bytes memory cmd = _encodeLiquidityCommand(
            HARVEST,
            base,
            quote,
            poolIndex,
            bidTick,
            askTick,
            liq,
            limitLower,
            limitHigher
        );

        // Execute and validate response
        _executeCommand(callPath, cmd, 0);

        // Return event data
        _eventName = "LogHarvest(address,address,address,uint256,int24,int24,uint128)";
        _eventParam = abi.encode(
            address(this),
            base,
            quote,
            poolIndex,
            bidTick,
            askTick,
            liq
        );
    }

    /**
     * @dev Executes a trading operation in the specified pool
     * @param callPath Protocol operation identifier
     * @param base Base token address
     * @param quote Quote token address
     * @param poolIndex Index of the pool
     * @param amountIn Amount of token to input
     * @param amountOutMin Minimum amount of output token
     * @param buyBase True if buying base token, false if selling
     * @param getIds Storage ID to retrieve input amount
     * @param setIds Storage ID to store output amount
     * @return _eventName Event name for logging
     * @return _eventParam Encoded event parameters
     * @notice Executes a swap with slippage protection
     * @custom:validation Validates trade direction and amounts
     */
    function buy(
        uint16 callPath,
        address base,
        address quote,
        uint256 poolIndex,
        uint256 amountIn,
        uint256 amountOutMin,
        bool buyBase,
        uint256 getIds,
        uint256 setIds
    ) external returns (string memory _eventName, bytes memory _eventParam) {
        // Get input amount from storage
        amountIn = getUint(getIds, amountIn);

        // Approve input token if not native token
        if (base != NATIVE_TOKEN) {
            approve(base);
        }

        // Encode command parameters
        bytes memory cmd = _encodeTradeCommand(
            base,
            quote,
            poolIndex,
            amountIn,
            amountOutMin,
            buyBase
        );

        // Execute command with ETH value if using native token
        bytes memory res = _executeCommand(
            callPath,
            cmd,
            base == NATIVE_TOKEN ? amountIn : 0
        );

        (int128 baseAmount, int128 quoteAmount) = abi.decode(
            res,
            (int128, int128)
        );

        uint256 amountOut;
        // Convert negative amounts to positive uint256, handling the direction
        if (buyBase) {
            require(
                quoteAmount < 0,
                "AmbientFinanceResolver: invalid quote amount for base purchase"
            );
            amountOut = uint256(uint128(-quoteAmount));
        } else {
            require(
                baseAmount < 0,
                "AmbientFinanceResolver: invalid base amount for quote purchase"
            );
            amountOut = uint256(uint128(-baseAmount));
        }

        setUint(setIds, amountOut);

        // Return event data
        _eventName = "LogTrade(address,address,address,uint256,uint256,uint256,bool)";
        _eventParam = abi.encode(
            address(this),
            base,
            quote,
            poolIndex,
            amountIn,
            amountOut,
            buyBase
        );
    }

    /**
     * @dev Internal helper to encode trade command parameters
     * @param base Base token address
     * @param quote Quote token address
     * @param poolIndex Pool identifier
     * @param amountIn Input amount
     * @param amountOutMin Minimum output amount
     * @param buyBase True if buying base token
     * @return Encoded command data for Ambient Finance protocol
     * @notice Encodes swap parameters with appropriate price limits
     * @custom:security Sets conservative price limits to prevent MEV attacks
     */
    function _encodeTradeCommand(
        address base,
        address quote,
        uint256 poolIndex,
        uint256 amountIn,
        uint256 amountOutMin,
        bool buyBase
    ) internal pure returns (bytes memory) {
        // Calculate price limit based on trade direction
        uint128 priceLimit = buyBase
            ? uint128(21267430153580247136652501917186561137) // Maximum price for buying base
            : uint128(65538); // Minimum price for selling base

        return
            abi.encode(
                base,
                quote,
                poolIndex,
                buyBase, // Trade direction (buy/sell base token)
                buyBase, // Use same quantity denomination as trade direction
                uint128(amountIn),
                uint16(0), // Default pool type
                priceLimit, // Price limit for the trade
                uint128(amountOutMin),
                0 // Reserved for future use
            );
    }

    /**
     * @dev Approves token spending for Ambient Finance
     * @param token Address of token to approve
     * @notice Optimizes gas by only approving when necessary
     * @custom:gas-optimization Checks existing allowance before approval
     * @custom:security Uses maximum allowance for efficiency
     */
    function approve(address token) internal {
        if (token == NATIVE_TOKEN) {
            return;
        }

        // Check current allowance
        uint256 currentAllowance = TokenInterface(token).allowance(
            address(this),
            ambientFinance
        );

        // Only approve if necessary
        if (currentAllowance == 0) {
            TokenHelper.approve(
                TokenInterface(token),
                ambientFinance,
                type(uint256).max
            );
        }
    }
}

/**
 * @title ConnectV1AmbientFinance
 * @author Tadle Team
 * @notice Version 1.0.0 of the Ambient Finance connector
 * @dev Extends AmbientFinanceResolver with version identification
 * @custom:version 1.0.0
 */
contract ConnectV1AmbientFinance is AmbientFinanceResolver {
    /// @dev Version identifier for the connector
    /// @notice Human-readable version string
    string public constant name = "AmbientFinance-v1.0.0";

    /**
     * @dev Initializes the connector with required dependencies
     * @param _ambientFinance Address of Ambient Finance protocol
     * @param _tadleMemory Address of storage contract
     * @notice Sets up the connector with required protocol contracts
     * @custom:initialization Inherits validation from AmbientFinanceResolver
     */
    constructor(
        address _ambientFinance,
        address _tadleMemory
    ) AmbientFinanceResolver(_ambientFinance, _tadleMemory) {}
}
