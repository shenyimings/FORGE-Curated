// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.29;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ETH_ADDRESS, ALT_ETH_ADDRESS} from "./Constants.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

library TokenUtils {
    using SafeERC20 for ERC20;

    function getDecimals(address token) internal view returns (uint8 decimals) {
        decimals = (token == ETH_ADDRESS || token == ALT_ETH_ADDRESS) ?
            18 : ERC20(token).decimals();
        require(decimals <= 18);
    }

    function tokenBalance(address token) internal view returns (uint256) {
        return
            token == ETH_ADDRESS
                ? address(this).balance
                : ERC20(token).balanceOf(address(this));
    }

    function checkApprove(ERC20 token, address spender, uint256 amount) internal {
        if (address(token) == address(0)) return;

        token.forceApprove(spender, amount);
    }

    function checkRevoke(ERC20 token, address spender) internal {
        if (address(token) == address(0)) return;
        token.forceApprove(spender, 0);
    }

    function checkReturnCode() internal pure returns (bool success) {
        uint256[1] memory result;
        assembly {
            switch returndatasize()
                case 0 {
                    // This is a non-standard ERC-20
                    success := 1 // set success to true
                }
                case 32 {
                    // This is a compliant ERC-20
                    returndatacopy(result, 0, 32)
                    success := mload(result) // Set `success = returndata` of external call
                }
                default {
                    // This is an excessively non-compliant ERC-20, revert.
                    revert(0, 0)
                }
        }
    }
}