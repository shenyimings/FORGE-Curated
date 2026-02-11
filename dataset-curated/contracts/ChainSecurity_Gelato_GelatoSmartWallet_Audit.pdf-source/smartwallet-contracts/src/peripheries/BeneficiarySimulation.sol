// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {IERC20} from "../interfaces/IERC20.sol";
import {NATIVE_TOKEN} from "../types/Constants.sol";

contract BeneficiarySimulations {
    receive() external payable {}

    function callAndGetPayment(address to, bytes calldata data, address token)
        external
        returns (uint256)
    {
        uint256 balanceBefore = _getBalance(token);

        (bool success, bytes memory result) = to.call(data);
        if (!success) {
            assembly {
                revert(add(result, 32), mload(result))
            }
        }

        return _getBalance(token) - balanceBefore;
    }

    function _getBalance(address token) internal view returns (uint256) {
        if (token == NATIVE_TOKEN) {
            return address(this).balance;
        }
        return IERC20(token).balanceOf(address(this));
    }
}
