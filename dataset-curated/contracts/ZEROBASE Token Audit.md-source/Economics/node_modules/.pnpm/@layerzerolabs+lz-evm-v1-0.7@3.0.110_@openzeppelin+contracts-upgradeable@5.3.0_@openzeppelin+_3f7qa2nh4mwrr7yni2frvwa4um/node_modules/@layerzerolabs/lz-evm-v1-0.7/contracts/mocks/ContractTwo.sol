// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.7.6;

import "../interfaces/IContractOne.sol";

contract ContractTwo {
    address contractOne;

    constructor(address _contractOne) {
        contractOne = _contractOne;
    }

    function callSetIt(uint _gasLimit) external {
        IContractOne(contractOne).setIt{gas: _gasLimit}(1);
    }
}
