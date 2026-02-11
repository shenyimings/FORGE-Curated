// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.22;

import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import { IMintBurnVoidReturn } from "./interfaces/IMintBurnVoidReturn.sol";
import { SkyOFTCore, RateLimitDirection } from "./SkyOFTCore.sol";

/**
 * @title SkyOFTAdapterMintBurn
 * @notice A variant of the standard OFT Adapter that uses an existing ERC20's mint and burn for cross-chain transfers.
 * @dev This contract needs mint permissions on the token.
 * @dev This contract burns the tokens from the sender's balance and transfers in the fee.
 *
 * @dev This contract extends the SkyOFTCore, which extends the SkyRateLimiter containing rate limiting functionality.
 * @dev It allows for the configuration of rate limits for both outbound and inbound directions.
 * @dev It also allows for the setting of the rate limit accounting type to be net or gross.
 */
contract SkyOFTAdapterMintBurn is SkyOFTCore {
    using SafeERC20 for IERC20;

    /**
     * @notice Initializes the SkyOFTAdapterMintBurn contract.
     *
     * @param _token The address of the underlying ERC20 token.
     * @param _lzEndpoint The LayerZero endpoint address.
     * @param _delegate The address of the delegate.
     */
    constructor(
        address _token,
        address _lzEndpoint,
        address _delegate
    ) SkyOFTCore(_token, _lzEndpoint, _delegate) {}

    /**
     * @notice Returns the balance of fees accumulated in the contract.
     * @return amountLD The balance of fees in local decimals.
     *
     * @dev This function is used to check the fee balance before withdrawal.
     */
    function feeBalance() public view returns (uint256 amountLD) {
        return innerToken.balanceOf(address(this));
    }

    /**
     * @notice Withdraws accumulated fees to a specified address.
     * @param _to The address to which the fees will be withdrawn.
     * @param _amountLD The amount of tokens to withdraw in local decimals.
     *
     * @dev This also allows for owner to rescue tokens that are otherwise burned/lost.
     */
    function withdrawFees(address _to, uint256 _amountLD) external onlyOwner {
        uint256 balance = feeBalance();
        if (_amountLD > balance) revert InsufficientFeeBalance(_amountLD, balance);

        innerToken.safeTransfer(_to, _amountLD);
        emit FeesWithdrawn(_to, _amountLD);
    }

    /**
     * @notice Burns tokens from the sender's balance to prepare for sending.
     *
     * @param _from The address to debit the tokens from.
     * @param _amountLD The amount of tokens to send in local decimals.
     * @param _minAmountLD The minimum amount to send in local decimals.
     * @param _dstEid The destination chain ID.
     *
     * @return amountSentLD The amount sent in local decimals.
     * @return amountReceivedLD The amount received in local decimals on the remote.
     */
    function _debit(
        address _from,
        uint256 _amountLD,
        uint256 _minAmountLD,
        uint32 _dstEid
    ) internal override returns (uint256 amountSentLD, uint256 amountReceivedLD) {
        (amountSentLD, amountReceivedLD) = _debitView(_amountLD, _minAmountLD, _dstEid);

        // @dev We are using amountReceivedLD because that is the amount of tokens leaving the chain.
        // @dev The fee remains on this chain, thus it is not included in the rate limit check.
        _checkAndUpdateRateLimit(_dstEid, amountReceivedLD, RateLimitDirection.Outbound);

        // @dev Burn the total amount sent, and mint the difference (i.e. the fee) to this contract.
        IMintBurnVoidReturn(token()).burn(_from, amountSentLD);

        // @dev Conditionally handle the fee.
        uint256 fee = amountSentLD - amountReceivedLD;
        if (fee > 0) IMintBurnVoidReturn(token()).mint(address(this), fee);
    }

    /**
     * @notice Mints tokens to the recipient.
     * @param _to The address to credit the tokens to.
     * @param _amountLD The amount of tokens to credit in local decimals.
     * @param _srcEid The source Endpoint ID.
     *
     * @return amountReceivedLD The amount of tokens actually received in local decimals.
     */
    function _credit(
        address _to,
        uint256 _amountLD,
        uint32 _srcEid
    ) internal virtual override whenNotPaused returns (uint256 amountReceivedLD) {
        // @dev Check and update the rate limit based on the source endpoint ID (srcEid).
        _checkAndUpdateRateLimit(_srcEid, _amountLD, RateLimitDirection.Inbound);

        // @dev If recipient is the zero address or the inner token, reroute to the dead address.
        if (_to == address(0) || _to == token()) _to = address(0xdead);

        // @dev Mints the tokens to the recipient.
        IMintBurnVoidReturn(token()).mint(_to, _amountLD);

        return _amountLD;
    }
}
