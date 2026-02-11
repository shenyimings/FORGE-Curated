// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {ReentrancyGuard} from "../../openzeppelin/security/ReentrancyGuard.sol";
import {Transfers} from "../../utils/library/Transfers.sol";


contract TransfersMock is ReentrancyGuard {
    receive() external payable {
    }

    function transferNAT(address payable _recipient, uint256 _amount)
        external
        nonReentrant
    {
        Transfers.transferNAT(_recipient, _amount);
    }

    function transferNATNoGuard(address payable _recipient, uint256 _amount)
        external
    {
        Transfers.transferNAT(_recipient, _amount);
    }
}
