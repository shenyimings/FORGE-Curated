// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Libraries
import "forge-std/Test.sol";
import "forge-std/console.sol";
import {FlowCaps} from "src/interfaces/IPublicAllocator.sol";

// Contracts
import {Invariants} from "../Invariants.t.sol";
import {Setup} from "../Setup.t.sol";

// Utils
import {Actor} from "../utils/Actor.sol";

contract ReplayTest4 is Invariants, Setup {
    // Generated from Echidna reproducers

    // Target contract instance (you may need to adjust this)
    ReplayTest4 Tester = this;

    modifier setup() override {
        _;
    }

    function setUp() public {
        // Deploy protocol contracts
        _setUp();

        /// @dev fixes the actor to the first user
        actor = actors[USER1];

        vm.warp(101007);
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                   		REPLAY TESTS                                     //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    function test_replay_4_assert_ERC4626_MINT_INVARIANT_C() public {
        // PASS
        _setUpActor(USER1);
        Tester.mintEEV(39654, 0, 0);
        Tester.deposit(99135, 0, 0);
        Tester.borrow(38393, 0, 0);
        _delay(17073);
        Tester.assert_ERC4626_MINT_INVARIANT_C(0);
    }

    function test_replay_4_reallocateTo() public {
        // PASS
        Tester.submitCap(0, 0, 1);
        Tester.submitCap(0, 0, 0);
        Tester.mintEEV(1, 0, 0);
        Tester.setFlowCaps([FlowCaps(0, 0), FlowCaps(0, 0), FlowCaps(0, 1), FlowCaps(1, 0)]);
        Tester.updateWithdrawQueue([3, 0, 0, 0], 0, 2);
        Tester.reallocateTo(3, 0, [uint128(0), uint128(0), uint128(0), uint128(0)]);
    }

    function test_replay_4_assert_ERC4626_DEPOSIT_INVARIANT_C() public {
        // PASS
        _setUpActor(USER1);
        Tester.mint(395636, 0, 0);
        Tester.submitCap(1, 0, 2);
        Tester.mintEEV(170438, 0, 1);
        Tester.borrow(165229, 0, 2);
        _delay(1054);
        Tester.assert_ERC4626_DEPOSIT_INVARIANT_C(0);
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                           HELPERS                                         //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    /// @notice Fast forward the time and set up an actor,
    /// @dev Use for ECHIDNA call-traces
    function _delay(uint256 _seconds) internal {
        vm.warp(block.timestamp + _seconds);
    }

    /// @notice Set up an actor
    function _setUpActor(address _origin) internal {
        actor = actors[_origin];
    }

    /// @notice Set up an actor and fast forward the time
    /// @dev Use for ECHIDNA call-traces
    function _setUpActorAndDelay(address _origin, uint256 _seconds) internal {
        actor = actors[_origin];
        vm.warp(block.timestamp + _seconds);
    }

    /// @notice Set up a specific block and actor
    function _setUpBlockAndActor(uint256 _block, address _user) internal {
        vm.roll(_block);
        actor = actors[_user];
    }

    /// @notice Set up a specific timestamp and actor
    function _setUpTimestampAndActor(uint256 _timestamp, address _user) internal {
        vm.warp(_timestamp);
        actor = actors[_user];
    }
}
