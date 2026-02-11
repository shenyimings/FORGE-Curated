// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

import { BaseController } from "./BaseController.sol";
import { AccountingLogic } from "./AccountingLogic.sol";

/**
 * @title YieldManager
 * @dev Abstract contract that manages yield distribution for the protocol.
 * Handles the calculation and distribution of yield generated from backing assets,
 * including protocol fee collection and safety buffer management.
 */
abstract contract YieldManager is BaseController, AccountingLogic {
    using Math for uint256;

    /**
     * @dev Role identifier for addresses authorized to distribute yield
     */
    bytes32 public constant YIELD_MANAGER_ROLE = keccak256("YIELD_MANAGER_ROLE");

    /**
     * @dev Emitted when yield is distributed to the yield distributor
     */
    event YieldDistributed(address indexed yieldDistributor, uint256 yield);

    /**
     * @dev Thrown when yield distribution is paused (share redemption price != mint price)
     */
    error Yield_DistributionPaused();
    /**
     * @dev Thrown when the safety buffer exceeds the available yield
     */
    error Yield_ExcessiveSafetyBuffer();

    /**
     * @dev Initializer function for the YieldManager contract
     * @notice This function should be called during contract initialization
     */
    // forge-lint: disable-next-line(mixed-case-function)
    function __YieldManager_init() internal onlyInitializing { }

    /**
     * @notice Distributes yield generated from backing assets to the yield distributor
     * @dev Calculates yield as the difference between backing assets value and share total supply.
     * Deducts safety buffer and protocol fees before distribution.
     * Only callable when share redemption price equals mint price (distribution not paused).
     * @return yield The net amount of yield distributed after fees and safety buffer
     */
    function distributeYield() external nonReentrant onlyRole(YIELD_MANAGER_ROLE) returns (uint256 yield) {
        uint256 value = backingAssetsValue();
        require(_shareRedemptionPrice(value) == SHARE_MINT_PRICE, Yield_DistributionPaused());

        yield = value - _share.totalSupply(); // share redemption price is 1 with same decimals
        require(yield > safetyBufferYieldDeduction, Yield_ExcessiveSafetyBuffer());
        yield -= safetyBufferYieldDeduction;

        _share.mint(address(_yieldDistributor), yield);
        emit YieldDistributed(address(_yieldDistributor), yield);
    }
}
