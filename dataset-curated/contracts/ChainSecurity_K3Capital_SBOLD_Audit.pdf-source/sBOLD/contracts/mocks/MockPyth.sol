// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {PythStructs} from "@pythnetwork/pyth-sdk-solidity/PythStructs.sol";

contract MockPyth {
    PythStructs.Price price;
    bool doRevert;
    string revertMsg = "oops";

    function setPrice(PythStructs.Price memory _price) external {
        price = _price;
    }

    function setRevert(bool _doRevert) external {
        doRevert = _doRevert;
    }

    function getPriceUnsafe(bytes32) external view returns (PythStructs.Price memory) {
        if (doRevert) revert(revertMsg);
        return price;
    }
}
