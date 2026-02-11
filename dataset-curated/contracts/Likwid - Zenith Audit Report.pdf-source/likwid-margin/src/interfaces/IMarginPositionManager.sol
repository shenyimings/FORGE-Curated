// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

import {PoolId} from "../types/PoolId.sol";
import {PoolKey} from "../types/PoolKey.sol";
import {MarginLevels} from "../types/MarginLevels.sol";
import {IBasePositionManager} from "./IBasePositionManager.sol";
import {MarginPosition} from "../libraries/MarginPosition.sol";

interface IMarginPositionManager is IBasePositionManager {
    /// @notice Thrown when the provided level is invalid
    error InvalidLevel();

    /// @notice Thrown when the received borrow amount is insufficient
    error InsufficientBorrowReceived();

    /// @notice Thrown when the received close amount is insufficient
    error InsufficientCloseReceived();

    /// @notice Thrown when the received amount is insufficient
    error InsufficientReceived();

    /// @notice Thrown when the position is not liquidated
    error PositionNotLiquidated();

    /// @notice Thrown when the mirror amount is too high
    error MirrorTooMuch();

    /// @notice Thrown when the borrow amount is too high
    error BorrowTooMuch();

    /// @notice Thrown when the reserves are not enough
    error ReservesNotEnough();

    /// @notice Thrown when margin is banned for low fee pools
    error LowFeePoolMarginBanned();

    /// @notice Emitted when the margin level is changed
    /// @param oldLevel The old margin level
    /// @param newLevel The new margin level
    event MarginLevelChanged(bytes32 oldLevel, bytes32 newLevel);

    /// @notice Emitted when the margin fee is changed
    /// @param oldFee The old margin fee
    /// @param newFee The new margin fee
    event MarginFeeChanged(uint24 oldFee, uint24 newFee);

    /// @notice Emitted when a margin position is created or increased
    /// @param poolId The ID of the pool
    /// @param owner The owner of the position
    /// @param tokenId The ID of the position token
    /// @param marginAmount The amount of margin added
    /// @param marginTotal The total margin of the position
    /// @param debtAmount The total debt of the position
    /// @param marginForOne Whether the margin is for currency1
    event Margin(
        PoolId indexed poolId,
        address indexed owner,
        uint256 tokenId,
        uint256 marginAmount,
        uint256 marginTotal,
        uint256 debtAmount,
        bool marginForOne
    );

    /// @notice Emitted when a margin position is repaid
    /// @param poolId The ID of the pool
    /// @param sender The address of the repayer
    /// @param tokenId The ID of the position token
    /// @param marginAmount The amount of margin in the position
    /// @param marginTotal The total margin of the position
    /// @param debtAmount The total debt of the position
    /// @param releaseAmount The amount of margin released
    /// @param repayAmount The amount of debt repaid
    event Repay(
        PoolId indexed poolId,
        address indexed sender,
        uint256 tokenId,
        uint256 marginAmount,
        uint256 marginTotal,
        uint256 debtAmount,
        uint256 releaseAmount,
        uint256 repayAmount
    );

    /// @notice Emitted when a margin position is closed
    /// @param poolId The ID of the pool
    /// @param sender The address of the closer
    /// @param tokenId The ID of the position token
    /// @param marginAmount The amount of margin in the position
    /// @param marginTotal The total margin of the position
    /// @param debtAmount The total debt of the position
    /// @param releaseAmount The amount of margin released
    /// @param repayAmount The amount of debt repaid
    /// @param closeAmount The amount received after closing
    event Close(
        PoolId indexed poolId,
        address indexed sender,
        uint256 tokenId,
        uint256 marginAmount,
        uint256 marginTotal,
        uint256 debtAmount,
        uint256 releaseAmount,
        uint256 repayAmount,
        uint256 closeAmount
    );

    /// @notice Emitted when a margin position is modified
    /// @param poolId The ID of the pool
    /// @param sender The address of the modifier
    /// @param tokenId The ID of the position token
    /// @param marginAmount The amount of margin in the position
    /// @param marginTotal The total margin of the position
    /// @param debtAmount The total debt of the position
    /// @param changeAmount The amount of change in the position
    event Modify(
        PoolId indexed poolId,
        address indexed sender,
        uint256 tokenId,
        uint256 marginAmount,
        uint256 marginTotal,
        uint256 debtAmount,
        int256 changeAmount
    );

    /// @notice Emitted when a margin position is liquidated by burning
    /// @param poolId The ID of the pool
    /// @param sender The address of the liquidator
    /// @param tokenId The ID of the position token
    /// @param marginAmount The amount of margin in the position
    /// @param marginTotal The total margin of the position
    /// @param debtAmount The total debt of the position
    /// @param truncatedReserves The truncated reserves of the pool
    /// @param pairReserves The pair reserves of the pool
    /// @param releaseAmount The amount of margin released
    /// @param repayAmount The amount of debt repaid
    /// @param profitAmount The profit from the liquidation
    /// @param lostAmount The loss from the liquidation
    event LiquidateBurn(
        PoolId indexed poolId,
        address indexed sender,
        uint256 tokenId,
        uint256 marginAmount,
        uint256 marginTotal,
        uint256 debtAmount,
        uint256 truncatedReserves,
        uint256 pairReserves,
        uint256 releaseAmount,
        uint256 repayAmount,
        uint256 profitAmount,
        uint256 lostAmount
    );

    /// @notice Emitted when a margin position is liquidated by calling
    /// @param poolId The ID of the pool
    /// @param sender The address of the liquidator
    /// @param tokenId The ID of the position token
    /// @param marginAmount The amount of margin in the position
    /// @param marginTotal The total margin of the position
    /// @param debtAmount The total debt of the position
    /// @param truncatedReserves The truncated reserves of the pool
    /// @param pairReserves The pair reserves of the pool
    /// @param releaseAmount The amount of margin released
    /// @param repayAmount The amount of debt repaid
    /// @param needRepayAmount The amount of debt that needs to be repaid
    /// @param lostAmount The loss from the liquidation
    event LiquidateCall(
        PoolId indexed poolId,
        address indexed sender,
        uint256 tokenId,
        uint256 marginAmount,
        uint256 marginTotal,
        uint256 debtAmount,
        uint256 truncatedReserves,
        uint256 pairReserves,
        uint256 releaseAmount,
        uint256 repayAmount,
        uint256 needRepayAmount,
        uint256 lostAmount
    );

    /// @notice Gets the state of a position
    /// @param tokenId The ID of the position token
    /// @return position The state of the position
    function getPositionState(uint256 tokenId) external view returns (MarginPosition.State memory position);

    struct CreateParams {
        /// @notice true: currency1 is marginToken, false: currency0 is marginToken
        bool marginForOne;
        /// @notice Leverage factor of the margin position.
        uint24 leverage;
        /// @notice The amount of margin
        uint256 marginAmount;
        /// @notice The borrow amount of the margin position.When the parameter is passed in, it is 0.
        uint256 borrowAmount;
        /// @notice The maximum borrow amount of the margin position.
        uint256 borrowAmountMax;
        /// @notice The address of recipient
        address recipient;
        /// @notice Deadline for the transaction
        uint256 deadline;
    }

    /// @notice Create/Add a position
    /// @param key The key of pool
    /// @param params The parameters of the margin position
    /// @return tokenId The id of position
    /// @return borrowAmount The borrow amount
    /// @return swapFeeAmount The swap amount in margin
    function addMargin(PoolKey memory key, IMarginPositionManager.CreateParams calldata params)
        external
        payable
        returns (uint256 tokenId, uint256 borrowAmount, uint256 swapFeeAmount);

    struct MarginParams {
        uint256 tokenId;
        /// @notice Leverage factor of the margin position.
        uint24 leverage;
        /// @notice The amount of margin
        uint256 marginAmount;
        /// @notice The borrow amount of the margin position.When the parameter is passed in, it is 0.
        uint256 borrowAmount;
        /// @notice The maximum borrow amount of the margin position.
        uint256 borrowAmountMax;
        /// @notice Deadline for the transaction
        uint256 deadline;
    }

    /// @notice Margin a position
    /// @param params The parameters of the margin position
    /// @return borrowAmount The borrow amount
    /// @return swapFeeAmount The swap amount in margin
    function margin(IMarginPositionManager.MarginParams memory params)
        external
        payable
        returns (uint256 borrowAmount, uint256 swapFeeAmount);

    /// @notice Release the margin position by repaying the debt
    /// @param tokenId The id of position
    /// @param repayAmount The amount to repay
    /// @param deadline Deadline for the transaction
    function repay(uint256 tokenId, uint256 repayAmount, uint256 deadline) external payable;

    /// @notice Close the margin position
    /// @param tokenId The id of position
    /// @param closeMillionth The repayment ratio is calculated as one millionth
    /// @param profitAmountMin The minimum profit amount to be received after closing the position
    /// @param deadline Deadline for the transaction
    function close(uint256 tokenId, uint24 closeMillionth, uint256 profitAmountMin, uint256 deadline) external;

    /// @notice Liquidates a position by burning the position token.
    /// @param tokenId The ID of the position to liquidate.
    /// @return profit The profit from the liquidation.
    function liquidateBurn(uint256 tokenId) external returns (uint256 profit);

    /// @notice Liquidates a position by making a call.
    /// @param tokenId The ID of the position to liquidate.
    /// @return profit The profit from the liquidation.
    /// @return repayAmount The amount repaid.
    function liquidateCall(uint256 tokenId) external payable returns (uint256 profit, uint256 repayAmount);

    /// @notice Modify the margin position
    /// @param tokenId The id of position
    /// @param changeAmount The amount to modify
    function modify(uint256 tokenId, int128 changeAmount) external payable;

    /// @notice Gets the default margin fee
    /// @return defaultMarginFee The default margin fee
    function defaultMarginFee() external view returns (uint24 defaultMarginFee);

    /// @notice Gets the margin levels
    /// @return marginLevel The margin levels
    function marginLevels() external view returns (MarginLevels marginLevel);
}
