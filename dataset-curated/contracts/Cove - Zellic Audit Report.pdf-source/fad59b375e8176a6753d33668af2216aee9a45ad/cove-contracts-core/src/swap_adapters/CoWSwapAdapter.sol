// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ClonesWithImmutableArgs } from "clones-with-immutable-args/ClonesWithImmutableArgs.sol";
import { GPv2Order } from "src/deps/cowprotocol/GPv2Order.sol";

import { Errors } from "src/libraries/Errors.sol";
import { CoWSwapClone } from "src/swap_adapters/CoWSwapClone.sol";
import { TokenSwapAdapter } from "src/swap_adapters/TokenSwapAdapter.sol";
import { ExternalTrade } from "src/types/Trades.sol";

/// @title CoWSwapAdapter
/// @notice Adapter for executing and completing token swaps using CoWSwap protocol.
contract CoWSwapAdapter is TokenSwapAdapter {
    using GPv2Order for GPv2Order.Data;
    using SafeERC20 for IERC20;

    /// CONSTANTS ///
    /// @dev Storage slot for CoWSwapAdapter specific data.
    bytes32 internal constant _COWSWAP_ADAPTER_STORAGE =
        bytes32(uint256(keccak256("cove.basketmanager.cowswapadapter.storage")) - 1);

    /// @notice Address of the clone implementation used for creating CoWSwapClone contracts.
    address public immutable cloneImplementation;

    /// STRUCTS ///
    /// @dev Structure to store adapter-specific data.
    struct CoWSwapAdapterStorage {
        uint32 orderValidTo;
    }

    /// EVENTS ///
    /// @notice Emitted when a new order is created.
    /// @param sellToken The address of the token to be sold.
    /// @param buyToken The address of the token to be bought.
    /// @param sellAmount The amount of the sell token.
    /// @param buyAmount The amount of the buy token.
    /// @param validTo The timestamp until which the order is valid.
    /// @param swapContract The address of the swap contract.
    event OrderCreated(
        address indexed sellToken,
        address indexed buyToken,
        uint256 sellAmount,
        uint256 buyAmount,
        uint32 validTo,
        address swapContract
    );

    /// @notice Emitted when a token swap is completed.
    /// @param sellToken The address of the token sold.
    /// @param buyToken The address of the token bought.
    /// @param claimedSellAmount The amount of sell tokens claimed.
    /// @param claimedBuyAmount The amount of buy tokens claimed.
    /// @param swapContract The address of the swap contract.
    event TokenSwapCompleted(
        address indexed sellToken,
        address indexed buyToken,
        uint256 claimedSellAmount,
        uint256 claimedBuyAmount,
        address swapContract
    );

    /// @notice Constructor to initialize the CoWSwapAdapter with the clone implementation address.
    /// @param cloneImplementation_ The address of the clone implementation contract.
    constructor(address cloneImplementation_) payable {
        if (cloneImplementation_ == address(0)) {
            revert Errors.ZeroAddress();
        }
        cloneImplementation = cloneImplementation_;
    }

    /// @notice Executes a series of token swaps by creating orders on the CoWSwap protocol.
    /// @param externalTrades The external trades to execute.
    function executeTokenSwap(ExternalTrade[] calldata externalTrades, bytes calldata) external payable override {
        uint32 validTo = uint32(block.timestamp + 15 minutes);
        _cowswapAdapterStorage().orderValidTo = validTo;
        for (uint256 i = 0; i < externalTrades.length;) {
            _createOrder(
                externalTrades[i].sellToken,
                externalTrades[i].buyToken,
                externalTrades[i].sellAmount,
                externalTrades[i].minAmount,
                validTo
            );
            unchecked {
                // Overflow not possible: i is bounded by externalTrades.length
                ++i;
            }
        }
    }

    /// @notice Completes the token swaps by claiming the tokens from the CoWSwapClone contracts.
    /// @param externalTrades The external trades that were executed and need to be settled.
    /// @return claimedAmounts A 2D array containing the claimed amounts of sell and buy tokens for each trade.
    function completeTokenSwap(ExternalTrade[] calldata externalTrades)
        external
        payable
        override
        returns (uint256[2][] memory claimedAmounts)
    {
        uint256 length = externalTrades.length;
        claimedAmounts = new uint256[2][](length);
        uint32 validTo = _cowswapAdapterStorage().orderValidTo;

        for (uint256 i = 0; i < length;) {
            // Call claim on each CoWSwapClone contract
            bytes32 salt = keccak256(
                abi.encodePacked(
                    externalTrades[i].sellToken,
                    externalTrades[i].buyToken,
                    externalTrades[i].sellAmount,
                    externalTrades[i].minAmount,
                    validTo
                )
            );
            address swapContract = ClonesWithImmutableArgs.addressOfClone3(salt);
            // slither-disable-next-line calls-loop
            (uint256 claimedSellAmount, uint256 claimedBuyAmount) = CoWSwapClone(swapContract).claim();
            claimedAmounts[i] = [claimedSellAmount, claimedBuyAmount];
            // slither-disable-next-line reentrancy-events
            emit TokenSwapCompleted(
                externalTrades[i].sellToken,
                externalTrades[i].buyToken,
                claimedSellAmount,
                claimedBuyAmount,
                swapContract
            );
            unchecked {
                // Overflow not possible: i is bounded by externalTrades.length
                ++i;
            }
        }
    }

    /// @dev Internal function to create an order on the CoWSwap protocol.
    /// @param sellToken The address of the token to sell.
    /// @param buyToken The address of the token to buy.
    /// @param sellAmount The amount of the sell token.
    /// @param buyAmount The minimum amount of the buy token.
    /// @param validTo The timestamp until which the order is valid.
    function _createOrder(
        address sellToken,
        address buyToken,
        uint256 sellAmount,
        uint256 buyAmount,
        uint32 validTo
    )
        internal
    {
        // Create the order with the receiver being the cloned contract
        bytes32 salt = keccak256(abi.encodePacked(sellToken, buyToken, sellAmount, buyAmount, validTo));
        address swapContract = ClonesWithImmutableArgs.clone3(
            cloneImplementation,
            abi.encodePacked(sellToken, buyToken, sellAmount, buyAmount, uint64(validTo), address(this), address(this)),
            salt
        );
        emit OrderCreated(sellToken, buyToken, sellAmount, buyAmount, validTo, swapContract);
        // slither-disable-start calls-loop
        IERC20(sellToken).safeTransfer(swapContract, sellAmount);
        CoWSwapClone(swapContract).initialize();
        // slither-disable-end calls-loop
    }

    /// @dev Internal function to retrieve the storage for the CoWSwapAdapter.
    /// @return s The storage struct for the CoWSwapAdapter.
    function _cowswapAdapterStorage() internal pure returns (CoWSwapAdapterStorage storage s) {
        bytes32 slot = _COWSWAP_ADAPTER_STORAGE;
        // slither-disable-start assembly
        // solhint-disable-next-line no-inline-assembly
        assembly {
            s.slot := slot
        }
        // slither-disable-end assembly
    }
}
