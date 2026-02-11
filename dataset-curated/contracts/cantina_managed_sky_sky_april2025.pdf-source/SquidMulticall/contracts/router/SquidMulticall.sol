// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {ISquidMulticall} from "../interfaces/ISquidMulticall.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {IERC1155Receiver} from "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract SquidMulticall is ISquidMulticall, IERC721Receiver, IERC1155Receiver {
    using SafeERC20 for IERC20;

    bytes4 private constant ERC165_INTERFACE_ID = 0x01ffc9a7;
    bytes4 private constant ERC721_TOKENRECEIVER_INTERFACE_ID = 0x150b7a02;
    bytes4 private constant ERC1155_TOKENRECEIVER_INTERFACE_ID = 0x4e2312e0;

    /// @inheritdoc ISquidMulticall
    function run(Call[] calldata calls) external payable {
        for (uint256 i = 0; i < calls.length; i++) {
            Call memory call = calls[i];

            if (call.callType == CallType.FullTokenBalance) {
                (address token, uint256 amountParameterPosition) = abi.decode(
                    call.payload,
                    (address, uint256)
                );
                uint256 amount = IERC20(token).balanceOf(address(this));
                // Deduct 1 from amount to keep hot balances and reduce gas cost, which is also why we check for amount < 2 and not 1
                if (amount < 2) revert NoTokenAvailable(token);
                _setCallDataParameter(call.callData, amountParameterPosition, amount - 1);
            } else if (call.callType == CallType.FullNativeBalance) {
                call.value = address(this).balance;
            } else if (call.callType == CallType.CollectTokenBalance) {
                address token = abi.decode(call.payload, (address));
                uint256 senderBalance = IERC20(token).balanceOf(msg.sender);
                IERC20(token).safeTransferFrom(msg.sender, address(this), senderBalance);
                continue;
            }

            (bool success, bytes memory data) = call.target.call{value: call.value}(call.callData);
            if (!success) revert CallFailed(i, data);
        }
    }

    function _setCallDataParameter(
        bytes memory callData,
        uint256 parameterPosition,
        uint256 value
    ) private pure {
        assembly {
            // 36 bytes shift because 32 for prefix + 4 for selector
            mstore(add(callData, add(36, mul(parameterPosition, 32))), value)
        }
    }

    /// @notice Implementation required by ERC165 for NFT reception.
    /// See https://eips.ethereum.org/EIPS/eip-165.
    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return
            interfaceId == ERC1155_TOKENRECEIVER_INTERFACE_ID ||
            interfaceId == ERC721_TOKENRECEIVER_INTERFACE_ID ||
            interfaceId == ERC165_INTERFACE_ID;
    }

    /// @notice Implementation required by ERC721 for NFT reception.
    /// See https://eips.ethereum.org/EIPS/eip-721.
    function onERC721Received(
        address,
        address,
        uint256,
        bytes calldata
    ) external pure returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }

    /// @notice Implementation required by ERC1155 for NFT reception.
    /// See https://eips.ethereum.org/EIPS/eip-1155.
    function onERC1155Received(
        address,
        address,
        uint256,
        uint256,
        bytes calldata
    ) external pure returns (bytes4) {
        return IERC1155Receiver.onERC1155Received.selector;
    }

    /// @notice Implementation required by ERC1155 for NFT reception.
    /// See https://eips.ethereum.org/EIPS/eip-1155.
    function onERC1155BatchReceived(
        address,
        address,
        uint256[] calldata,
        uint256[] calldata,
        bytes calldata
    ) external pure returns (bytes4) {
        return IERC1155Receiver.onERC1155BatchReceived.selector;
    }

    /// @dev Enable native tokens reception with .transfer or .send
    receive() external payable {}
}
