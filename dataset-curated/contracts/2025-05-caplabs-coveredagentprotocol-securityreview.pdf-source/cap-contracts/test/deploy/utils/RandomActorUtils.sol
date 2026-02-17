// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { StdCheats } from "forge-std/StdCheats.sol";
import { StdUtils } from "forge-std/StdUtils.sol";

contract RandomActorUtils is StdUtils, StdCheats {
    address[] private actors;

    constructor(address[] memory _actors) {
        if (_actors.length == 0) {
            revert("No actors provided");
        }
        actors = _actors;
    }

    function randomActor(uint256 actorIndexSeed) public view returns (address) {
        return actors[bound(actorIndexSeed, 0, actors.length - 1)];
    }

    function randomActorExcept(uint256 actorIndexSeed, address except) public view returns (address) {
        address[] memory filteredActors = new address[](actors.length - 1);
        uint256 index = 0;
        for (uint256 i = 0; i < actors.length; i++) {
            if (actors[i] != except) {
                filteredActors[index] = actors[i];
                index++;
            }
        }
        if (filteredActors.length == 0) {
            revert("No actors left");
        }

        return filteredActors[bound(actorIndexSeed, 0, filteredActors.length - 1)];
    }
}
