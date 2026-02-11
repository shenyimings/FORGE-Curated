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

contract ReplayTest3 is Invariants, Setup {
    // Generated from Echidna reproducers

    // Target contract instance (you may need to adjust this)
    ReplayTest3 Tester = this;

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

    function test_replay_3_echidna_INV_ACCOUNTING() public {
        // PASS
        _setUpActor(USER1);
        Tester.mintEEV(4208688, 0, 1); // mint 4208688 eulerEarn 2 shares to actor 1
        Tester.setCaps(1, 35, 99); // set supply cap to 1 and borrow cap to 35 on eTST3 vault
        Tester.mintEEV(138084516, 21, 14); // mint 138084516 eulerEarn 1 shares to actor 3
        Tester.deposit(5834850, 60, 0); // deposit 5834850 collateralTokens to eTST vault for actor 1
        Tester.borrow(2245910, 15, 0); // borrow 2245910 loanTokens from eTST2 vault onBehalf of actor 1
        _delay(169877); // fast forward 169877 seconds
        Tester.assert_ERC4626_DEPOSIT_INVARIANT_C(0); // deposit 2199999999999999857706762 loanTokens to eulerEarn 1 on behalf of actor 1, redeem 2199999999999999857706762 shares from eulerEarn 1
        Tester.submitCap(1, 1, 9); // submit cap to 1 for eTST2 market on eulerEarn 2
        Tester.assert_ERC4626_WITHDRAW_INVARIANT_C(0); // withdraw 2245910 loanTokens from eulerEarn 1 on behalf of actor 1
        console.log("##### Pre-last call");
        console.log("lastTotalAssets", eulerEarn.lastTotalAssets());
        console.log("lostAssets", eulerEarn.lostAssets());
        console.log("totalAssets", eulerEarn.totalAssets());

        Tester.assert_ERC4626_DEPOSIT_INVARIANT_C(0); // deposit 2099999999999999998037255 loanTokens to eulerEarn 1 on behalf of actor 1, redeem 2099997900002099995937259 shares from eulerEarn 1
        console.log("##### eulerEarn(1)", address(eulerEarn));
        console.log("##### eulerEarn(2)", address(eulerEarn2));
        console.log("##### Post-last call");
        console.log("lastTotalAssets", eulerEarn.lastTotalAssets());
        console.log("lostAssets", eulerEarn.lostAssets());
        console.log("totalAssets", eulerEarn.totalAssets()); // reverts here
        echidna_INV_ACCOUNTING();

        // eulerEarn 1 totalAssets() reverting -> _accruedFeeAndAssets()
        // lastTotalAssets < lostAssets
        //
        // lastTotalAssets == 2,
        // lostAssets == 3
    }

    function test_replay_3_echidna_ERC4626_USERS() public {
        // PASS
        vm.skip(true);
        _setUpActor(USER1);
        _delay(33605);
        Tester.deposit(1524785993, 45, 255);
        _setUpActor(USER2);
        _delay(135921);
        Tester.mintEEV(1524785992, 255, 255);
        _delay(490448);
        Tester.setCaps(962, 10439, 255);
        _setUpActor(USER3);
        _delay(112444);
        Tester.submitCap(1524785991, 255, 52);
        _setUpActor(USER2);
        _delay(322247);
        Tester.mintEEV(1524785993, 44, 232);
        _setUpActor(USER1);
        _delay(525476);
        Tester.deposit(1524785991, 255, 164);
        _delay(414579);
        Tester.borrow(4370001, 244, 86);
        _delay(332369);
        Tester.assert_ERC4626_DEPOSIT_INVARIANT_C(12);
        _setUpActor(USER3);
        _delay(414579);
        Tester.submitCap(121, 184, 40);
        _delay(401699);
        Tester.assert_ERC4626_WITHDRAW_INVARIANT_C(32);
        _setUpActor(USER1);
        _delay(136392);
        Tester.assert_ERC4626_REDEEM_INVARIANT_C(255);
        _setUpActor(USER2);
        _delay(415353);
        Tester.assert_ERC4626_WITHDRAW_INVARIANT_C(249);
        _setUpActor(USER3);
        _delay(439544);
        Tester.assert_ERC4626_DEPOSIT_INVARIANT_C(252);
        echidna_ERC4626_USERS();
    }

    function test_replay_3_echidna_ERC4626_ASSETS_INVARIANTS() public {
        // PASS
        vm.skip(true);
        _setUpActor(USER1);
        Tester.deposit(106000752, 24, 255);
        Tester.mintEEV(45986645, 49, 5);
        Tester.setCaps(962, 10439, 255);
        Tester.mintEEV(147752070, 27, 18);
        Tester.deposit(1524785991, 255, 164);
        Tester.borrow(2337559, 51, 4);
        _delay(111369);
        Tester.assert_ERC4626_DEPOSIT_INVARIANT_C(0);
        Tester.submitCap(108, 76, 20);
        Tester.assert_ERC4626_WITHDRAW_INVARIANT_C(0);
        _delay(127154);
        Tester.assert_ERC4626_DEPOSIT_INVARIANT_C(0);
        echidna_ERC4626_ASSETS_INVARIANTS();
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
