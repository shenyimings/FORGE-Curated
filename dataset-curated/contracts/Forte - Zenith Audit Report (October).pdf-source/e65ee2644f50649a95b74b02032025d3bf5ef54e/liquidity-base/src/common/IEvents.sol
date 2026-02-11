// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {packedFloat} from "../amm/mathLibs/MathLibs.sol";
/**
 * @dev File that contains all the events for the project
 * @author @oscarsernarosero @mpetersoCode55 @cirsteve @palmerg4
 * @notice this file should be then inherited in the contract interfaces to use the events.
 */

/**
 * @dev events common for the pool and the factory contract
 * @notice any change in this interface most likely means a breaking change with monitoring services
 */
interface CommonEvents {
    enum FeeCollectionType {
        LP,
        PROTOCOL
    }
    event ProtocolFeeCollectorProposed(address _collector);
    event ProtocolFeeCollectorConfirmed(address _collector);
    event FeeSet(FeeCollectionType _feeType, uint16 _fee);
}

/**
 * @dev events for the pool contract
 * @notice any change in this interface most likely means a breaking change with monitoring services
 */
interface IPoolEvents is CommonEvents {
    event FeesCollected(FeeCollectionType _feeType, address _collector, uint256 _amount);
    event Swap(address _tokenIn, uint256 _amountIn, uint256 _amountOut, uint256 _minOut, address _recipient);
    event RevenueWithdrawn(address _collector, uint256 tokenId, uint256 _amount, address _recipient);
    event LiquidityWithdrawn(
        address lp,
        uint tokenId,
        uint256 amountOutXToken,
        uint256 amountOutYToken,
        uint256 revenue,
        address _recipient
    );
    event LiquidityDeposited(address _sender, uint256 _tokenId, uint256 _A, uint256 _B);
    event LPTokenUpdated(uint256 tokenId, packedFloat wj, packedFloat hn);
    event FeesGenerated(uint256 lpFee, uint256 protocolFee);
    event PositionMinted(uint256 tokenId, address owner, bool isInactive);
}

/**
 * @dev events for the pool-factory contract
 * @notice any change in this interface most likely means a breaking change with monitoring services
 */
interface IFactoryEvents is CommonEvents {
    event PoolCreated(address _pool);
    event SetYTokenAllowList(address _allowedList);
    event SetDeployerAllowList(address _allowedList);
    event LPTokenAddressSet(address _LPTokenAddres);
}

interface IAllowListEvents {
    event AllowListDeployed();
    event AddressAllowed(address _address, bool _allowed);
}

interface ILPTokenEvents{
    event ALTBCPositionTokenDeployed();
    event PoolAddedToAllowList(address pool, uint256 inactiveTokenId);
    event FactoryProposed(address factory);
    event FactoryConfirmed(address factory);
    event LPTokenUpdated(uint256 tokenId, packedFloat wj, packedFloat hn);
}
