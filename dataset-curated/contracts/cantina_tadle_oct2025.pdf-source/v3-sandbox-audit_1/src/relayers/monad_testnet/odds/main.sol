// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {TokenHelper, TokenInterface} from "../../../libraries/TokenHelper.sol";

/**
 * @title ITadleOddsMarket
 * @dev Interface for Tadle Odds Market contract
 */
interface ITadleOddsMarket {
    /**
     * @dev Deposits funds into the market
     * @param amount The amount to deposit
     */
    function deposit(uint256 amount) external;

    /**
     * @dev Withdraws funds from the market
     * @param to Recipient address
     * @param amount Amount to withdraw
     * @param timestamp Timestamp for withdrawal
     * @param signature Authorization signature
     */
    function withdraw(address to, uint256 amount, uint256 timestamp, bytes memory signature) external;
}

/**
 * @title TadleOddsResolver
 * @dev Main contract for handling odds market operations
 */
contract TadleOddsResolver {
    // Immutable market contract instance
    ITadleOddsMarket public immutable tadleOddsMarket;
    // Immutable token contract instance
    TokenInterface public immutable monUSD;

    /**
     * @dev Initializes the contract with market and token addresses
     * @param _tadleOddsMarket Address of the odds market contract
     * @param _monUSD Address of the token contract
     */
    constructor(address _tadleOddsMarket, address _monUSD) {
        tadleOddsMarket = ITadleOddsMarket(_tadleOddsMarket);
        monUSD = TokenInterface(_monUSD);
    }

    /**
     * @dev Deposits funds into the market
     * @param amount The amount to deposit
     * @return _eventName Event name for logging
     * @return _eventParam Event parameters for logging
     */
    function deposit(uint256 amount) external returns (string memory _eventName, bytes memory _eventParam) {
        // Approve token transfer
        TokenHelper.approve(monUSD, address(tadleOddsMarket), amount);
        // Execute deposit
        tadleOddsMarket.deposit(amount);
        // Prepare event data
        _eventName = "Deposit(address,uint256)";
        _eventParam = abi.encode(address(this), amount);
    }

    /**
     * @dev Withdraws funds from the market
     * @param amount The amount to withdraw
     * @param timestamp Timestamp for withdrawal
     * @param signature Authorization signature
     * @return _eventName Event name for logging
     * @return _eventParam Event parameters for logging
     */
    function withdraw(uint256 amount, uint256 timestamp, bytes memory signature)
        external
        returns (string memory _eventName, bytes memory _eventParam)
    {
        // Execute withdrawal
        tadleOddsMarket.withdraw(address(this), amount, timestamp, signature);
        // Prepare event data
        _eventName = "Withdraw(address,uint256)";
        _eventParam = abi.encode(address(this), amount);
    }
}

/**
 * @title ConnectV1TadleOdds
 * @dev Versioned connector contract for Tadle Odds
 */
contract ConnectV1TadleOdds is TadleOddsResolver {
    /// @dev Version identifier for the connector
    string public constant name = "TadleOdds-v1.0.0";

    /**
     * @dev Initializes the connector
     * @param _tadleOddsMarket Address of the odds market contract
     * @param _monUSD Address of the token contract
     */
    constructor(address _tadleOddsMarket, address _monUSD) TadleOddsResolver(_tadleOddsMarket, _monUSD) {}
}
