// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Stores} from "../implementation/Stores.sol";

/**
 * @title INadFun Interface
 * @dev Interface for interacting with NadFun protocol's core functions
 * @notice Provides methods for creating bonding curves and executing protected trades
 */
interface INadFun {
    /**
     * @dev Creates a new bonding curve
     * @param creator Address of the curve creator
     * @param name Name of the curve token
     * @param symbol Symbol of the curve token
     * @param tokenURI URI for token metadata
     * @param amountIn Initial ETH amount for liquidity
     * @param fee Fee percentage (in basis points, 0 for default)
     * @return curve Address of the created curve
     * @return token Address of the curve token
     * @return virtualNative Virtual ETH amount in the curve
     * @return virtualToken Virtual token amount inthe curve
     * @return amountOut Amount of tokens received
     */
    function createCurve(
        address creator,
        string memory name,
        string memory symbol,
        string memory tokenURI,
        uint256 amountIn,
        uint256 fee
    )
        external
        payable
        returns (address curve, address token, uint256 virtualNative, uint256 virtualToken, uint256 amountOut);

    /**
     * @dev Executes a protected ETH to token swap
     * @param amountIn Amount of ETH to swap
     * @param amountOutMin Minimum tokens to receive
     * @param fee Protocol fee amount
     * @param token Token address to receive
     * @param to Recipient address
     * @param deadline Transaction timeout timestamp
     */
    function protectBuy(
        uint256 amountIn,
        uint256 amountOutMin,
        uint256 fee,
        address token,
        address to,
        uint256 deadline
    ) external payable;

    /**
     * @dev Executes a protected token to ETH swap
     * @param amountIn Amount of tokens to swap
     * @param amountOutMin Minimum ETH to receive
     * @param token Token address to swap
     * @param to Recipient address
     * @param deadline Transaction timeout timestamp
     */
    function protectSell(uint256 amountIn, uint256 amountOutMin, address token, address to, uint256 deadline)
        external;
}

/**
 * @title NadFunResolver
 * @dev Base contract for interacting with NadFun protocol
 * @notice Provides functionality for creating bonding curves and executing protected trades
 */
contract NadFunResolver is Stores {
    using SafeERC20 for IERC20;

    /**
     * @dev Creates a new bonding curve with initial liquidity
     * @notice Creates a new bonding curve and corresponding token with initial ETH liquidity
     * @param params Parameters for curve creation including name, symbol, URI, initial amount and fee
     * @return _eventName Name of the event to be logged
     * @return _eventParam Encoded event parameters
     */
    struct CreateCurveParams {
        string name;
        string symbol;
        string tokenURI;
        uint256 amountIn;
        uint256 fee;
    }

    /**
     * @dev Parameters for protected trading operations
     * @param amountIn Amount of tokens to trade (ETH for buy, tokens for sell)
     * @param amountOutMin Minimum amount of tokens to receive after trade
     * @param fee Custom fee rate in basis points (0 for default 1%)
     * @param token Token contract address for the trade
     * @param to Recipient address for the traded tokens
     * @param deadline Transaction expiration timestamp
     * @param getIds Storage ID to retrieve input amount
     * @param setIds Storage ID to store output amount
     */
    struct ProtectParams {
        uint256 amountIn;
        uint256 amountOutMin;
        uint256 fee;
        address token;
        address to;
        uint256 deadline;
        uint256 getIds;
        uint256 setIds;
    }

    // ============ Constants ============
    address public immutable NAD_FUN;
    uint256 public constant EXTRA_VALUE = 0.02 ether;
    uint256 public constant DEFAULT_FEE = 1000; // 1% fee in basis points
    uint256 private constant BASIS_POINTS = 100000;

    // ============ Events ============
    event TokenApproval(address indexed token, uint256 amount);
    event ProtectedSwap(address indexed token, uint256 amountIn, uint256 amountOut, bool isBuy);

    constructor(address _nadFun, address _tadleMemory) Stores(_tadleMemory) {
        require(_nadFun != address(0), "Invalid NadFun address");
        NAD_FUN = _nadFun;
    }

    function createCurve(CreateCurveParams calldata params)
        external
        returns (string memory _eventName, bytes memory _eventParam)
    {
        (address curve, address token, uint256 amountOut, uint256 feeAmount) = _createCurveWithFee(params);
        (_eventName, _eventParam) = _encodeCreateCurveEvent(params, curve, token, amountOut, feeAmount);
    }

    /**
     * @dev Executes a protected ETH to token buy transaction
     * @notice Swaps ETH for tokens with slippage protection and custom fee handling
     * @param params Trading parameters including amounts, token, deadline and storage IDs
     * @return _eventName Name of the event to be logged
     * @return _eventParam Encoded event parameters
     */
    function protectBuy(ProtectParams calldata params)
        external
        returns (string memory _eventName, bytes memory _eventParam)
    {
        require(params.token != address(0), "Invalid token");
        require(params.to == address(this), "Invalid recipient");
        require(params.deadline >= block.timestamp, "Expired deadline");

        uint256 amountIn = getUint(params.getIds, params.amountIn);
        uint256 actualFee = params.fee == 0 ? DEFAULT_FEE : params.fee;
        uint256 feeAmount = (amountIn * actualFee) / BASIS_POINTS;
        uint256 totalAmount = amountIn + feeAmount;

        require(address(this).balance >= totalAmount, "Insufficient ETH balance");

        uint256 balanceBefore = IERC20(params.token).balanceOf(params.to);

        INadFun(NAD_FUN).protectBuy{value: totalAmount}(
            amountIn, params.amountOutMin, feeAmount, params.token, params.to, params.deadline
        );

        uint256 balanceAfter = IERC20(params.token).balanceOf(params.to);
        uint256 amountOut = balanceAfter - balanceBefore;
        require(amountOut >= params.amountOutMin, "Insufficient output amount");

        setUint(params.setIds, amountOut);
        emit ProtectedSwap(params.token, amountIn, amountOut, true);

        _eventName = "LogProtectBuy(address,uint256,uint256)";
        _eventParam = abi.encode(params.token, amountIn, amountOut);
    }

    /**
     * @dev Execute a protected token to ETH sell transaction
     * @notice Swaps tokens for ETH with slippage protection
     * @param params Trading parameters struct
     * @return _eventName Name of the event to emit
     * @return _eventParam Encoded parameters for the event
     */
    function protectSell(ProtectParams calldata params)
        external
        returns (string memory _eventName, bytes memory _eventParam)
    {
        require(params.token != address(0), "Invalid token");
        require(params.to == address(this), "Invalid recipient");
        require(params.deadline >= block.timestamp, "Expired deadline");

        uint256 amountIn = getUint(params.getIds, params.amountIn);
        require(IERC20(params.token).balanceOf(address(this)) >= amountIn, "Insufficient token balance");

        uint256 ethBalanceBefore = address(this).balance;

        _safeApprove(params.token, NAD_FUN, amountIn);
        INadFun(NAD_FUN).protectSell(amountIn, params.amountOutMin, params.token, params.to, params.deadline);

        uint256 ethBalanceAfter = address(this).balance;
        uint256 amountOut = ethBalanceAfter - ethBalanceBefore;
        require(amountOut >= params.amountOutMin, "Insufficient output amount");

        setUint(params.setIds, amountOut);
        emit ProtectedSwap(params.token, amountIn, amountOut, false);

        _eventName = "LogProtectSell(address,uint256,uint256)";
        _eventParam = abi.encode(params.token, amountIn, amountOut);
    }

    /**
     * @dev Internal function to create bonding curve and calculate fees
     * @notice Handles core logic for curve creation including fee calculation and contract calls
     * @param params Parameters for curve creation
     * @return curve Address of the created curve contract
     * @return token Address of the created token contract
     * @return amountOut Amount of tokens minted
     * @return feeAmount Calculated fee amount
     */
    function _createCurveWithFee(CreateCurveParams calldata params)
        internal
        returns (address curve, address token, uint256 amountOut, uint256 feeAmount)
    {
        feeAmount = _calculateFeeAmount(params.amountIn, params.fee);
        uint256 totalAmount = params.amountIn + feeAmount + EXTRA_VALUE;

        require(address(this).balance >= totalAmount, "Insufficient ETH balance");

        (curve, token,,, amountOut) = INadFun(NAD_FUN).createCurve{value: totalAmount}(
            address(this), params.name, params.symbol, params.tokenURI, params.amountIn, feeAmount
        );
    }

    /**
     * @dev Internal function to encode curve creation event
     * @notice Encodes curve creation results into event parameters
     * @param params Original curve creation parameters
     * @param curve Curve contract address
     * @param token Token contract address
     * @param amountOut Amount of tokens minted
     * @param feeAmount Fee amount
     * @return _eventName Name of the event
     * @return _eventParam Encoded event parameters
     */
    function _encodeCreateCurveEvent(
        CreateCurveParams calldata params,
        address curve,
        address token,
        uint256 amountOut,
        uint256 feeAmount
    ) internal view returns (string memory _eventName, bytes memory _eventParam) {
        _eventName = "LogCreateCurve(address,address,address,string,string,string,uint256,uint256,uint256)";
        _eventParam = abi.encode(
            address(this),
            curve,
            token,
            params.name,
            params.symbol,
            params.tokenURI,
            params.amountIn,
            feeAmount,
            amountOut
        );
    }

    /**
     * @dev Internal function to calculate fee amount
     * @notice Calculates fee amount based on input amount and fee rate
     * @param amountIn Input amount for fee calculation
     * @param fee Fee rate in basis points (0 for default)
     * @return Calculated fee amount
     */
    function _calculateFeeAmount(uint256 amountIn, uint256 fee) internal pure returns (uint256) {
        uint256 actualFee = fee == 0 ? DEFAULT_FEE : fee;
        return (amountIn * actualFee) / BASIS_POINTS;
    }

    /**
     * @dev Internal helper for safe token approvals
     * @notice Handles token approvals with retry mechanism for non-standard tokens
     * @param token Token contract address
     * @param spender Address to approve for spending
     * @param amount Amount of tokens to approve
     */
    function _safeApprove(address token, address spender, uint256 amount) internal {
        try IERC20(token).approve(spender, amount) {
            emit TokenApproval(token, amount);
        } catch {
            IERC20(token).approve(spender, 0);
            IERC20(token).approve(spender, amount);
            emit TokenApproval(token, amount);
        }
    }

    receive() external payable {}
}

/**
 * @title ConnectV1NadFun
 * @dev Connector implementation for NadFun protocol
 * @notice Entry point for NadFun protocol interactions with version tracking
 */
contract ConnectV1NadFun is NadFunResolver {
    string public constant name = "NadFun-v1.0.0";

    constructor(address _nadFun, address _tadleMemory) NadFunResolver(_nadFun, _tadleMemory) {}
}
