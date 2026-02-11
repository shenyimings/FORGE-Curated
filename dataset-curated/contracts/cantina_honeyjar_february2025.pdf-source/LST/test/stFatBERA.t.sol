// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import {Test, console2} from "forge-std/Test.sol";
import {StdCheats} from "forge-std/StdCheats.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {StakedFatBERAV2} from "../src/StakedFatBERAV2.sol";
import {fatBERA as FatBERA} from "../src/fatBERA.sol";

contract stFatBERATest is Test {
    StakedFatBERAV2 public stFatBERA;
    FatBERA public fatBERA = FatBERA(0xBAE11292A3E693aF73651BDa350D752AE4A391D4);
    IERC20 public wbera = IERC20(0x6969696969696969696969696969696969696969);
    address public fbnotifier = 0x73e34207C4d35e6c7Bf7D23B8ADD6975aa8049B7;

    // ------------------------------------------------------------------------
    address owner = makeAddr("owner");
    address user = makeAddr("user");
    address operator = makeAddr("operator");
    address treasury = makeAddr("treasury");
    // ------------------------------------------------------------------------

    function setUp() public {
        vm.createSelectFork("https://rpc.berachain.com", 4048939);

        vm.startPrank(owner);
        bytes memory initData = abi.encodeWithSelector(StakedFatBERAV2.initialize.selector, owner, address(fatBERA));
        stFatBERA = StakedFatBERAV2(Upgrades.deployUUPSProxy("StakedFatBERAV2.sol:StakedFatBERAV2", initData));
        stFatBERA.grantRole(stFatBERA.OPERATOR_ROLE(), operator);
        stFatBERA.setTreasury(treasury);
        stFatBERA.setExitFee(50); // 0.5%
        vm.stopPrank();

        vm.label(address(stFatBERA), "stFatBERA");
        vm.label(address(fatBERA), "fatBERA");
        vm.label(address(wbera), "wbera");
        vm.label(owner, "owner");
        vm.label(user, "user");
        vm.label(treasury, "treasury");
        vm.label(operator, "operator");

        // already credit wbera to user
        StdCheats.deal(address(wbera), user, 100 ether);
        StdCheats.deal(address(wbera), fbnotifier, type(uint256).max);

        // pre-approve fatBERA to fbnotifier
        vm.prank(fbnotifier);
        wbera.approve(address(fatBERA), type(uint256).max);
    }

    function test_depositShouldResultInOneToOne() public {
        uint256 AMOUNT_TO_DEPOSIT = 100 ether;
        uint256 AMOUNT_WITH_FEE = 99.5 ether;
        vm.startPrank(user);

        // first deposit into fatBERA
        wbera.approve(address(fatBERA), AMOUNT_TO_DEPOSIT);
        uint256 minted = fatBERA.deposit(AMOUNT_TO_DEPOSIT, user);

        // then deposit the fatBERA into stFatBERA
        fatBERA.approve(address(stFatBERA), minted);
        stFatBERA.deposit(minted, user);

        vm.stopPrank();

        assertEq(stFatBERA.balanceOf(user), AMOUNT_TO_DEPOSIT);
        assertEq(stFatBERA.previewRedeem(minted), AMOUNT_WITH_FEE);
    }

    function test_compoundingSingleUser() public {
        uint256 AMOUNT_TO_DEPOSIT = 100 ether;
        // deposit into fatBERA and then into stFatBERA
        vm.startPrank(user);
        wbera.approve(address(fatBERA), AMOUNT_TO_DEPOSIT);
        uint256 minted = fatBERA.deposit(AMOUNT_TO_DEPOSIT, user);
        fatBERA.approve(address(stFatBERA), minted);
        stFatBERA.deposit(minted, user);
        vm.stopPrank();

        // accrue rewards to fatBERA and then notify fatBERA
        vm.prank(fbnotifier);
        // we credit with alot of rewards because it should be distributed equally amongst
        // all fatBERA users so a small quantity only will drip to stFatBERA users
        fatBERA.notifyRewardAmount(address(wbera), 1000 ether);
        vm.warp(block.timestamp + 7 days);

        // compound stFatBERA
        vm.prank(operator);
        stFatBERA.compound();
        assertGt(
            fatBERA.balanceOf(address(stFatBERA)), AMOUNT_TO_DEPOSIT, "stFatBERA's FatBERa holdings should increase"
        );

        // user should be owed slightly more than the original 100 bera
        assertGt(stFatBERA.previewRedeem(minted), AMOUNT_TO_DEPOSIT, "user should be owed more than original deposit");
    }
}
