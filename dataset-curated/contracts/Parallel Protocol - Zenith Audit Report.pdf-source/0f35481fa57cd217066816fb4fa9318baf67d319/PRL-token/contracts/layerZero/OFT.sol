// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import { Origin } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/OApp.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import { OFTComposeMsgCodec } from "./libs/OFTComposeMsgCodec.sol";
import { OFTMsgCodec } from "./libs/OFTMsgCodec.sol";
import { IOFT, OFTCore } from "./OFTCore.sol";

/// @title OFT Contract
/// @author Forked from
/// https://github.com/LayerZero-Labs/LayerZero-v2/blob/main/packages/layerzero-v2/evm/oapp/contracts/oft/OFT.sol
/// @dev Modifications made by Cooper Labs.
/// @dev Removed sharedDecimals/decimalConversionRate related code.
/// @dev Extends the default OFT token to ERC-20 Permit.
abstract contract OFT is OFTCore, ERC20 {
    using OFTMsgCodec for bytes;
    using OFTMsgCodec for bytes32;

    /// @dev Constructor for the OFT contract.
    /// @param _name The name of the OFT.
    /// @param _symbol The symbol of the OFT.
    /// @param _lzEndpoint The LayerZero endpoint address.
    /// @param _delegate The delegate capable of making OApp configurations inside of the endpoint.
    constructor(
        string memory _name,
        string memory _symbol,
        address _lzEndpoint,
        address _delegate
    )
        ERC20(_name, _symbol)
        OFTCore(_lzEndpoint, _delegate)
    { }

    /// @dev Retrieves the address of the underlying ERC20 implementation.
    /// @dev In the case of OFT, address(this) and erc20 are the same contract.
    /// @return The address of the OFT token.
    function token() public view returns (address) {
        return address(this);
    }

    /// @notice Indicates whether the OFT contract requires approval of the 'token()' to send.
    /// @return requiresApproval Needs approval of the underlying token implementation.
    /// @dev In the case of OFT where the contract IS the token, approval is NOT required.
    function approvalRequired() external pure virtual returns (bool) {
        return false;
    }

    /// @dev Burns tokens from the sender's specified balance.
    /// @param _from The address to debit the tokens from.
    /// @param _amount The amount of tokens to send.
    /// @param _minAmount The minimum amount to send.
    /// @param _dstEid The destination chain ID.
    /// @return amountSent The amount sent.
    /// @return amountReceived The amount received on the remote.
    function _debit(
        address _from,
        uint256 _amount,
        uint256 _minAmount,
        uint32 _dstEid
    )
        internal
        virtual
        override
        returns (uint256 amountSent, uint256 amountReceived)
    {
        (amountSent, amountReceived) = _debitView(_amount, _minAmount, _dstEid);

        // @dev In NON-default OFT, amountSent could be 100, with a 10% fee, the amountReceived amount is 90,
        // therefore amountSent CAN differ from amountReceived.

        // @dev Default OFT burns on src.
        _burn(_from, amountSent);
    }

    /// @dev Credits tokens to the specified address.
    /// @param _to The address to credit the tokens to.
    /// @param _amount The amount of tokens to credit.
    /// @dev _srcEid The source chain ID.
    /// @return amountReceived The amount of tokens ACTUALLY received.
    function _credit(
        address _to,
        uint256 _amount,
        uint32 /*_srcEid*/
    )
        internal
        virtual
        override
        returns (uint256 amountReceived)
    {
        if (_to == address(0x0)) _to = address(0xdead); // _mint(...) does not support address(0x0)
        // @dev Default OFT mints on dst.
        _mint(_to, _amount);
        // @dev In the case of NON-default OFT, the _amount MIGHT not be == amountReceived.
        return _amount;
    }
}
