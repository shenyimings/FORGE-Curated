// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

import {PoolId} from "../types/PoolId.sol";
import {PoolKey} from "../types/PoolKey.sol";
import {Currency} from "../types/Currency.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {LendPosition} from "../libraries/LendPosition.sol";

interface ILendPositionManager is IERC721 {
    error InvalidCurrency();

    event Deposit(
        PoolId indexed poolId,
        Currency indexed currency,
        address indexed sender,
        uint256 tokenId,
        address recipient,
        uint256 amount
    );

    event Withdraw(
        PoolId indexed poolId,
        Currency indexed currency,
        address indexed sender,
        uint256 tokenId,
        address recipient,
        uint256 amount
    );

    /// @notice Return the position with the given ID
    /// @param positionId The ID of the position to retrieve
    /// @return _position The position with the given ID
    function getPositionState(uint256 positionId) external view returns (LendPosition.State memory);

    /// @notice Creates a new lending position.
    /// @param key The key of the pool to lend to.
    /// @param lendForOne The direction of lend.
    /// @param recipient The recipient of the position.
    /// @param amount The amount to lend.
    /// @return tokenId The ID of the new position.
    function addLending(PoolKey memory key, bool lendForOne, address recipient, uint256 amount)
        external
        payable
        returns (uint256 tokenId);

    /// @notice Deposits more funds into an existing lending position.
    /// @param tokenId The ID of the position to deposit into.
    /// @param amount The amount to deposit.
    function deposit(uint256 tokenId, uint256 amount) external payable;

    /// @notice Withdraws funds from an existing lending position.
    /// @param tokenId The ID of the position to withdraw from.
    /// @param amount The amount to withdraw.
    function withdraw(uint256 tokenId, uint256 amount) external;

    struct SwapInputParams {
        PoolId poolId;
        bool zeroForOne;
        uint256 tokenId;
        uint256 amountIn;
        uint256 amountOutMin;
        uint256 deadline;
    }

    /// @notice Swaps an exact amount of input tokens for as many output tokens as possible.
    /// @param params The parameters for the swap.
    /// @return swapFee The fee paid for the swap.
    /// @return feeAmount The amount of the fee.
    /// @return amountOut The amount of output tokens received.
    function exactInput(SwapInputParams calldata params)
        external
        payable
        returns (uint24 swapFee, uint256 feeAmount, uint256 amountOut);

    struct SwapOutputParams {
        PoolId poolId;
        bool zeroForOne;
        uint256 tokenId;
        uint256 amountInMax;
        uint256 amountOut;
        uint256 deadline;
    }

    /// @notice Swaps as few input tokens as possible for an exact amount of output tokens.
    /// @param params The parameters for the swap.
    /// @return swapFee The fee paid for the swap.
    /// @return feeAmount The amount of the fee.
    /// @return amountIn The amount of input tokens paid.
    function exactOutput(SwapOutputParams calldata params)
        external
        payable
        returns (uint24 swapFee, uint256 feeAmount, uint256 amountIn);
}
