// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { OAppSender, OAppCore } from "@layerzerolabs/oapp-evm/contracts/oapp/OAppSender.sol";
import { OptionsBuilder } from "@layerzerolabs/oapp-evm/contracts/oapp/libs/OptionsBuilder.sol";
import { MessagingFee, OFTReceipt } from "@layerzerolabs/oft-evm/contracts/interfaces/IOFT.sol";
import { OFTMsgCodec } from "@layerzerolabs/oft-evm/contracts/libs/OFTMsgCodec.sol";

/// @title OAppMessenger
/// @notice Messenger logic for the LayerZero bridge
abstract contract OAppMessenger is OAppSender {
    using OptionsBuilder for bytes;

    /// @dev Gas limit for the LayerZero bridge
    uint128 private constant lzReceiveGas = 100_000;

    /// @dev Destination EID for the LayerZero bridge
    uint32 private immutable dstEid;

    /// @dev Decimals of the token
    uint8 private immutable decimals;

    /// @dev OAppCore sets the endpoint as an immutable variable
    /// @param _lzEndpoint Local layerzero endpoint
    constructor(address _lzEndpoint, uint32 _dstEid, uint8 _decimals) OAppCore(_lzEndpoint, msg.sender) {
        dstEid = _dstEid;
        decimals = _decimals;
    }

    /// @notice Quote the fee for depositing via the LayerZero bridge
    /// @param _amountLD Amount in local decimals
    /// @param _destReceiver Receiver of the assets on MegaETH Testnet
    /// @return fee Fee for the LayerZero bridge
    function quote(uint256 _amountLD, address _destReceiver) external view returns (MessagingFee memory fee) {
        (bytes memory message, bytes memory options) = _buildMsgAndOptions(lzReceiveGas, _amountLD, _destReceiver);
        fee = _quote(dstEid, message, options, false);
    }

    /// @dev Message using layer zero. Fee overpays are refunded to caller
    /// @param _destReceiver Receiver of assets on destination chain
    /// @param _amountLD Amount of asset in local decimals
    function _sendMessage(address _destReceiver, uint256 _amountLD) internal {
        MessagingFee memory _fee = MessagingFee({ nativeFee: msg.value, lzTokenFee: 0 });
        (bytes memory message, bytes memory options) = _buildMsgAndOptions(lzReceiveGas, _amountLD, _destReceiver);
        _lzSend(dstEid, message, options, _fee, msg.sender);
    }

    /// @dev Build the message and options for the LayerZero bridge
    /// @param _gas Gas fee
    /// @param _amountLD Amount in local decimals
    /// @param _destReceiver Receiver of the assets on MegaETH Testnet
    /// @return message Message for the LayerZero bridge
    /// @return options Options for the LayerZero bridge
    function _buildMsgAndOptions(uint128 _gas, uint256 _amountLD, address _destReceiver)
        internal
        view
        returns (bytes memory message, bytes memory options)
    {
        (message,) = OFTMsgCodec.encode(OFTMsgCodec.addressToBytes32(_destReceiver), _toSD(_amountLD), "");
        options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(_gas, 0);
    }

    /// @dev Convert amount in shared decimals to amount in local decimals
    /// @param _amountLD Amount in local decimals
    /// @return amountSD Amount in shared decimals
    function _toSD(uint256 _amountLD) internal view virtual returns (uint64 amountSD) {
        return uint64(_amountLD / (10 ** (decimals - sharedDecimals())));
    }

    /// @notice Retrieves the shared decimals of the OFT.
    /// @return The shared decimals of the OFT.
    function sharedDecimals() public view virtual returns (uint8) {
        return 6;
    }
}
