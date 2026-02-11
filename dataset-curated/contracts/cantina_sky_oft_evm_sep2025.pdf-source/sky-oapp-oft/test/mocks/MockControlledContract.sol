// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.22;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

contract MockControlledContract is Ownable {
    string public data;

    constructor(address _owner) Ownable(_owner) {}

    function setData(string memory _data) external onlyOwner {
        data = _data;
    }
}
