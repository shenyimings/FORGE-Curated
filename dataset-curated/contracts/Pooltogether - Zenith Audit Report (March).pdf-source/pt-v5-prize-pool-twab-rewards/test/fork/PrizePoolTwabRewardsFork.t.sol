// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import { console } from "forge-std/console.sol";
import { IERC20 } from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import { IMintableERC20 } from "./utils/IMintableERC20.sol";
import { TwabController } from "pt-v5-twab-controller/TwabController.sol";

import {
    IPrizePool,
    PrizePoolTwabRewards,
    TwabControllerZeroAddress,
    TokensReceivedLessThanExpected,
    ZeroTokensPerEpoch,
    ZeroEpochs,
    PayeeZeroAddress,
    GracePeriodActive,
    ExceedsMaxEpochs,
    RewardsAlreadyClaimed,
    PromotionInactive,
    OnlyPromotionCreator,
    EpochNotOver,
    InvalidEpochId
} from "../../src/PrizePoolTwabRewards.sol";
import { Promotion } from "../../src/interfaces/IPrizePoolTwabRewards.sol";

interface IPrizePoolExtended is IPrizePool {
    function contributePrizeTokens(address _prizeVault, uint256 _amount) external returns (uint256);
}

contract PrizePoolTwabRewardsForkTest is Test {
    /* ============ Fork Vars ============ */

    uint256 public blockNumber = 130421927;

    address public twabControllerAddress = address(0xCB0672dE558Ad8F122C0E081f0D35480aB3be167);
    address public prizePoolAddress = address(0xF35fE10ffd0a9672d0095c435fd8767A7fe29B55);

    IMintableERC20 public opToken = IMintableERC20(address(0x4200000000000000000000000000000000000042));
    IMintableERC20 public poolToken = IMintableERC20(address(0x395Ae52bB17aef68C2888d941736A71dC6d4e125));
    IMintableERC20 public wethToken = IMintableERC20(address(0x4200000000000000000000000000000000000006));

    address public opMinter = address(0x5C4e7Ba1E219E47948e6e3F55019A647bA501005);
    address public poolMinter = address(0x4200000000000000000000000000000000000010);

    /* ============ Variables ============ */

    PrizePoolTwabRewards public twabRewards;
    TwabController public twabController = TwabController(twabControllerAddress);
    IPrizePoolExtended public prizePool = IPrizePoolExtended(prizePoolAddress);

    address public vault1;
    address public vault2;

    address public wallet1;
    address public wallet2;
    address public wallet3;

    uint public currentDrawId;

    /* ============ Set Up ============ */

    function setUp() public {
        uint256 optimismFork = vm.createFork(vm.rpcUrl("optimism"), blockNumber);
        vm.selectFork(optimismFork);

        twabRewards = new PrizePoolTwabRewards(twabController, prizePool);

        vault1 = makeAddr("vault1");
        vault2 = makeAddr("vault2");

        wallet1 = makeAddr("wallet1");
        wallet2 = makeAddr("wallet2");
        wallet3 = makeAddr("wallet3");

        currentDrawId = (block.timestamp - prizePool.firstDrawOpensAt()) / prizePool.drawPeriodSeconds();

        deal(address(wethToken), address(this), 10000e18);
    }

    function test() public {
        uint40 startTimestamp = uint40(prizePool.firstDrawOpensAt() + (currentDrawId + 1) * prizePool.drawPeriodSeconds());
        uint40 epochDuration = uint40(prizePool.drawPeriodSeconds() * 7); // 7 draws

        vm.prank(opMinter);
        opToken.mint(address(this), 1000e18 * 10);
        opToken.approve(address(twabRewards), 1000e18 * 10);
        uint promotionId = twabRewards.createPromotion(
            opToken,
            startTimestamp,
            1000e18,
            epochDuration, // weekly
            10
        );

        // go to start of promotion
        vm.warp(startTimestamp);

        // mint for users
        vm.startPrank(vault1);
        twabController.mint(wallet1, 1e18);
        twabController.mint(wallet2, 1e18);
        vm.stopPrank();
        vm.startPrank(vault2);
        twabController.mint(wallet1, 1e18);
        twabController.mint(wallet2, 1e18);
        vm.stopPrank();

        // contribute to prize pool evenly
        wethToken.transfer(address(prizePool), 2e18);
        prizePool.contributePrizeTokens(vault1, 1e18);
        prizePool.contributePrizeTokens(vault2, 1e18);

        uint8[] memory epochIds = new uint8[](1);
        uint24 epochStartDrawId;
        uint24 epochEndDrawId;

        // go to end of promotion epoch 0
        vm.warp(startTimestamp + epochDuration);
        epochIds[0] = 0;

        // claim for each user
        (
            ,
            ,
            epochStartDrawId,
            epochEndDrawId  
        ) = twabRewards.epochRangesForPromotion(promotionId, 0);
        uint256 totalContributed = prizePool.getTotalContributedBetween(epochStartDrawId, epochEndDrawId);
        // claim for vault1 + wallet1
        assertEq((500e18*1e18)/totalContributed, twabRewards.claimRewards(vault1, wallet1, promotionId, epochIds));
        // claim for vault2 + wallet2
        assertEq((500e18*1e18)/totalContributed, twabRewards.claimRewards(vault2, wallet2, promotionId, epochIds));

        // Go to end of promotion epoch 1
        vm.warp(startTimestamp + epochDuration * 2);
        epochIds[0] = 1;

        // Assert no one received rewards
        assertEq(0, twabRewards.claimRewards(vault1, wallet1, promotionId, epochIds));
        assertEq(0, twabRewards.claimRewards(vault2, wallet1, promotionId, epochIds));
        assertEq(0, twabRewards.claimRewards(vault1, wallet2, promotionId, epochIds));
        assertEq(0, twabRewards.claimRewards(vault2, wallet2, promotionId, epochIds));

        // contribute only for vault1
        wethToken.transfer(address(prizePool), 11e18);
        prizePool.contributePrizeTokens(vault1, 11e18);

        // Go to end of promotion epoch 2
        vm.warp(startTimestamp + epochDuration * 4);
        epochIds[0] = 2;

        uint8[] memory epochIds2 = new uint8[](2);
        epochIds2[0] = 2;
        epochIds2[1] = 3;
        // claim for vault1
        (
            ,
            ,
            epochStartDrawId,
            epochEndDrawId
        ) = twabRewards.epochRangesForPromotion(promotionId, 2);
        totalContributed = prizePool.getTotalContributedBetween(epochStartDrawId, epochEndDrawId);
        assertEq((500e18*11e18)/totalContributed, twabRewards.claimRewards(vault1, wallet1, promotionId, epochIds2));

        // assert vault2 is zero
        assertEq(0, twabRewards.claimRewards(vault2, wallet1, promotionId, epochIds));
        assertEq(0, twabRewards.claimRewards(vault2, wallet2, promotionId, epochIds));
    }
}
