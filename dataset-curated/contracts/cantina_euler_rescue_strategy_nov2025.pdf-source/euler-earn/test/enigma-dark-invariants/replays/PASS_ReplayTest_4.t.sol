// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Libraries
import "forge-std/Test.sol";
import "forge-std/console.sol";

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

    function test_replay_4_setFeeRecipient() public {
        vm.skip(true);
        // PASS
        _setUpActor(USER1);
        Tester.deposit(1, 0, 1);
        Tester.setSupplyQueue(1, 0);
        Tester.deposit(100, 0, 2);
        Tester.donateSharesToEulerEarn(1, 1, 0);
        Tester.setFeeRecipient(true, 0);
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                         COVERAGE TESTS                                    //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    function test_liquidiationCoverage() public {
        vm.skip(true);
        Tester.deposit(20 ether, 0, 0);
        Tester.deposit(1 ether, 1, 1);
        Tester.borrow(0.7 ether, 0, 0);
        Tester.borrow(0.1 ether, 0, 0);
        Tester.setPrice(0.2 ether, 0);
        _setUpActor(USER2);
        Tester.enableController(1, 0);
        Tester.liquidate(0.01 ether, 0, 0, 0);
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
