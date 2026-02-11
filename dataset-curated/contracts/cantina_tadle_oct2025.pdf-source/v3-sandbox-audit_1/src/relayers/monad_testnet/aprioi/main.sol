// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title IAprioi Interface
 * @author Tadle Team
 * @notice Interface for interacting with Aprioi protocol's core functions
 * @dev Extends IERC20 with deposit and redemption functionality
 */
interface IAprioi is IERC20 {
    /// @notice Deposit ETH to receive aprMON tokens
    /// @param assets Amount of ETH to deposit
    /// @param receiver Address to receive aprMON tokens
    function deposit(uint256 assets, address receiver) external payable;

    /// @notice Request to redeem aprMON tokens for ETH
    /// @param shares Amount of aprMON tokens to redeem
    /// @param controller Address to control the redemption
    /// @param owner Address that owns the aprMON tokens
    /// @return requestId Unique identifier for the redemption request
    function requestRedeem(
        uint256 shares,
        address controller,
        address owner
    ) external returns (uint256 requestId);

    /// @notice Complete redemption and receive ETH
    /// @param requestId ID of the redemption request
    /// @param receiver Address to receive ETH
    function redeem(uint256 requestId, address receiver) external;
}

/**
 * @title AprioiResolver
 * @author Tadle Team
 * @notice Contract for handling Aprioi protocol interactions
 * @dev Manages deposits, redemption requests, and withdrawals for aprMON tokens
 * @custom:security Implements balance tracking and validation
 */
contract AprioiResolver {
    using SafeERC20 for IERC20;

    // ============ Storage ============
    /// @dev Address of the Aprioi protocol contract
    /// @notice Immutable reference to the main protocol contract
    address public immutable APRIOI;

    // ============ Events ============
    /// @dev Emitted when tokens are approved for spending
    /// @notice Tracks token approval operations
    event TokenApproval(address indexed token, uint256 amount);

    /**
     * @dev Initialize contract with Aprioi protocol address
     * @param _aprioi Address of Aprioi protocol
     * @notice Sets up the resolver with the Aprioi protocol contract
     * @custom:validation Ensures protocol address is not zero
     */
    constructor(address _aprioi) {
        require(
            _aprioi != address(0),
            "AprioiResolver: protocol address cannot be zero"
        );
        APRIOI = _aprioi;
    }

    /**
     * @dev Deposit ETH to receive aprMON tokens
     * @param assets Amount of ETH to deposit
     * @param receiver Address to receive aprMON tokens (must be this contract)
     * @return _eventName Name of the event to emit
     * @return _eventParam Encoded event parameters
     * @notice Converts ETH to aprMON tokens through the protocol
     * @custom:validation Validates receiver and balance before deposit
     * @custom:security Tracks balance changes to calculate exact output
     */
    function deposit(
        uint256 assets,
        address receiver
    ) external returns (string memory _eventName, bytes memory _eventParam) {
        // Validate inputs
        require(
            receiver == address(this),
            "AprioiResolver: receiver must be this contract"
        );
        require(
            address(this).balance >= assets,
            "AprioiResolver: insufficient ETH balance for deposit"
        );

        // Track token balance changes
        uint256 balanceBefore = IAprioi(APRIOI).balanceOf(receiver);

        // Execute deposit
        IAprioi(APRIOI).deposit{value: assets}(assets, receiver);

        // Calculate received tokens
        uint256 balanceAfter = IAprioi(APRIOI).balanceOf(receiver);
        uint256 amountOut = balanceAfter - balanceBefore;

        _eventName = "LogDeposit(address,uint256,uint256)";
        _eventParam = abi.encode(receiver, assets, amountOut);
    }

    /**
     * @dev Request to redeem aprMON tokens for ETH
     * @param shares Amount of aprMON tokens to redeem
     * @param controller Address to control the redemption (must be this contract)
     * @param owner Address that owns the aprMON tokens (must be this contract)
     * @return _eventName Name of the event to emit
     * @return _eventParam Encoded event parameters
     * @notice Initiates the redemption process for aprMON tokens
     * @custom:validation Ensures controller and owner are this contract
     */
    function requestRedeem(
        uint256 shares,
        address controller,
        address owner
    ) external returns (string memory _eventName, bytes memory _eventParam) {
        // Validate inputs
        require(
            controller == address(this),
            "AprioiResolver: controller must be this contract"
        );
        require(
            owner == address(this),
            "AprioiResolver: owner must be this contract"
        );

        // Submit redemption request
        uint256 requestId = IAprioi(APRIOI).requestRedeem(
            shares,
            controller,
            owner
        );

        _eventName = "LogRequestRedeem(uint256,address,address,uint256)";
        _eventParam = abi.encode(shares, controller, owner, requestId);
    }

    /**
     * @dev Complete redemption and receive ETH
     * @param requestId ID of the redemption request
     * @param receiver Address to receive ETH (must be this contract)
     * @return _eventName Name of the event to emit
     * @return _eventParam Encoded event parameters
     * @notice Completes the redemption process and receives ETH
     * @custom:validation Validates receiver address
     * @custom:security Tracks balance changes to calculate exact output
     */
    function redeem(
        uint256 requestId,
        address receiver
    ) external returns (string memory _eventName, bytes memory _eventParam) {
        // Validate inputs
        require(
            receiver == address(this),
            "AprioiResolver: receiver must be this contract"
        );

        // Track ETH balance changes
        uint256 balanceBefore = address(receiver).balance;

        // Execute redemption
        IAprioi(APRIOI).redeem(requestId, receiver);

        // Calculate received ETH
        uint256 balanceAfter = address(receiver).balance;
        uint256 amountOut = balanceAfter - balanceBefore;

        _eventName = "LogRedeem(uint256,address,uint256)";
        _eventParam = abi.encode(requestId, receiver, amountOut);
    }

    /**
     * @dev Required to receive ETH
     * @notice Allows the contract to receive ETH from deposits and redemptions
     * @custom:payable Essential for protocol interactions
     */
    receive() external payable {}
}

/**
 * @title ConnectV1Aprioi
 * @author Tadle Team
 * @notice Version 1.0.0 of the Aprioi connector
 * @dev Extends AprioiResolver with version identification
 * @custom:version 1.0.0
 */
contract ConnectV1Aprioi is AprioiResolver {
    /// @dev Version identifier for the connector
    /// @notice Human-readable version string
    string public constant name = "Aprioi-v1.0.0";

    /**
     * @dev Constructor to initialize the Aprioi connector
     * @param _aprioi Address of the Aprioi protocol
     * @notice Sets up the connector with the required protocol contract
     * @custom:initialization Inherits validation from AprioiResolver
     */
    constructor(address _aprioi) AprioiResolver(_aprioi) {}
}
