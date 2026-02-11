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
import {FlowCaps} from "src/interfaces/IPublicAllocator.sol";

contract ReplayTest1 is Invariants, Setup {
    // Generated from Echidna reproducers

    // Target contract instance (you may need to adjust this)
    ReplayTest1 Tester = this;

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

    function test_replay_1_withdrawEEV() public {
        vm.skip(true);
        // PASS
        _setUpActor(USER1);
        Tester.mintEEV(310845, 0, 0);
        Tester.deposit(125, 0, 3);
        Tester.donateSharesToEulerEarn(3, 2, 1);
        Tester.setSupplyQueue(0, 2);
        Tester.assert_ERC4626_ROUNDTRIP_INVARIANT_E(307012, 0);
        Tester.mintEEV(236342, 0, 1);
        Tester.withdrawEEV(22126, 0, 1);
    }

    function test_replay_1_redeemEEV() public {
        _setUpActor(USER1);
        _delay(31594);
        Tester.depositEEV(1524785991, 118, 252);
        _setUpActor(USER2);
        _delay(66543);
        Tester.submitCap(4370001, 0, 11);
        _setUpActor(USER3);
        _delay(390247);
        Tester.deposit(4370000, 236, 215);
        _setUpActor(USER1);
        _delay(127251);
        Tester.depositEEV(763, 170, 255);
        _delay(292304);
        Tester.mintEEV(4369999, 158, 71);
        _setUpActor(USER2);
        _delay(566039);
        Tester.assert_ERC4626_DEPOSIT_INVARIANT_C(26);
        _setUpActor(USER3);
        _delay(436727);
        Tester.donateSharesToEulerEarn(691, 185, 49);
        _delay(4177);
        Tester.redeemEEV(4370001, 255, 255);
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
