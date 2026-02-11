pragma solidity ^0.8.17;

import { StdInvariant } from "forge-std/StdInvariant.sol";

import { Base } from "../Base.sol";
import { SwapperHandler as Handler } from "./handlers/SwapperHandler.sol";

import { MockERC20 } from "@mocks/MockERC20.sol";

contract SwapperInvariant is StdInvariant, Base {
    Handler internal h;

    uint256 internal initialLockAmount;

    function setUp() public override {
        super.setUp();

        h = new Handler(swapper, merkleTreeHelper, swapActionsBuilder);

        targetContract(address(h));

        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = Handler.claimAndSwap.selector;
        FuzzSelector memory a = FuzzSelector(address(h), selectors);
        targetSelector(a);

        initialLockAmount = escrow.totalLocked();
    }

    function invariant_SwapperShouldNotHoldAnyTokens() public view {
        assertEq(escrowToken.balanceOf(address(swapper)), 0);

        address[] memory rewardTokens = h.allRewardTokens();
        address[] memory outTokens = h.allOutTokens();

        for (uint256 i = 0; i < rewardTokens.length; i++) {
            assertEq(MockERC20(rewardTokens[i]).balanceOf(address(swapper)), 0);
        }

        for (uint256 i = 0; i < outTokens.length; i++) {
            assertEq(MockERC20(outTokens[i]).balanceOf(address(swapper)), 0);
        }
    }

    function invariant_TotalLockedCorrectAmount() public view {
        assertEq(initialLockAmount + h.weightedSum() / 100, escrow.totalLocked());
    }

    function invariant_ActorLockedAndBalanceCorrectAmount() public view {
        address[] memory actors = h.allActors();

        for (uint256 i = 0; i < actors.length; i++) {
            address actor = actors[i];

            Handler.ActorData memory data = h.getActorData(actor);

            uint256 totalLockedByActor = 0;
            for (uint256 j = 0; j < data.tokenIds.length; j++) {
                totalLockedByActor += escrow.locked(data.tokenIds[j]).amount;
            }

            assertEq(data.weightedSum / 100, totalLockedByActor);
            assertEq(data.tokenAmountGained - data.weightedSum / 100, escrowToken.balanceOf(actor));
        }
    }
}
