// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IPriceOracle} from "../interfaces/IPriceOracle.sol";

contract MockPriceOracle is IPriceOracle {
    mapping(address => uint256) quotes;
    mapping(address => bool) doRevert;

    string public name = "MockPriceOracle";
    address public quote = address(1);
    uint256 public quoteAmount;
    string revertMsg = "oops";

    constructor() {
        quotes[0x620cE1130f7c63457784cdFA31cfcCBFb6bE5029] = 1e18;
        quotes[0x4D5627C9F87b094A0a78A9FED0027E1A701bE0ea] = 1e18;
        quotes[0x2442cA14d1217b4dD503e47DFdF79b774b56Ea89] = 1e18;
        quotes[0x10f8d8422A36BA75Ae3381815eA72638dDa0088C] = 1e18;
    }

    function setRevert(address addr, bool _doRevert) external {
        doRevert[addr] = _doRevert;
    }

    function setQuote(address base, uint256 _quoteAmount) external {
        quotes[base] = _quoteAmount;
    }

    function isBaseSupported(address base) external view returns (bool) {
        return true;
    }

    function getQuote(uint256, address base) external view returns (uint256 outAmount) {
        if (doRevert[base]) revert(revertMsg);
        return quotes[base];
    }
}
