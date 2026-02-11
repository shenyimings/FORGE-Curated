// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

/// @title OFTMsgCodec
/// @author Forked from
/// https://github.com/LayerZero-Labs/LayerZero-v2/blob/main/packages/layerzero-v2/evm/oapp/contracts/oft/libs/OFTMsgCodec.sol
/// @dev Modifications made by Cooper Labs. Removed 'SD' (Shared Decimals) related code.
library OFTMsgCodec {
    // Offset constants for encoding and decoding OFT messages
    uint8 private constant SEND_TO_OFFSET = 32;
    uint8 private constant SEND_AMOUNT_OFFSET = 64;

    /// @dev Encodes an OFT LayerZero message.
    /// @param _sendTo The recipient address.
    /// @param _amount The amount.
    /// @param _composeMsg The composed message.
    /// @return _msg The encoded message.
    /// @return hasCompose A boolean indicating whether the message has a composed payload.
    function encode(
        bytes32 _sendTo,
        uint256 _amount,
        bytes memory _composeMsg
    )
        internal
        view
        returns (bytes memory _msg, bool hasCompose)
    {
        hasCompose = _composeMsg.length > 0;
        // @dev Remote chains will want to know the composed function caller ie. msg.sender on the src.
        _msg = hasCompose
            ? abi.encodePacked(_sendTo, _amount, addressToBytes32(msg.sender), _composeMsg)
            : abi.encodePacked(_sendTo, _amount);
    }

    /// @dev Checks if the OFT message is composed.
    /// @param _msg The OFT message.
    /// @return A boolean indicating whether the message is composed.
    function isComposed(bytes calldata _msg) internal pure returns (bool) {
        return _msg.length > SEND_AMOUNT_OFFSET;
    }

    /// @dev Retrieves the recipient address from the OFT message.
    /// @param _msg The OFT message.
    /// @return The recipient address.
    function sendTo(bytes calldata _msg) internal pure returns (bytes32) {
        return bytes32(_msg[:SEND_TO_OFFSET]);
    }

    /// @dev Retrieves the amount from the OFT message.
    /// @param _msg The OFT message.
    /// @return The amount.
    function amount(bytes calldata _msg) internal pure returns (uint256) {
        return uint256(bytes32(_msg[SEND_TO_OFFSET:SEND_AMOUNT_OFFSET]));
    }

    /// @dev Retrieves the composed message from the OFT message.
    /// @param _msg The OFT message.
    /// @return The composed message.
    function composeMsg(bytes calldata _msg) internal pure returns (bytes memory) {
        return _msg[SEND_AMOUNT_OFFSET:];
    }

    /// @dev Converts an address to bytes32.
    /// @param _addr The address to convert.
    /// @return The bytes32 representation of the address.
    function addressToBytes32(address _addr) internal pure returns (bytes32) {
        return bytes32(uint256(uint160(_addr)));
    }

    /// @dev Converts bytes32 to an address.
    /// @param _b The bytes32 value to convert.
    /// @return The address representation of bytes32.
    function bytes32ToAddress(bytes32 _b) internal pure returns (address) {
        return address(uint160(uint256(_b)));
    }
}
