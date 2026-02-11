// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import "./features/ContractOnlyEthRecipient.sol";
import "./features/KyberExecutor.sol";
import "./features/MaverickExecutor.sol";
import "./features/PancakeV3Executor.sol";
import "./features/UniswapV3Executor.sol";
import "./Constants.sol";
import "@1inch/solidity-utils/contracts/libraries/RevertReasonParser.sol";
import "./interfaces/ISwapExecutor.sol";
import "./libs/SafeERC20Ext.sol";
import "./libs/TokenLibrary.sol";
import "./libs/LowLevelHelper.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/**
 * @title SwapExecutor
 * @notice Contract that performs actual swaps. It iterate over calldatas being passed and executes them. This means that users of this contract
 * shall be exeptionally careful about how they do call it, which is why we don't recomment to use it directly except for complex scenarios where
 * this contract might be part of a bigger flow designed by actual solidity developers that will make all sanity checks on their side.
 * SwapFacade is an example of implementation that provide necessary failsafe checks for actual users.
 * This contract also manages fees that might occur during swaps. Callers might check fee values and revert if they are disagree on it
 */
contract SwapExecutor is
    KyberExecutor,
    MaverickExecutor,
    PancakeV3Executor,
    UniswapV3Executor,
    ContractOnlyEthRecipient,
    ReentrancyGuard,
    ISwapExecutor
{
    using TokenLibrary for IERC20;
    using SafeERC20 for IERC20;
    using SafeERC20Ext for IERC20;

    address constant private ERC_1820 = 0x1820a4B7618BdE71Dce8cdc73aAB6C95905faD24;

    /// @notice Performs tokens swap
    /// @param targetTokenTransferInfos instructions on how to transfer tokens to target addresses
    /// @param swapDescriptions descriptions that describe how exactly swaps should be performed
    function executeSwap(TokenTransferInfo[] calldata targetTokenTransferInfos, SwapDescription[] calldata swapDescriptions) external nonReentrant() payable {
        unchecked {
            for (uint256 i = 0; i < swapDescriptions.length; i++) {
                IERC20 sourceToken = swapDescriptions[i]
                    .sourceToken;
                uint256 balanceToSwap = sourceToken
                    .universalBalanceOf(address(this));
                if (balanceToSwap == 0) {
                    revert SwapTotalAmountCannotBeZero();
                }
                // keeping 1 wei on contract for cheaper swaps
                balanceToSwap--;
                TargetSwapDescription[] calldata swaps = swapDescriptions[i].swaps;
                for (uint256 j = 0; j < swaps.length; j++) {
                    TargetSwapDescription calldata swap = swaps[j];
                    uint256 poolSwapAmount = (balanceToSwap * swap.tokenRatio) / _ONE;
                    // CallType callType; first 8 bits
                    // SourceTokenInteraction sourceInteraction; next 8 bits
                    // uint256 amountOffset; next 32 bits
                    // address sourceTokenInteractionTarget; last 160 bits
                    uint8 callType = uint8(swap.params >> 248);
                    if (poolSwapAmount == 0) {
                        revert SwapAmountCannotBeZero();
                    }
                    // May be useful if say we want to transfer some funds to recipient without executing a swaps
                    if (true) {
                        // solhint-disable avoid-low-level-calls
                        bool success;
                        bytes memory result;
                        if (callType == CALL_TYPE_DIRECT) {
                            uint8 sourceInteraction = uint8(swap.params >> 240);
                            uint32 amountOffset = uint32(swap.params >> 208);
                            address sourceTokenInteractionTarget = address(uint160(swap.params));
                            uint256 value = performSourceTokenInteractionAndGetEthValue(sourceToken, poolSwapAmount, sourceInteraction, sourceTokenInteractionTarget);
                            bytes memory data = amountOffset != type(uint32).max // flag meaning no patching is required
                                ? LowLevelHelper.patchUint(swap.data, poolSwapAmount, amountOffset)
                                : swap.data;
                            {
                                bool shouldRevert;
                                assembly {
                                    let sig := and(mload(add(data, 0x20)), 0xffffffff00000000000000000000000000000000000000000000000000000000)
                                    shouldRevert := eq(sig, 0x23b872dd00000000000000000000000000000000000000000000000000000000)
                                }
                                if (shouldRevert) {
                                    revert TransferFromNotAllowed();
                                }
                                if (swap.target == ERC_1820) {
                                    revert ERC1820InterfactionForbidden();
                                }
                            }
                            (success, result) = swap.target.call{ value: value }(data);
                        }
                        else if (callType == CALL_TYPE_CALCULATED) {
                            {
                                uint256 amountOffset = uint32(swap.params >> 208);
                                bytes memory calculatedData = amountOffset != type(uint32).max // flag meaning no patching is required
                                    ? LowLevelHelper.patchUint(swap.data, poolSwapAmount, amountOffset)
                                    : swap.data;
                                (success, result) = swap.target.staticcall(calculatedData);
                            }
                            if (!success) {
                                string memory reason = RevertReasonParser.parse(
                                    result,
                                    "SEHEC: "
                                );
                                revert(reason);
                            }
                            (address target, address sourceTokenInteractionTarget, uint256 actualSwapAmount, bytes memory data) = abi.decode(result, (address, address, uint256, bytes));
                            {
                                bool shouldRevert;
                                assembly {
                                    let sig := and(mload(add(data, 0x20)), 0xffffffff00000000000000000000000000000000000000000000000000000000)
                                    shouldRevert := eq(sig, 0x23b872dd00000000000000000000000000000000000000000000000000000000)
                                }
                                if (shouldRevert) {
                                    revert TransferFromNotAllowed();
                                }
                                if (target == ERC_1820) {
                                    revert ERC1820InterfactionForbidden();
                                }
                            }
                            uint256 value;
                            {
                                value = performSourceTokenInteractionAndGetEthValue(sourceToken, actualSwapAmount, uint8(swap.params >> 240), sourceTokenInteractionTarget);
                            }
                            (success, result) = target.call{ value: value }(data);
                        }
                        else {
                            revert EnumOutOfRangeValue(EnumType.CallType, uint256(callType));
                        }
                        if (!success) {
                            string memory reason = RevertReasonParser.parse(
                                result,
                                "SEEC: "
                            );
                            revert(reason);
                        }
                    }
                }
            }

            for (uint256 i = 0; i < targetTokenTransferInfos.length; i++) {
                TokenTransferInfo calldata info = targetTokenTransferInfos[i];
                if (info.exactAmount > 0) {
                    // request to transfer exact amount
                    info.token.universalTransfer(info.recipient, info.exactAmount);
                } else {
                    // transfer all that we managed to swap
                    uint256 balance = info.token.universalBalanceOf(address(this));
                    if (balance > 1) {
                        // keep 1 wei as gas saving
                        info.token.universalTransfer(info.recipient, balance - 1);
                    }
                }
            }
        }
    }

    /// @notice Performs source token interaction required by protocol, such as approve, transfer or anything else.
    /// @return Result Amount of ether that should be provided to call `target`
    function performSourceTokenInteractionAndGetEthValue(IERC20 sourceToken, uint256 poolSwapAmount, uint8 sourceInteraction, address sourceTokenInteractionTarget) private returns (uint256) {
        if (sourceToken.isEth()) {
            return poolSwapAmount;
        }
        // solhint-disable-next-line no-empty-blocks
        if (sourceInteraction == SOURCE_TOKEN_INTERACTION_NONE) {
        }
        else if (sourceInteraction == SOURCE_TOKEN_INTERACTION_APPROVE) {
            sourceToken.setAllowance(sourceTokenInteractionTarget, poolSwapAmount);
        }
        else if (sourceInteraction == SOURCE_TOKEN_INTERACTION_TRANSFER) {
            sourceToken.safeTransfer(sourceTokenInteractionTarget, poolSwapAmount);
        }
        else {
            revert EnumOutOfRangeValue(EnumType.SourceTokenInteraction, uint256(sourceInteraction));
        }
        return 0;
    }
}
