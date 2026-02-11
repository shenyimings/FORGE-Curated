// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.7.6;

contract IsContract {
    function isAddressContract(address addr) external view returns (bool) {
        // check if the toAddress is a contract. We are not concerned about addresses that pretend to be wallets. because worst case we just delete their payload if being malicious
        // we can guarantee that if a size > 0, then the contract is definitely a contract address in this context
        uint size;
        assembly {
            size := extcodesize(addr)
        }
        return size != 0;
    }
}
