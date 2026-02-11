pragma solidity ^0.8.17;

import { StdUtils } from "forge-std/StdUtils.sol";
import { StdCheats } from "forge-std/StdCheats.sol";
import { CommonBase } from "forge-std/Base.sol";

abstract contract BaseHandler is StdUtils, StdCheats, CommonBase {
    address[] internal actors;

    constructor() {
        for (uint256 i = 0; i < 3; i++) {
            actors.push(address(uint160(0x1000 + i)));
        }
    }

    function useSender(uint256 _seed) public view returns (address) {
        return actors[_bound(_seed, 0, actors.length - 1)];
    }

    function allActors() public view returns (address[] memory) {
        return actors;
    }
}
