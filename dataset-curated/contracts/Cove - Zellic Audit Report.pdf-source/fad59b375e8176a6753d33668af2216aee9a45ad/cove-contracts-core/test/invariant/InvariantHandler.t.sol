// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import { Test } from "forge-std/Test.sol";
import { console } from "forge-std/console.sol";

contract InvariantHandler is Test {
    address[] public actors;
    address internal currentActor;

    constructor(uint256 actorCount) {
        // Create actors and fund them with 100 ether
        if (actorCount != 0) {
            console.log("InvariantHandler: Creating %d actors", actorCount);
            actors = new address[](actorCount);
            for (uint256 i = 0; i < actorCount; i++) {
                string memory name = string.concat("actor-", vm.toString(i));
                actors[i] = makeAddr(name);
                vm.deal(actors[i], 100 ether);
            }
        } else {
            // If no actors are created, log a message
            console.log("InvariantHandler: No actors created");
        }
    }

    modifier useActor(uint256 actorIndexSeed) {
        {
            uint256 idx = bound(actorIndexSeed, 0, actors.length - 1);
            console.log("InvariantHandler: Using actor %d", idx);
            currentActor = actors[idx];
        }
        vm.stopPrank();
        vm.startPrank(currentActor);
        _;
        vm.stopPrank();
        currentActor = address(this);
    }
}
