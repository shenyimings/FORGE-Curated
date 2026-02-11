// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {TokenHelper, TokenInterface} from "../../../libraries/TokenHelper.sol";
import {Stores} from "../implementation/Stores.sol";

/**
 * @title WETHResolver
 * @dev Contract for handling WETH (Wrapped Ether) operations
 * @notice Provides functionality for wrapping and unwrapping ETH
 */
contract WETHResolver is Stores {
    /// @dev Reference to the WETH token contract
    TokenInterface public immutable weth;

    /**
     * @dev Initializes the contract with WETH address
     * @param _weth Address of WETH token contract
     * @param _tadleMemory Address of storage contract
     */
    constructor(address _weth, address _tadleMemory) Stores(_tadleMemory) {
        weth = TokenInterface(_weth);
    }

    /**
     * @dev Deposits ETH to receive WETH
     * @param _amt Amount of ETH to wrap (in wei)
     * @param getId Storage ID to retrieve amount, 0 for direct input
     * @param setId Storage ID to store wrapped amount, 0 to skip storage
     * @return _eventName Event name for logging
     * @return _eventParam Encoded event parameters
     */
    function deposit(uint256 _amt, uint256 getId, uint256 setId)
        external
        returns (string memory _eventName, bytes memory _eventParam)
    {
        // Get amount from storage if ID provided
        uint256 amount = getUint(getId, _amt);
        require(amount > 0, "Invalid deposit amount");

        // Convert ETH to WETH
        TokenHelper.convertEthToWeth(true, weth, amount);

        // Store result if setId provided
        if (setId != 0) {
            setUint(setId, amount);
        }

        // Return event data
        _eventName = "LogDeposit(address,uint256)";
        _eventParam = abi.encode(address(this), amount);
    }

    /**
     * @dev Withdraws ETH by unwrapping WETH
     * @param _amt Amount of WETH to unwrap (in wei)
     * @param getId Storage ID to retrieve amount, 0 for direct input
     * @param setId Storage ID to store unwrapped amount, 0 to skip storage
     * @return _eventName Event name for logging
     * @return _eventParam Encoded event parameters
     */
    function withdraw(uint256 _amt, uint256 getId, uint256 setId)
        external
        returns (string memory _eventName, bytes memory _eventParam)
    {
        // Get amount from storage if ID provided
        uint256 amount = getUint(getId, _amt);
        require(amount > 0, "Invalid withdrawal amount");

        // Check WETH balance
        require(weth.balanceOf(address(this)) >= amount, "Insufficient WETH balance");

        // Convert WETH to ETH
        TokenHelper.convertWethToEth(true, weth, amount);

        // Store result if setId provided
        if (setId != 0) {
            setUint(setId, amount);
        }

        // Return event data
        _eventName = "LogWithdraw(address,uint256)";
        _eventParam = abi.encode(address(this), amount);
    }
}

/**
 * @title ConnectV1WETH
 * @dev Connector implementation for WETH operations
 * @notice Entry point for WETH wrapping and unwrapping
 */
contract ConnectV1WETH is WETHResolver {
    /// @dev Version identifier for the connector
    string public name = "WETH-v1.0.0";

    /**
     * @dev Initializes the connector with required dependencies
     * @param _weth Address of WETH token contract
     * @param _tadleMemory Address of storage contract
     */
    constructor(address _weth, address _tadleMemory) WETHResolver(_weth, _tadleMemory) {}
}
