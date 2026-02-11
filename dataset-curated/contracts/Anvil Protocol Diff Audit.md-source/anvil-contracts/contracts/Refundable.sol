// SPDX-License-Identifier: ISC
pragma solidity 0.8.25;

/**
 * @title Base contract that can be extended to pull in `refundExcess` modifier, which ensures that the ETH balance of a
 * contract is not increased as a result of a function call.
 *
 * @custom:security-contact security@af.xyz
 */
abstract contract Refundable {
    /**
     * @dev refunds excess ETH to the caller after an operation such that the contract's ETH balance cannot be increased
     * as a result of the operation.
     */
    modifier refundExcess() {
        uint256 startingBalance = address(this).balance;

        _;

        uint256 expectedEndingBalance = startingBalance - msg.value;
        if (address(this).balance > expectedEndingBalance) {
            payable(msg.sender).transfer(address(this).balance - expectedEndingBalance);
        }
    }
}
