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

    function randomActor(address[] memory _actors, uint256 actorIndexSeed) public pure returns (address) {
        return _actors[bound(actorIndexSeed, 0, _actors.length - 1)];
    }

    function randomActor(uint256 actorIndexSeed, address actor1, address actor2) public pure returns (address) {
        address[] memory _actors = new address[](2);
        _actors[0] = actor1;
        _actors[1] = actor2;
        return randomActor(_actors, actorIndexSeed);
    }

    function randomActor(uint256 actorIndexSeed, address actor1, address actor2, address actor3)
        public
        pure
        returns (address)
    {
        address[] memory _actors = new address[](3);
        _actors[0] = actor1;
        _actors[1] = actor2;
        _actors[2] = actor3;
        return randomActor(_actors, actorIndexSeed);
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
