// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import { IERC20Metadata, IERC20 } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { IOFT, OFTCore } from "./OFTCore.sol";

/// @title OFTAdapter Contract
/// @author Forked from
/// https://github.com/LayerZero-Labs/LayerZero-v2/blob/main/packages/layerzero-v2/evm/oapp/contracts/oft/OFTAdapter.sol
/// @dev Modifications made by Cooper Labs. Removed sharedDecimals/decimalConversionRate related code.
/// @dev OFTAdapter is a contract that adapts an ERC-20 token to the OFT functionality.
/// @dev For existing ERC20 tokens, this can be used to convert the token to crosschain compatibility.
/// @dev WARNING: ONLY 1 of these should exist for a given global mesh,
/// unless you make a NON-default implementation of OFT and needs to be done very carefully.
/// @dev WARNING: The default OFTAdapter implementation assumes LOSSLESS transfers, ie. 1 token in, 1 token out.
/// IF the 'innerToken' applies something like a transfer fee, the default will NOT work...
/// a pre/post balance check will need to be done to calculate the amountSent/amountReceived.
abstract contract OFTAdapter is OFTCore {
    using SafeERC20 for IERC20;

    IERC20 internal immutable innerToken;

    /// @dev Constructor for the OFTAdapter contract.
    /// @param _token The address of the ERC-20 token to be adapted.
    /// @param _lzEndpoint The LayerZero endpoint address.
    /// @param _delegate The delegate capable of making OApp configurations inside of the endpoint.
    constructor(address _token, address _lzEndpoint, address _delegate) OFTCore(_lzEndpoint, _delegate) {
        innerToken = IERC20(_token);
    }

    /// @dev Retrieves the address of the underlying ERC20 implementation.
    /// @return The address of the adapted ERC-20 token.
    /// @dev In the case of OFTAdapter, address(this) and erc20 are NOT the same contract.
    function token() public view returns (address) {
        return address(innerToken);
    }

    /// @notice Indicates whether the OFT contract requires approval of the 'token()' to send.
    /// @return requiresApproval Needs approval of the underlying token implementation.
    /// @dev In the case of OFT where the contract IS the token, approval is NOT required.
    function approvalRequired() external pure virtual returns (bool) {
        return true;
    }

    /// @dev Burns tokens from the sender's specified balance, ie. pull method.
    /// @param _from The address to debit from.
    /// @param _amount The amount of tokens to send.
    /// @param _minAmount The minimum amount to send.
    /// @param _dstEid The destination chain ID.
    /// @return amountSent The amount sent.
    /// @return amountReceived The amount received  on the remote.
    /// @dev msg.sender will need to approve this _amount of tokens to be locked inside of the contract.
    /// @dev WARNING: The default OFTAdapter implementation assumes LOSSLESS transfers, ie. 1 token in, 1 token out.
    /// IF the 'innerToken' applies something like a transfer fee, the default will NOT work...
    /// a pre/post balance check will need to be done to calculate the amountReceived.
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
        // @dev Lock tokens by moving them into this contract from the caller.
        innerToken.safeTransferFrom(_from, address(this), amountSent);
    }

    /// @dev Credits tokens to the specified address.
    /// @param _to The address to credit the tokens to.
    /// @param _amount The amount of tokens to credit.
    /// @dev _srcEid The source chain ID.
    /// @return amountReceived The amount of tokens ACTUALLY received.
    /// @dev WARNING: The default OFTAdapter implementation assumes LOSSLESS transfers, ie. 1 token in, 1 token out.
    /// IF the 'innerToken' applies something like a transfer fee, the default will NOT work...
    /// a pre/post balance check will need to be done to calculate the amountReceived.

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
        // @dev Unlock the tokens and transfer to the recipient.
        innerToken.safeTransfer(_to, _amount);
        // @dev In the case of NON-default OFTAdapter, the amount MIGHT not be == amountReceived.
        return _amount;
    }
}
