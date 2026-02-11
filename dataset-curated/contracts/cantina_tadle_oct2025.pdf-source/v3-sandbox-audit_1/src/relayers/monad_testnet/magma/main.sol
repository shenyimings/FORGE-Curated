// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title IMagmaStakeManager Interface
 * @dev Interface for interacting with Magma protocol's staking functions
 * @notice Defines core staking operations for MON tokens
 */
interface IMagmaStakeManager {
    /**
     * @dev Deposits MON tokens into the staking contract
     * @param _referralId Referral ID for the deposit (0 for no referral)
     */
    function depositMon(uint256 _referralId) external payable;

    /**
     * @dev Withdraws staked MON tokens
     * @param amount Amount of MON tokens to withdraw
     */
    function withdrawMon(uint256 amount) external;
}

/**
 * @title MagmaResolver
 * @dev Contract for handling Magma protocol staking operations
 * @notice Provides functionality for MON staking and unstaking with gMON tokens
 */
contract MagmaResolver {
    using SafeERC20 for IERC20;

    // ============ Storage ============
    /// @dev Reference to the Magma staking manager contract
    IMagmaStakeManager public immutable MAGMA_STAKE_MANAGER;
    /// @dev Address of the gMON token contract
    address public immutable gMON;

    // ============ Events ============
    /// @dev Emitted when token approval is granted
    event TokenApproval(address indexed token, uint256 amount);

    /**
     * @dev Initializes the contract with required addresses
     * @param _magmaStakeManager Address of the Magma staking manager contract
     * @param _gMON Address of the gMON token contract
     */
    constructor(address _magmaStakeManager, address _gMON) {
        require(_magmaStakeManager != address(0), "Invalid Magma address");
        require(_gMON != address(0), "Invalid gMON address");

        MAGMA_STAKE_MANAGER = IMagmaStakeManager(_magmaStakeManager);
        gMON = _gMON;
    }

    /**
     * @dev Deposits MON tokens and receives gMON in return
     * @notice Stakes MON tokens in the Magma protocol with no referral
     * @param assets Amount of MON to deposit
     * @return _eventName Name of the event to be logged
     * @return _eventParam Encoded event parameters
     */
    function depositMon(uint256 assets) external returns (string memory _eventName, bytes memory _eventParam) {
        require(address(this).balance >= assets, "Insufficient MON balance");

        uint256 balanceBefore = IERC20(gMON).balanceOf(address(this));
        MAGMA_STAKE_MANAGER.depositMon{value: assets}(0);
        uint256 balanceAfter = IERC20(gMON).balanceOf(address(this));
        uint256 amountOut = balanceAfter - balanceBefore;

        _eventName = "LogDepositMon(address,uint256,uint256)";
        _eventParam = abi.encode(address(this), assets, amountOut);
    }

    /**
     * @dev Withdraws MON tokens by unstaking gMON
     * @notice Unstakes MON tokens from the Magma protocol
     * @param amount Amount of MON to withdraw
     * @return _eventName Name of the event to be logged
     * @return _eventParam Encoded event parameters
     */
    function withdrawMon(uint256 amount) external returns (string memory _eventName, bytes memory _eventParam) {
        uint256 balanceBefore = address(this).balance;
        MAGMA_STAKE_MANAGER.withdrawMon(amount);
        uint256 balanceAfter = address(this).balance;
        uint256 amountOut = balanceAfter - balanceBefore;

        _eventName = "LogWithdrawMon(address,uint256)";
        _eventParam = abi.encode(address(this), amountOut);
    }

    /// @dev Required to receive MON tokens
    receive() external payable {}
}

/**
 * @title ConnectV1Magma
 * @dev Connector implementation for Magma protocol v1
 * @notice Entry point for Magma protocol interactions
 */
contract ConnectV1Magma is MagmaResolver {
    /// @dev Version identifier for the connector
    string public constant name = "Magma-v1.0.0";

    constructor(address _magmaStakeManager, address _gMON) MagmaResolver(_magmaStakeManager, _gMON) {}
}
