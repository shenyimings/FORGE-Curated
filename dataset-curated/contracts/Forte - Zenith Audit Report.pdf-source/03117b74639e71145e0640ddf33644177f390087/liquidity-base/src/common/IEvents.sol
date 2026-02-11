// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

/**
 * @dev File that contains all the events for the project
 * @author  @oscarsernarosero @mpetersoCode55 @cirsteve @palmerg4
 * @notice this file should be then inherited in the contract interfaces to use the events.
 */

/**
 * @dev events common for the pool and the factory contract
 * @notice any change in this interface most likely means a breaking change with monitoring services
 */
interface CommonEvents {
    event ProtocolFeeSet(uint16 indexed _protocolFee);
    event ProtocolFeeCollectorProposed(address indexed _collector);
    event ProtocolFeeCollectorConfirmed(address indexed _collector);
}

/**
 * @dev events for the pool contract
 * @notice any change in this interface most likely means a breaking change with monitoring services
 */
interface IPoolEvents is CommonEvents {
    event LiquidityXTokenAdded(address indexed _token, uint256 amount);
    event PoolClosed(uint256 indexed amountOutTokenX, uint256 indexed amountOutTokenY);
    event Swap(address indexed _tokenIn, uint256 indexed _amountIn, uint256 indexed _amountOut, uint256 _minOut);
    event LPFeeSet(uint16 indexed _fee);
    event LPFeeGenerated(uint256 indexed _amount);
    event ProtocolFeeGenerated(uint256 indexed _amount);
    event LPFeesCollected(address indexed _collector, uint256 indexed _amount);
    event ProtocolFeesCollected(address indexed _collector, uint256 indexed _amount);
    event RevenueWithdrawn(address indexed _collector, uint256 indexed tokenId, uint256 indexed _amount);
    event CumulativePriceUpdated(uint256 indexed blockTimestamp, uint cumulativePrice);
    event LiquidityWithdrawn(address lp, uint indexed tokenId, uint256 indexed amountOutXToken, uint256 indexed amountOutYToken, uint256 revenue);
    event LPTokenMinted(address indexed lp, uint256 indexed tokenId, uint256 amountXToken, uint256 amountYToken);
    event LPTokenBurned(address indexed lp, uint256 indexed tokenId, uint256 indexed initialLiquidityWj);
}

/**
 * @dev events for the pool-factory contract
 * @notice any change in this interface most likely means a breaking change with monitoring services
 */
interface IFactoryEvents is CommonEvents {
    event PoolCreated(address indexed _pool);
    event SetYTokenAllowList(address indexed _allowedList);
    event SetDeployerAllowList(address indexed _allowedList);
}

interface IAllowListEvents {
    event AllowListDeployed();
    event AddressAllowed(address indexed _address, bool indexed _allowed);
}
