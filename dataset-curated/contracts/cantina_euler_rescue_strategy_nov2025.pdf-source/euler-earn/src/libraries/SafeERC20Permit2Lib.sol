// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import {IAllowanceTransfer} from "../interfaces/IAllowanceTransfer.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";

/// @title SafeERC20Permit2Lib Library
/// @custom:security-contact security@euler.xyz
/// @author Euler Labs (https://www.eulerlabs.com/)
/// @notice The library provides a helper for ERC20 approvals and transfers with use of Permit2
library SafeERC20Permit2Lib {
    function forceApproveMaxWithPermit2(IERC20 token, address spender, address permit2) internal {
        if (permit2 == address(0)) {
            SafeERC20.forceApprove(token, spender, type(uint256).max);
        } else {
            if (token.allowance(address(this), permit2) == 0) {
                SafeERC20.forceApprove(token, permit2, type(uint256).max);
            }
            IAllowanceTransfer(permit2).approve(address(token), spender, type(uint160).max, type(uint48).max);
        }
    }

    function revokeApprovalWithPermit2(IERC20 token, address spender, address permit2) internal {
        if (permit2 == address(0)) {
            if (!trySafeApprove(token, spender, 0)) {
                trySafeApprove(token, spender, 1);
            }
        } else {
            IAllowanceTransfer(permit2).approve(address(token), spender, 0, 0);
        }
    }

    function safeTransferFromWithPermit2(IERC20 token, address from, address to, uint256 value, address permit2)
        internal
    {
        uint160 permit2Amount;
        uint48 permit2Expiration;

        if (permit2 != address(0)) {
            (permit2Amount, permit2Expiration,) =
                IAllowanceTransfer(permit2).allowance(from, address(token), address(this));
        }

        if (permit2Amount >= value && permit2Expiration >= block.timestamp) {
            // it's safe to down-cast value to uint160
            IAllowanceTransfer(permit2).transferFrom(from, to, uint160(value), address(token));
        } else {
            SafeERC20.safeTransferFrom(token, from, to, value);
        }
    }

    function trySafeApprove(IERC20 token, address to, uint256 value) internal returns (bool) {
        (bool success, bytes memory data) = address(token).call(abi.encodeCall(IERC20.approve, (to, value)));
        return success && (data.length == 0 || abi.decode(data, (bool)));
    }
}
