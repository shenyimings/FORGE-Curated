// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.25;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

contract LayoutV1 is Initializable {
    struct Account {
        uint balance;
    }

    mapping (address => Account) public accounts;

    uint gap;

    function initialize() public initializer {}

    function setAccount(address account, Account memory accountInfo) public {
        accounts[account].balance = accountInfo.balance;
    }
}