// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import { IERC20 } from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import { ERC20Mock } from "openzeppelin-contracts/mocks/ERC20Mock.sol";
import { FeeERC20 } from "./mocks/FeeERC20.sol";
import { TwabController } from "pt-v5-twab-controller/TwabController.sol";

import {
    PrizePoolTwabRewards,
    IPrizePool,
    TwabControllerZeroAddress,
    PrizePoolZeroAddress,
    TokensReceivedLessThanExpected,
    ZeroTokensPerEpoch,
    EpochDurationLtDrawPeriod,
    ZeroEpochs,
    PayeeZeroAddress,
    GracePeriodActive,
    ExceedsMaxEpochs,
    RewardsAlreadyClaimed,
    PromotionInactive,
    OnlyPromotionCreator,
    EpochNotOver,
    InvalidEpochId,
    EpochDurationLtDrawPeriod,
    EpochDurationNotMultipleOfDrawPeriod,
    StartTimeLtFirstDrawOpensAt,
    StartTimeNotAlignedWithDraws,
    NoEpochsToClaim
} from "../src/PrizePoolTwabRewards.sol";
import { Promotion } from "../src/interfaces/IPrizePoolTwabRewards.sol";
import { ITwabRewards } from "../src/interfaces/ITwabRewards.sol";

contract PrizePoolTwabRewardsTest is Test {
    PrizePoolTwabRewards public twabRewards;
    TwabController public twabController;
    IPrizePool public prizePool;
    ERC20Mock public mockToken;

    uint40 public drawPeriodSeconds = 1 days;
    uint40 public firstDrawOpensAt;

    address wallet1;
    address wallet2;
    address wallet3;

    address vaultAddress;

    uint32 twabPeriodLength = 1 hours;

    uint96 tokensPerEpoch = 10000e18;
    uint40 epochDuration = drawPeriodSeconds * 7; // 1 week
    uint8 numberOfEpochs = 12;

    uint256 promotionId;
    Promotion public promotion;

    /* ============ Events ============ */

    event PromotionCreated(
        uint256 indexed promotionId,
        IERC20 indexed token,
        uint40 startTimestamp,
        uint104 tokensPerEpoch,
        uint40 epochDuration,
        uint8 initialNumberOfEpochs
    );
    event PromotionEnded(uint256 indexed promotionId, address indexed recipient, uint256 amount, uint8 epochNumber);
    event PromotionDestroyed(uint256 indexed promotionId, address indexed recipient, uint256 amount);
    event PromotionExtended(uint256 indexed promotionId, uint256 numberOfEpochs);
    event RewardsClaimed(uint256 indexed promotionId, bytes32 epochClaimFlags, address indexed vault, address indexed user, uint256 amount);

    /* ============ Set Up ============ */

    function setUp() public {
        firstDrawOpensAt = uint40(block.timestamp);
        twabController = new TwabController(twabPeriodLength, uint32(firstDrawOpensAt));
        prizePool = IPrizePool(makeAddr("prizePool"));
        vm.etch(address(prizePool), "prizePool");
        vm.mockCall(address(prizePool), abi.encodeWithSelector(prizePool.drawPeriodSeconds.selector), abi.encode(drawPeriodSeconds));
        vm.mockCall(address(prizePool), abi.encodeWithSelector(prizePool.firstDrawOpensAt.selector), abi.encode(firstDrawOpensAt));
        mockToken = new ERC20Mock();
        twabRewards = new PrizePoolTwabRewards(twabController, prizePool);

        wallet1 = makeAddr("wallet1");
        wallet2 = makeAddr("wallet2");
        wallet3 = makeAddr("wallet3");

        vaultAddress = makeAddr("vault1");

        promotionId = createPromotion();
        promotion = twabRewards.getPromotion(promotionId);
        // Make up the contributions for the promotion
        mockPrizePoolContributions(vaultAddress, 1, 7, 1e18, 1e18);
        mockPrizePoolContributions(vaultAddress, 8, 14, 1e18, 1e18);
        mockPrizePoolContributions(vaultAddress, 15, 21, 1e18, 1e18);
        mockPrizePoolContributions(vaultAddress, 22, 28, 1e18, 1e18);
        mockPrizePoolContributions(vaultAddress, 29, 35, 1e18, 1e18);
        mockPrizePoolContributions(vaultAddress, 36, 42, 1e18, 1e18);
        mockPrizePoolContributions(vaultAddress, 43, 49, 1e18, 1e18);

    }

    /* ============ constructor ============ */

    function testConstructor_PrizePoolZeroAddress() public {
        vm.expectRevert(abi.encodeWithSelector(PrizePoolZeroAddress.selector));
        new PrizePoolTwabRewards(twabController, IPrizePool(address(0)));
    }

    function testConstructor_SetsTwabController() external {
        assertEq(address(twabRewards.twabController()), address(twabController));
    }

    function testConstructor_TwabControllerZeroAddress() external {
        vm.expectRevert(abi.encodeWithSelector(TwabControllerZeroAddress.selector));
        new PrizePoolTwabRewards(TwabController(address(0)), prizePool);
    }

    /* ============ createPromotion ============ */

    function testCreatePromotion_success() external {
        vm.startPrank(wallet1);

        uint256 amount = tokensPerEpoch * numberOfEpochs;
        mockToken.mint(wallet1, amount);
        mockToken.approve(address(twabRewards), amount);

        uint256 _promotionId = 2;
        vm.expectEmit();
        emit PromotionCreated(
            _promotionId,
            IERC20(mockToken),
            firstDrawOpensAt,
            tokensPerEpoch,
            epochDuration,
            numberOfEpochs
        );
        twabRewards.createPromotion(
            mockToken,
            firstDrawOpensAt,
            tokensPerEpoch,
            epochDuration,
            numberOfEpochs
        );
        vm.stopPrank();
    }

    function testCreatePromotion_EpochDurationNotMultipleOfDrawPeriod() public {
        vm.expectRevert(abi.encodeWithSelector(EpochDurationNotMultipleOfDrawPeriod.selector));
        twabRewards.createPromotion(
            mockToken,
            firstDrawOpensAt,
            tokensPerEpoch,
            drawPeriodSeconds + 1,
            numberOfEpochs
        );
    }

    function testCreatePromotion_StartTimeLtFirstDrawOpensAt() public { 
        vm.expectRevert(abi.encodeWithSelector(StartTimeLtFirstDrawOpensAt.selector));
        twabRewards.createPromotion(
            mockToken,
            firstDrawOpensAt - 1,
            tokensPerEpoch,
            drawPeriodSeconds,
            numberOfEpochs
        );
    }

    function testCreatePromotion_FeeTokenFails() external {
        FeeERC20 feeToken = new FeeERC20();
        uint256 amount = tokensPerEpoch * numberOfEpochs;
        feeToken.mint(address(this), amount);
        feeToken.approve(address(twabRewards), amount);

        vm.expectRevert(abi.encodeWithSelector(TokensReceivedLessThanExpected.selector, amount - amount / 100, amount));
        twabRewards.createPromotion(
            feeToken,
            firstDrawOpensAt,
            tokensPerEpoch,
            epochDuration,
            numberOfEpochs
        );
    }

    function testCreatePromotion_ZeroTokensPerEpoch() external {
        uint96 _tokensPerEpoch = 0;
        uint256 amount = _tokensPerEpoch * numberOfEpochs;
        mockToken.mint(address(this), amount);
        mockToken.approve(address(twabRewards), amount);

        vm.expectRevert(abi.encodeWithSelector(ZeroTokensPerEpoch.selector));
        twabRewards.createPromotion(
            mockToken,
            firstDrawOpensAt,
            _tokensPerEpoch,
            epochDuration,
            numberOfEpochs
        );
    }

    function testCreatePromotion_ZeroEpochs() external {
        vm.expectRevert(abi.encodeWithSelector(ZeroEpochs.selector));
        twabRewards.createPromotion(
            mockToken,
            firstDrawOpensAt,
            tokensPerEpoch,
            epochDuration,
            0 // 0 number of epochs
        );
    }

    function testCreatePromotion_EpochDurationLtDrawPeriod() external {
        vm.expectRevert(
            abi.encodeWithSelector(
                EpochDurationLtDrawPeriod.selector
            )
        );
        twabRewards.createPromotion(
            mockToken,
            firstDrawOpensAt,
            tokensPerEpoch,
            twabPeriodLength / 2,
            numberOfEpochs
        );
    }

    function testCreatePromotion_StartTimeNotAlignedWithDraws() external {
        vm.expectRevert(abi.encodeWithSelector(StartTimeNotAlignedWithDraws.selector));
        twabRewards.createPromotion(
            mockToken,
            firstDrawOpensAt + 13,
            tokensPerEpoch,
            epochDuration,
            numberOfEpochs
        );
    }

    /* ============ calculateDrawIdAt ============ */

    function testCalculateDrawIdAt() public {
        assertEq(twabRewards.calculateDrawIdAt(firstDrawOpensAt), 1, "epoch 0");
        assertEq(twabRewards.calculateDrawIdAt(firstDrawOpensAt + epochDuration * 2), 15, "epoch 1");
    }

    /* ============ endPromotion ============ */

    function testEndPromotion_success() public {
        vm.warp(firstDrawOpensAt + epochDuration); // end of first epoch
        uint256 _refundAmount = tokensPerEpoch * (numberOfEpochs - 1); // total less one
        uint256 balanceBefore = mockToken.balanceOf(address(this));
        vm.expectEmit();
        emit PromotionEnded(promotionId, address(this), _refundAmount, 1);
        twabRewards.endPromotion(promotionId, address(this));
    }

    function testEndPromotion_TransfersCorrectAmount() external {
        for (uint8 epochToEndOn = 0; epochToEndOn < numberOfEpochs; epochToEndOn++) {
            uint256 _promotionId = createPromotion();
            vm.warp(firstDrawOpensAt + epochToEndOn * epochDuration);
            uint256 _refundAmount = tokensPerEpoch * (numberOfEpochs - epochToEndOn);

            uint256 balanceBefore = mockToken.balanceOf(address(this));

            vm.expectEmit();
            emit PromotionEnded(_promotionId, address(this), _refundAmount, epochToEndOn);
            twabRewards.endPromotion(_promotionId, address(this));

            uint256 balanceAfter = mockToken.balanceOf(address(this));
            assertEq(balanceAfter - balanceBefore, _refundAmount, "refund amount");

            uint8 latestEpochId = twabRewards.getPromotion(_promotionId).numberOfEpochs;
            assertEq(latestEpochId, twabRewards.getEpochIdNow(_promotionId), "latestEpochId");
        }
    }

    function testEndPromotion_EndBeforeStarted() external {
        uint256 amount = tokensPerEpoch * numberOfEpochs;
        mockToken.mint(address(this), amount);
        mockToken.approve(address(twabRewards), amount);

        uint256 _promotionId = twabRewards.createPromotion(
            mockToken,
            firstDrawOpensAt,
            tokensPerEpoch,
            epochDuration,
            numberOfEpochs
        );
        vm.warp(firstDrawOpensAt - 1); // before started

        uint256 _refundAmount = tokensPerEpoch * numberOfEpochs;
        uint256 balanceBefore = mockToken.balanceOf(address(this));

        vm.expectEmit();
        emit PromotionEnded(_promotionId, address(this), _refundAmount, 0);
        twabRewards.endPromotion(_promotionId, address(this));

        uint256 balanceAfter = mockToken.balanceOf(address(this));
        assertEq(balanceAfter - balanceBefore, _refundAmount);

        uint8 lastEpochId = twabRewards.getPromotion(_promotionId).numberOfEpochs;
        assertEq(lastEpochId, twabRewards.getEpochIdNow(_promotionId));
    }

    function testEndPromotion_UsersCanStillClaim() external {
        uint8 numEpochsPassed = 6;
        uint8[] memory epochIds = new uint8[](6);
        epochIds[0] = 0;
        epochIds[1] = 1;
        epochIds[2] = 2;
        epochIds[3] = 3;
        epochIds[4] = 4;
        epochIds[5] = 5;

        mockPrizePoolContributions(vaultAddress, 1, 7, 1e18, 1e18);
        mockPrizePoolContributions(vaultAddress, 8, 14, 1e18, 1e18);
        mockPrizePoolContributions(vaultAddress, 15, 21, 1e18, 1e18);
        mockPrizePoolContributions(vaultAddress, 22, 28, 1e18, 1e18);
        mockPrizePoolContributions(vaultAddress, 29, 35, 1e18, 1e18);
        mockPrizePoolContributions(vaultAddress, 36, 42, 1e18, 1e18);

        uint256 totalShares = 1000e18;
        vm.startPrank(vaultAddress);
        twabController.mint(wallet1, uint96((totalShares * 3) / 4));
        twabController.mint(wallet2, uint96((totalShares * 1) / 4));
        vm.stopPrank();

        uint256 wallet1RewardAmount = numEpochsPassed * ((tokensPerEpoch * 3) / 4);
        uint256 wallet2RewardAmount = numEpochsPassed * ((tokensPerEpoch * 1) / 4);

        vm.warp(numEpochsPassed * epochDuration + firstDrawOpensAt);

        uint256 _refundAmount = tokensPerEpoch * (numberOfEpochs - numEpochsPassed);
        uint256 balanceBefore = mockToken.balanceOf(address(this));
        twabRewards.endPromotion(promotionId, address(this));
        uint256 balanceAfter = mockToken.balanceOf(address(this));
        assertEq(balanceAfter - balanceBefore, _refundAmount);

        balanceBefore = mockToken.balanceOf(wallet1);
        twabRewards.claimRewards(vaultAddress, wallet1, promotionId, epochIds);
        balanceAfter = mockToken.balanceOf(wallet1);
        assertEq(balanceAfter - balanceBefore, wallet1RewardAmount);

        balanceBefore = mockToken.balanceOf(wallet2);
        twabRewards.claimRewards(vaultAddress, wallet2, promotionId, epochIds);
        balanceAfter = mockToken.balanceOf(wallet2);
        assertEq(balanceAfter - balanceBefore, wallet2RewardAmount);
    }

    function testEndPromotion_OnlyPromotionCreator() external {
        vm.startPrank(wallet1);
        vm.expectRevert(abi.encodeWithSelector(OnlyPromotionCreator.selector, wallet1, address(this)));
        twabRewards.endPromotion(promotionId, wallet1);
        vm.stopPrank();
    }

    function testEndPromotion_PromotionInactive() external {
        vm.warp(firstDrawOpensAt + epochDuration * numberOfEpochs);
        vm.expectRevert(abi.encodeWithSelector(PromotionInactive.selector, promotionId));
        twabRewards.endPromotion(promotionId, wallet1);
    }

    function testEndPromotion_PayeeZeroAddress() external {
        vm.expectRevert(abi.encodeWithSelector(PayeeZeroAddress.selector));
        twabRewards.endPromotion(promotionId, address(0));
    }

    /* ============ destroyPromotion ============ */

    function testDestroyPromotion_TransfersExpectedAmount() external {
        uint8 numEpochsPassed = 2;
        uint8[] memory epochIds = new uint8[](2);
        epochIds[0] = 0;
        epochIds[1] = 1;

        uint256 totalShares = 1000e18;
        vm.startPrank(vaultAddress);
        twabController.mint(wallet1, uint96((totalShares * 3) / 4));
        twabController.mint(wallet2, uint96((totalShares * 1) / 4));
        vm.stopPrank();

        vm.warp(numEpochsPassed * epochDuration + firstDrawOpensAt);

        mockPrizePoolContributions(vaultAddress, 1, 7, 1e18, 1e18);
        mockPrizePoolContributions(vaultAddress, 8, 14, 1e18, 1e18);

        twabRewards.claimRewards(vaultAddress, wallet1, promotionId, epochIds);
        twabRewards.claimRewards(vaultAddress, wallet2, promotionId, epochIds);

        vm.warp(epochDuration * numberOfEpochs + firstDrawOpensAt + 60 days);

        uint256 _refundAmount = numberOfEpochs *
            tokensPerEpoch -
            mockToken.balanceOf(wallet1) -
            mockToken.balanceOf(wallet2);
        uint256 balanceBefore = mockToken.balanceOf(address(this));
        twabRewards.destroyPromotion(promotionId, address(this));
        uint256 balanceAfter = mockToken.balanceOf(address(this));
        assertEq(balanceAfter - balanceBefore, _refundAmount);
    }

    function testDestroyPromotion_DoesNotExceedRewardBalance() external {
        // create another promotion
        uint96 _tokensPerEpoch = 1e18;
        uint256 amount = _tokensPerEpoch * numberOfEpochs;
        mockToken.mint(address(this), amount);
        mockToken.approve(address(twabRewards), amount);
        twabRewards.createPromotion(
            mockToken,
            firstDrawOpensAt,
            _tokensPerEpoch,
            epochDuration,
            numberOfEpochs
        );

        twabRewards.endPromotion(promotionId, address(this));

        vm.warp(firstDrawOpensAt + 86400 * 61); // 61 days

        vm.expectEmit();
        emit PromotionDestroyed(promotionId, address(this), 0);
        twabRewards.destroyPromotion(promotionId, address(this));

        assertEq(mockToken.balanceOf(address(this)), tokensPerEpoch * numberOfEpochs);
        assertEq(mockToken.balanceOf(address(twabRewards)), amount);
    }

    function testDestroyPromotion_PayeeZeroAddress() external {
        vm.expectRevert(abi.encodeWithSelector(PayeeZeroAddress.selector));
        twabRewards.destroyPromotion(promotionId, address(0));
    }

    function testDestroyPromotion_OnlyPromotionCreator() external {
        vm.expectRevert(abi.encodeWithSelector(OnlyPromotionCreator.selector, wallet1, address(this)));
        vm.startPrank(wallet1);
        twabRewards.destroyPromotion(promotionId, address(this));
        vm.stopPrank();
    }

    function testDestroyPromotion_GracePeriodActive() external {
        uint64 promotionEndTime = firstDrawOpensAt + epochDuration * numberOfEpochs;
        vm.expectRevert(abi.encodeWithSelector(GracePeriodActive.selector, promotionEndTime + 86400 * 60));
        twabRewards.destroyPromotion(promotionId, address(this));
    }

    function testDestroyPromotion_GracePeriodActive_OneEpochPassed() external {
        uint64 promotionEndTime = firstDrawOpensAt + epochDuration * numberOfEpochs;
        vm.warp(firstDrawOpensAt + epochDuration); // 1 epoch passed
        vm.expectRevert(abi.encodeWithSelector(GracePeriodActive.selector, promotionEndTime + 86400 * 60));
        twabRewards.destroyPromotion(promotionId, address(this));
    }

    /* ============ extendPromotion ============ */

    function testExtendPromotion() external {
        uint8 addedEpochs = 6;
        uint256 additionalRewards = addedEpochs * tokensPerEpoch;

        mockToken.mint(address(this), additionalRewards);
        mockToken.approve(address(twabRewards), additionalRewards);

        vm.expectEmit();
        emit PromotionExtended(promotionId, addedEpochs);
        twabRewards.extendPromotion(promotionId, addedEpochs);

        assertEq(twabRewards.getPromotion(promotionId).numberOfEpochs, numberOfEpochs + addedEpochs);
        assertEq(mockToken.balanceOf(address(this)), 0);
        assertEq(mockToken.balanceOf(address(twabRewards)), tokensPerEpoch * (numberOfEpochs + addedEpochs));
    }

    function testExtendPromotion_PromotionInactive() external {
        vm.warp(firstDrawOpensAt + numberOfEpochs * epochDuration); // end of promotion
        vm.expectRevert(abi.encodeWithSelector(PromotionInactive.selector, promotionId));
        twabRewards.extendPromotion(promotionId, 5);
    }

    function testExtendPromotion_ExceedsMaxEpochs() external {
        vm.expectRevert(abi.encodeWithSelector(ExceedsMaxEpochs.selector, 250, numberOfEpochs, 255));
        twabRewards.extendPromotion(promotionId, 250);
    }

    /* ============ getVaultRewardAmount ============ */

    function testGetVaultRewardAmount_zero_contributed() public {
        vm.warp(firstDrawOpensAt + epochDuration);
        mockPrizePoolContributions(vaultAddress, 1, 7, 0, 1e18);
        assertEq(twabRewards.getVaultRewardAmount(vaultAddress, promotionId, 0), 0);
    }

    function testGetVaultRewardAmount_success() public {
        vm.warp(firstDrawOpensAt + epochDuration);
        mockPrizePoolContributions(vaultAddress, 1, 7, 0.5e18, 1e18);
        assertEq(twabRewards.getVaultRewardAmount(vaultAddress, promotionId, 0), tokensPerEpoch / 2);
    }

    function testGetVaultRewardAmount_second() public {
        vm.warp(firstDrawOpensAt + epochDuration);
        mockPrizePoolContributions(vaultAddress, 1, 7, 0.5e18, 1e18);
        assertEq(twabRewards.getVaultRewardAmount(vaultAddress, promotionId, 0), tokensPerEpoch / 2);
        assertEq(twabRewards.getVaultRewardAmount(vaultAddress, promotionId, 0), tokensPerEpoch / 2);
    }

    /* ============ getPromotion ============ */

    function testGetPromotion() external {
        Promotion memory p = twabRewards.getPromotion(promotionId);
        // assertEq(p.creator, address(this));
        assertEq(p.startTimestamp, firstDrawOpensAt);
        assertEq(p.numberOfEpochs, numberOfEpochs);
        assertEq(p.epochDuration, epochDuration);
        assertEq(p.createdAt, firstDrawOpensAt);
        assertEq(address(p.token), address(mockToken));
        assertEq(p.tokensPerEpoch, tokensPerEpoch);
        assertEq(p.rewardsUnclaimed, tokensPerEpoch * numberOfEpochs);
    }

    /* ============ getRemainingRewards ============ */

    function testGetRemainingRewards() external {
        for (uint8 epoch; epoch < numberOfEpochs; epoch++) {
            vm.warp(firstDrawOpensAt + epoch * epochDuration);
            assertEq(twabRewards.getRemainingRewards(promotionId), tokensPerEpoch * (numberOfEpochs - epoch));
        }
    }

    function testGetRemainingRewards_EndOfPromotion() external {
        vm.warp(firstDrawOpensAt + epochDuration * numberOfEpochs);
        assertEq(twabRewards.getRemainingRewards(promotionId), 0);
    }

    /* ============ epochRangesForPromotion ============ */

    function testEpochRangesForPromotion() public {
        (
            uint48 epochStartTimestamp,
            uint48 epochEndTimestamp,
            uint24 epochStartDrawId,
            uint24 epochEndDrawId
        ) = twabRewards.epochRangesForPromotion(promotionId, 0);
        assertEq(epochStartTimestamp, firstDrawOpensAt, "start timestamp");
        assertEq(epochEndTimestamp, firstDrawOpensAt + epochDuration, "end timestamp");
        // epoch duration is one week, so that includes draws 1 - 7
        assertEq(epochStartDrawId, 1, "start draw id");
        assertEq(epochEndDrawId, 7, "end draw id");
    }

    /* ============ epochRanges ============ */

    function testEpochRanges() public {
        (
            uint48 epochStartTimestamp,
            uint48 epochEndTimestamp,
            uint24 epochStartDrawId,
            uint24 epochEndDrawId
        ) = twabRewards.epochRanges(firstDrawOpensAt, epochDuration, 0);
        assertEq(epochStartTimestamp, firstDrawOpensAt, "start timestamp");
        assertEq(epochEndTimestamp, firstDrawOpensAt + epochDuration, "end timestamp");
        assertEq(epochStartDrawId, 1, "start draw id");
        assertEq(epochEndDrawId, 7, "end draw id");
    }

    function testEpochRanges_oneDrawDuration() public {
        (
            uint48 epochStartTimestamp,
            uint48 epochEndTimestamp,
            uint24 epochStartDrawId,
            uint24 epochEndDrawId
        ) = twabRewards.epochRanges(firstDrawOpensAt, drawPeriodSeconds, 0);
        assertEq(epochStartTimestamp, firstDrawOpensAt, "start timestamp");
        assertEq(epochEndTimestamp, firstDrawOpensAt + drawPeriodSeconds, "end timestamp");
        assertEq(epochStartDrawId, 1, "start draw id");
        assertEq(epochEndDrawId, 1, "end draw id");
    }

    /* ============ getEpochIdNow ============ */

    function testGetEpochIdNow_zero() external {
        vm.warp(0);
        assertEq(twabRewards.getEpochIdNow(promotionId), 0);
    }

    function testGetEpochIdNow_mid() external {
        vm.warp(firstDrawOpensAt + epochDuration * 3);
        assertEq(twabRewards.getEpochIdNow(promotionId), 3);
    }

    function testGetEpochIdNow_pastNumEpochs() external {
        vm.warp(firstDrawOpensAt + epochDuration * 13);
        assertEq(twabRewards.getEpochIdNow(promotionId), 13);
    }

    function testGetEpochIdNow_pastEpochLimit() external {
        vm.warp(firstDrawOpensAt + epochDuration * 300);
        assertEq(twabRewards.getEpochIdNow(promotionId), type(uint8).max);
    }

    /* ============ getEpochIdAt ============ */

    function testGetEpochIdAt_before() public {
        assertEq(twabRewards.getEpochIdAt(promotionId, firstDrawOpensAt - 1), 0, "epoch 0");
    }

    /* ============ claimRewards ============ */

    function testGetRewardsAmount_success() external {
        uint8 numEpochsPassed = 6;
        uint8[] memory epochIds = new uint8[](6);
        epochIds[0] = 0;
        epochIds[1] = 1;
        epochIds[2] = 2;
        epochIds[3] = 3;
        epochIds[4] = 4;
        epochIds[5] = 5;

        uint256 totalShares = 1000e18;
        vm.warp(firstDrawOpensAt);
        vm.startPrank(vaultAddress);
        twabController.mint(wallet1, uint96((totalShares * 3) / 4));
        twabController.mint(wallet2, uint96((totalShares * 1) / 4));
        vm.stopPrank();

        uint256 wallet1RewardAmountPerEpoch = (tokensPerEpoch * 3) / 4;
        uint256 wallet2RewardAmountPerEpoch = (tokensPerEpoch * 1) / 4;

        vm.warp(firstDrawOpensAt + epochDuration * numEpochsPassed);

        uint256 wallet1Rewards = twabRewards.claimRewards(vaultAddress, wallet1, promotionId, epochIds);
        uint256 wallet2Rewards = twabRewards.claimRewards(vaultAddress, wallet2, promotionId, epochIds);

        assertEq(wallet1Rewards, wallet1RewardAmountPerEpoch * numEpochsPassed);
        assertEq(wallet2Rewards, wallet2RewardAmountPerEpoch * numEpochsPassed);
    }

    function testGetRewardsAmount_DelegateAmountChanged() external {
        uint256 totalShares = 1000e18;
        vm.warp(firstDrawOpensAt);
        vm.startPrank(vaultAddress);
        twabController.mint(wallet1, uint96((totalShares * 3) / 4));
        twabController.mint(wallet2, uint96((totalShares * 1) / 4));
        vm.stopPrank();

        // Delegate wallet2 balance halfway through epoch 2
        vm.warp(firstDrawOpensAt + epochDuration * 2 + epochDuration / 2);
        vm.startPrank(wallet2);
        twabController.delegate(vaultAddress, wallet1);
        vm.stopPrank();

        uint8 numEpochsPassed = 6;
        vm.warp(firstDrawOpensAt + epochDuration * numEpochsPassed);

        uint8[] memory epochIds = new uint8[](1);

        epochIds[0] = 0;
        assertEq(twabRewards.claimRewards(vaultAddress, wallet1, promotionId, epochIds), (tokensPerEpoch * 3) / 4);
        assertEq(twabRewards.claimRewards(vaultAddress, wallet2, promotionId, epochIds), (tokensPerEpoch * 1) / 4);

        epochIds[0] = 1;
        assertEq(twabRewards.claimRewards(vaultAddress, wallet1, promotionId, epochIds), (tokensPerEpoch * 3) / 4);
        assertEq(twabRewards.claimRewards(vaultAddress, wallet2, promotionId, epochIds), (tokensPerEpoch * 1) / 4);

        epochIds[0] = 2;
        assertEq(twabRewards.claimRewards(vaultAddress, wallet1, promotionId, epochIds), (tokensPerEpoch * 7) / 8);
        assertEq(twabRewards.claimRewards(vaultAddress, wallet2, promotionId, epochIds), (tokensPerEpoch * 1) / 8);

        epochIds[0] = 3;
        assertEq(twabRewards.claimRewards(vaultAddress, wallet1, promotionId, epochIds), tokensPerEpoch);
        assertEq(twabRewards.claimRewards(vaultAddress, wallet2, promotionId, epochIds), 0);



        // for (uint8 epoch = 0; epoch < numEpochsPassed; epoch++) {
        //     if (epoch < 2) {
        //         assertEq(wallet1Rewards[epoch], (tokensPerEpoch * 3) / 4);
        //         assertEq(wallet2Rewards[epoch], (tokensPerEpoch * 1) / 4);
        //     } else if (epoch == 2) {
        //         assertEq(wallet1Rewards[epoch], (tokensPerEpoch * 7) / 8);
        //         assertEq(wallet2Rewards[epoch], (tokensPerEpoch * 1) / 8);
        //     } else {
        //         assertEq(wallet1Rewards[epoch], tokensPerEpoch);
        //         assertEq(wallet2Rewards[epoch], 0);
        //     }
        // }
    }

    function testGetRewardsAmount_NoDelegateBalance() external {
        uint8 numEpochsPassed = 6;
        uint8[] memory epochIds = new uint8[](6);
        epochIds[0] = 0;
        epochIds[1] = 1;
        epochIds[2] = 2;
        epochIds[3] = 3;
        epochIds[4] = 4;
        epochIds[5] = 5;

        uint256 totalShares = 1000e18;
        vm.warp(firstDrawOpensAt);
        vm.startPrank(vaultAddress);
        twabController.mint(wallet1, uint96((totalShares * 3) / 4));
        twabController.mint(wallet2, uint96((totalShares * 1) / 4));
        vm.stopPrank();

        uint256 wallet1RewardAmountPerEpoch = (tokensPerEpoch * 3) / 4;
        uint256 wallet2RewardAmountPerEpoch = (tokensPerEpoch * 1) / 4;
        uint256 wallet3RewardAmountPerEpoch = 0;

        vm.warp(firstDrawOpensAt + epochDuration * numEpochsPassed);

        uint256 wallet1Rewards = twabRewards.claimRewards(vaultAddress, wallet1, promotionId, epochIds);
        uint256 wallet2Rewards = twabRewards.claimRewards(vaultAddress, wallet2, promotionId, epochIds);
        uint256 wallet3Rewards = twabRewards.claimRewards(vaultAddress, wallet3, promotionId, epochIds);

        assertEq(wallet1Rewards, wallet1RewardAmountPerEpoch * numEpochsPassed);
        assertEq(wallet2Rewards, wallet2RewardAmountPerEpoch * numEpochsPassed);
        assertEq(wallet3Rewards, wallet3RewardAmountPerEpoch * numEpochsPassed);
    }

    function testGetRewardsAmount_NoSupply() external {
        uint8 numEpochsPassed = 3;
        uint8[] memory epochIds = new uint8[](3);
        epochIds[0] = 0;
        epochIds[1] = 1;
        epochIds[2] = 2;

        vm.warp(firstDrawOpensAt + epochDuration * numEpochsPassed);

        uint256 wallet1Rewards = twabRewards.claimRewards(wallet1, vaultAddress, promotionId, epochIds);

        assertEq(wallet1Rewards, 0);
    }

    function testGetRewardsAmount_EpochNotOver() external {
        uint8 numEpochsPassed = 3;
        uint8[] memory epochIds = new uint8[](3);
        epochIds[0] = 0;
        epochIds[1] = 1;
        epochIds[2] = 2;

        vm.warp(firstDrawOpensAt + epochDuration * (numEpochsPassed - 1) + 1);

        vm.expectRevert(
            abi.encodeWithSelector(EpochNotOver.selector, firstDrawOpensAt + epochDuration * numEpochsPassed)
        );
        twabRewards.claimRewards(wallet1, vaultAddress, promotionId, epochIds);
    }

    function testGetRewardsAmount_InvalidEpochId() external {
        uint8[] memory epochIds = new uint8[](3);
        epochIds[0] = 0;
        epochIds[1] = 1;
        epochIds[2] = numberOfEpochs;

        vm.warp(firstDrawOpensAt + epochDuration * (numberOfEpochs + 1));

        vm.expectRevert(abi.encodeWithSelector(InvalidEpochId.selector, numberOfEpochs, numberOfEpochs));
        twabRewards.claimRewards(wallet1, vaultAddress, promotionId, epochIds);
    }

    /* ============ claimRewards ============ */

    function testClaimRewards_success() external {
        uint8[] memory epochIds = new uint8[](3);
        epochIds[0] = 1;
        epochIds[1] = 2;
        epochIds[2] = 3;

        uint256 totalShares = 1000e18;
        vm.warp(firstDrawOpensAt);
        vm.startPrank(vaultAddress);
        twabController.mint(wallet1, uint96((totalShares * 3) / 4));
        twabController.mint(wallet2, uint96((totalShares * 1) / 4));
        vm.stopPrank();

        mockPrizePoolContributions(vaultAddress, 8, 14, 1e18, 1e18);
        mockPrizePoolContributions(vaultAddress, 15, 21, 1e18, 1e18);
        mockPrizePoolContributions(vaultAddress, 22, 28, 1e18, 1e18);

        uint8 numEpochsPassed = 3;
        uint256 warpTime = firstDrawOpensAt + epochDuration * 4;
        vm.warp(warpTime);
        vm.expectEmit();
        emit RewardsClaimed(promotionId, twabRewards.epochIdArrayToBytes(epochIds), vaultAddress, wallet1, (numEpochsPassed * (tokensPerEpoch * 3)) / 4);
        twabRewards.claimRewards(vaultAddress, wallet1, promotionId, epochIds);

        assertEq(mockToken.balanceOf(wallet1), (numEpochsPassed * (tokensPerEpoch * 3)) / 4);
    }

    function testClaimRewards_noUsers() public {
        uint8[] memory epochIds = new uint8[](3);
        epochIds[0] = 1;
        epochIds[1] = 2;
        epochIds[2] = 3;
        uint256 warpTime = firstDrawOpensAt + epochDuration * 4;
        vm.warp(warpTime);
        assertEq(twabRewards.claimRewards(vaultAddress, wallet1, promotionId, epochIds), 0);
    }

    function testClaimRewards_noContributions() public {
        uint8[] memory epochIds = new uint8[](3);
        epochIds[0] = 0;
        epochIds[1] = 1;
        epochIds[2] = 2;
        mockPrizePoolContributions(vaultAddress, 1, 7, 0, 0);
        mockPrizePoolContributions(vaultAddress, 8, 14, 0, 0);
        mockPrizePoolContributions(vaultAddress, 15, 21, 0, 0);
        uint256 totalShares = 1000e18;
        vm.warp(firstDrawOpensAt);
        vm.startPrank(vaultAddress);
        twabController.mint(wallet1, uint96((totalShares * 3) / 4));
        twabController.mint(wallet2, uint96((totalShares * 1) / 4));
        vm.stopPrank();
        uint256 warpTime = firstDrawOpensAt + epochDuration * 4;
        vm.warp(warpTime);
        assertEq(twabRewards.claimRewards(vaultAddress, wallet1, promotionId, epochIds), 0);
    }

    function testClaimRewards_Multicall() external {
        uint8 numEpochsPassed = 6;
        uint8[] memory epochIds = new uint8[](6);
        epochIds[0] = 0;
        epochIds[1] = 1;
        epochIds[2] = 2;
        epochIds[3] = 3;
        epochIds[4] = 4;
        epochIds[5] = 5;

        uint256 totalShares = 1000e18;
        vm.warp(firstDrawOpensAt);
        vm.startPrank(vaultAddress);
        twabController.mint(wallet1, uint96(totalShares / 2));
        twabController.mint(wallet2, uint96(totalShares / 2));
        vm.stopPrank();

        // Create second promotion with a different vault
        uint256 amount = tokensPerEpoch * numberOfEpochs;
        mockToken.mint(address(this), amount);
        mockToken.approve(address(twabRewards), amount);

        bytes[] memory data = new bytes[](2);
        data[0] = abi.encodeWithSelector(twabRewards.claimRewards.selector, vaultAddress, wallet1, promotionId, epochIds);
        data[1] = abi.encodeWithSelector(twabRewards.claimRewards.selector, vaultAddress, wallet2, promotionId, epochIds);

        vm.warp(firstDrawOpensAt + epochDuration * numEpochsPassed);
        vm.expectEmit();
        uint totalPromotionRewards = numEpochsPassed * tokensPerEpoch;
        uint vaultPromotionRewards = totalPromotionRewards;
        uint promotion1Rewards = vaultPromotionRewards / 2;
        emit RewardsClaimed(promotionId, twabRewards.epochIdArrayToBytes(epochIds), vaultAddress, wallet1, promotion1Rewards);
        vm.expectEmit();
        emit RewardsClaimed(promotionId, twabRewards.epochIdArrayToBytes(epochIds), vaultAddress, wallet2, promotion1Rewards);
        twabRewards.multicall(data);

        assertEq(mockToken.balanceOf(wallet1), promotion1Rewards);
        assertEq(mockToken.balanceOf(wallet2), promotion1Rewards);
    }

    /// test different scenarios for gas usage
    function testClaimRewards_gasProfile_cold() public {
        uint8[] memory epochIds = setupGasProfiling();

        // First claim; cold storage
        assertEq(twabRewards.claimRewards(vaultAddress, wallet1, promotionId, epochIds), tokensPerEpoch / 2);
    }

    /// test different scenarios for gas usage
    function testClaimRewards_gasProfile_multipleEpochs_cold() public {
        setupGasProfiling();
        uint8[] memory epochIds = new uint8[](3);
        epochIds[0] = 0;
        epochIds[1] = 1;
        epochIds[2] = 2;

        assertEq(twabRewards.claimRewards(vaultAddress, wallet1, promotionId, epochIds), (tokensPerEpoch / 2) * 3);
    }

    /// test different scenarios for gas usage
    function testClaimRewards_gasProfile_multipleEpochs_hot() public {
        setupGasProfiling();
        uint8[] memory epochIds = new uint8[](1);
        epochIds[0] = 0;
        // epochIds[1] = 1;
        // epochIds[2] = 2;

        assertEq(twabRewards.claimRewards(vaultAddress, wallet1, promotionId, epochIds), (tokensPerEpoch / 2) * epochIds.length);
        assertEq(twabRewards.claimRewards(vaultAddress, wallet2, promotionId, epochIds), (tokensPerEpoch / 2) * epochIds.length);
    }

    function testClaimRewards_gasProfile_secondClaim() public {
        uint8[] memory epochIds = setupGasProfiling();

        // First claim; cold storage
        assertEq(twabRewards.claimRewards(vaultAddress, wallet1, promotionId, epochIds), tokensPerEpoch / 2);

        // Second claim
        epochIds[0] = 1;
        assertEq(twabRewards.claimRewards(vaultAddress, wallet1, promotionId, epochIds), tokensPerEpoch / 2);
    }

    function testClaimRewards_gasProfile_claimSecondUser() public {
        uint8[] memory epochIds = setupGasProfiling();

        // First claim; cold storage
        assertEq(twabRewards.claimRewards(vaultAddress, wallet1, promotionId, epochIds), tokensPerEpoch / 2);

        // Second claim
        epochIds[0] = 1;
        assertEq(twabRewards.claimRewards(vaultAddress, wallet1, promotionId, epochIds), tokensPerEpoch / 2);

        // Second claim
        epochIds[0] = 2;
        assertEq(twabRewards.claimRewards(vaultAddress, wallet1, promotionId, epochIds), tokensPerEpoch / 2);

        // claim on older epoch with new user
        epochIds[0] = 0;
        assertEq(twabRewards.claimRewards(vaultAddress, wallet2, promotionId, epochIds), tokensPerEpoch / 2);
    }

    function testClaimRewards_gasProfile_secondClaimSecondUser() public {
        uint8[] memory epochIds = setupGasProfiling();

        // First claim; cold storage
        assertEq(twabRewards.claimRewards(vaultAddress, wallet1, promotionId, epochIds), tokensPerEpoch / 2);

        // Second claim
        epochIds[0] = 1;
        assertEq(twabRewards.claimRewards(vaultAddress, wallet1, promotionId, epochIds), tokensPerEpoch / 2);

        // Second claim
        epochIds[0] = 2;
        assertEq(twabRewards.claimRewards(vaultAddress, wallet1, promotionId, epochIds), tokensPerEpoch / 2);

        // claim on older epoch with new user
        epochIds[0] = 0;
        assertEq(twabRewards.claimRewards(vaultAddress, wallet2, promotionId, epochIds), tokensPerEpoch / 2);

        // second old epoch claim
        epochIds[0] = 1;
        assertEq(twabRewards.claimRewards(vaultAddress, wallet2, promotionId, epochIds), tokensPerEpoch / 2);
    }

    function testClaimRewards_DecreasedDelegateBalance() external {
        uint8[] memory epochIds = new uint8[](1);
        epochIds[0] = 0;

        uint256 totalShares = 1000e18;
        vm.warp(firstDrawOpensAt);
        vm.startPrank(vaultAddress);
        twabController.mint(wallet1, uint96((totalShares * 3) / 4));
        twabController.mint(wallet2, uint96((totalShares * 1) / 4));
        vm.stopPrank();

        // Decrease wallet1 delegate balance halfway through epoch
        vm.warp(firstDrawOpensAt + epochDuration / 2);
        vm.startPrank(wallet1);
        twabController.delegate(vaultAddress, wallet2);
        vm.stopPrank();

        mockPrizePoolContributions(vaultAddress, 1, 7, 1e18, 1e18);

        vm.warp(firstDrawOpensAt + epochDuration);
        vm.expectEmit();
        emit RewardsClaimed(promotionId, twabRewards.epochIdArrayToBytes(epochIds), vaultAddress, wallet1, (tokensPerEpoch * 3) / 8);
        twabRewards.claimRewards(vaultAddress, wallet1, promotionId, epochIds);

        assertEq(mockToken.balanceOf(wallet1), (tokensPerEpoch * 3) / 8);
    }

    function testClaimRewards_NoDelegateBalance() external {
        uint8 numEpochsPassed = 3;
        uint8[] memory epochIds = new uint8[](3);
        epochIds[0] = 0;
        epochIds[1] = 1;
        epochIds[2] = 2;

        mockPrizePoolContributions(vaultAddress, 1, 7, 1e18, 1e18);
        mockPrizePoolContributions(vaultAddress, 8, 14, 1e18, 1e18);
        mockPrizePoolContributions(vaultAddress, 15, 21, 1e18, 1e18);

        uint256 totalShares = 1000e18;
        vm.warp(firstDrawOpensAt);
        vm.startPrank(vaultAddress);
        twabController.mint(wallet1, uint96((totalShares * 3) / 4));
        twabController.mint(wallet2, uint96((totalShares * 1) / 4));
        vm.stopPrank();

        vm.warp(firstDrawOpensAt + epochDuration * numEpochsPassed);
        vm.expectEmit();
        emit RewardsClaimed(promotionId, twabRewards.epochIdArrayToBytes(epochIds), vaultAddress, wallet3, 0);
        twabRewards.claimRewards(vaultAddress, wallet3, promotionId, epochIds);

        assertEq(mockToken.balanceOf(wallet3), 0);
    }

    function testClaimRewards_NoSupply() external {
        uint8 numEpochsPassed = 3;
        uint8[] memory epochIds = new uint8[](3);
        epochIds[0] = 0;
        epochIds[1] = 1;
        epochIds[2] = 2;

        vm.warp(firstDrawOpensAt + epochDuration * numEpochsPassed);
        vm.expectEmit();
        emit RewardsClaimed(promotionId, twabRewards.epochIdArrayToBytes(epochIds), vaultAddress, wallet1, 0);
        twabRewards.claimRewards(vaultAddress, wallet1, promotionId, epochIds);

        assertEq(mockToken.balanceOf(wallet1), 0);
    }

    function testClaimRewards_EpochNotOver() external {
        uint8 numEpochsPassed = 3;
        uint8[] memory epochIds = new uint8[](3);
        epochIds[0] = 0;
        epochIds[1] = 1;
        epochIds[2] = 3; // 4th epoch

        vm.warp(firstDrawOpensAt + epochDuration * numEpochsPassed);
        vm.expectRevert(abi.encodeWithSelector(EpochNotOver.selector, firstDrawOpensAt + epochDuration * 4));
        twabRewards.claimRewards(vaultAddress, wallet1, promotionId, epochIds);
    }

    function testClaimRewards_RewardsAlreadyClaimed() external {
        uint8 numEpochsPassed = 3;
        uint8[] memory epochIds = new uint8[](3);
        epochIds[0] = 0;
        epochIds[1] = 1;
        epochIds[2] = 2;

        uint256 totalShares = 1000e18;
        vm.warp(firstDrawOpensAt);
        vm.startPrank(vaultAddress);
        twabController.mint(wallet1, uint96((totalShares * 3) / 4));
        twabController.mint(wallet2, uint96((totalShares * 1) / 4));
        vm.stopPrank();

        mockPrizePoolContributions(vaultAddress, 1, 7, 1e18, 1e18);
        mockPrizePoolContributions(vaultAddress, 8, 14, 1e18, 1e18);
        mockPrizePoolContributions(vaultAddress, 15, 21, 1e18, 1e18);

        vm.warp(firstDrawOpensAt + epochDuration * numEpochsPassed);
        twabRewards.claimRewards(vaultAddress, wallet1, promotionId, epochIds);

        // Try to claim again:
        uint8[] memory reclaimEpochId = new uint8[](1);
        reclaimEpochId[0] = 0;
        vm.expectRevert(abi.encodeWithSelector(RewardsAlreadyClaimed.selector, promotionId, wallet1, 0));
        twabRewards.claimRewards(vaultAddress, wallet1, promotionId, reclaimEpochId);

        reclaimEpochId[0] = 1;
        vm.expectRevert(abi.encodeWithSelector(RewardsAlreadyClaimed.selector, promotionId, wallet1, 1));
        twabRewards.claimRewards(vaultAddress, wallet1, promotionId, reclaimEpochId);

        reclaimEpochId[0] = 2;
        vm.expectRevert(abi.encodeWithSelector(RewardsAlreadyClaimed.selector, promotionId, wallet1, 2));
        twabRewards.claimRewards(vaultAddress, wallet1, promotionId, reclaimEpochId);
    }

    function testClaimRewards_InvalidEpochId() external {
        uint8[] memory epochIds = new uint8[](3);
        epochIds[0] = 0;
        epochIds[1] = 1;
        epochIds[2] = numberOfEpochs;

        vm.warp(firstDrawOpensAt + epochDuration * (numberOfEpochs + 1));
        vm.expectRevert(abi.encodeWithSelector(InvalidEpochId.selector, numberOfEpochs, numberOfEpochs));
        twabRewards.claimRewards(vaultAddress, wallet1, promotionId, epochIds);
    }

    /* ============ claimRewardedEpochs ============ */

    function testClaimRewardedEpochs_success() public {
        uint256 totalShares = 1000e18;
        vm.warp(firstDrawOpensAt);
        vm.startPrank(vaultAddress);
        twabController.mint(wallet1, uint96(totalShares / 2));
        twabController.mint(wallet2, uint96(totalShares / 2));
        vm.stopPrank();

        mockPrizePoolContributions(vaultAddress, 1, 7, 1e18, 1e18);
        mockPrizePoolContributions(vaultAddress, 8, 14, 1e18, 1e18);
        mockPrizePoolContributions(vaultAddress, 15, 21, 1e18, 1e18);

        vm.warp(firstDrawOpensAt + epochDuration * 3);
        vm.expectEmit();
        uint rewards = (tokensPerEpoch * 3) / 2;
        emit RewardsClaimed(promotionId, bytes32(uint(7)), vaultAddress, wallet1, rewards);
        assertEq(twabRewards.claimRewardedEpochs(vaultAddress, wallet1, promotionId, 0), rewards);
    }

    function testClaimRewardedEpochs_success_excludeAlreadyClaimed() public {
        uint256 totalShares = 1000e18;
        vm.warp(firstDrawOpensAt);
        vm.startPrank(vaultAddress);
        twabController.mint(wallet1, uint96(totalShares / 2));
        twabController.mint(wallet2, uint96(totalShares / 2));
        vm.stopPrank();

        mockPrizePoolContributions(vaultAddress, 1, 7, 1e18, 1e18);
        mockPrizePoolContributions(vaultAddress, 8, 14, 1e18, 1e18);
        mockPrizePoolContributions(vaultAddress, 15, 21, 1e18, 1e18);

        uint rewardsPerEpoch = tokensPerEpoch / 2;

        // claim the first epoch
        vm.warp(firstDrawOpensAt + epochDuration * 1);
        vm.expectEmit();
        emit RewardsClaimed(promotionId, bytes32(uint(1)), vaultAddress, wallet1, rewardsPerEpoch);
        assertEq(twabRewards.claimRewardedEpochs(vaultAddress, wallet1, promotionId, 0), rewardsPerEpoch);

        // claim the remaining
        vm.warp(firstDrawOpensAt + epochDuration * 3);
        vm.expectEmit();
        emit RewardsClaimed(promotionId, bytes32(uint(6)), vaultAddress, wallet1, rewardsPerEpoch * 2);
        assertEq(twabRewards.claimRewardedEpochs(vaultAddress, wallet1, promotionId, 0), rewardsPerEpoch * 2);
    }

    function testClaimRewardedEpochs_maxTwabAndContributionValues() public {
        // max out the twab controller
        uint256 totalShares = type(uint96).max;
        vm.warp(firstDrawOpensAt);
        vm.startPrank(vaultAddress);
        twabController.mint(wallet1, uint96(totalShares / 2));
        twabController.mint(wallet2, uint96(totalShares / 2));
        vm.stopPrank();

        // max out contributions
        mockPrizePoolContributions(vaultAddress, 1, 7, type(uint128).max, type(uint128).max);

        uint rewardsPerEpoch = tokensPerEpoch / 2;

        // claim the first epoch
        vm.warp(firstDrawOpensAt + epochDuration * 1);
        vm.expectEmit();
        emit RewardsClaimed(promotionId, bytes32(uint(1)), vaultAddress, wallet1, rewardsPerEpoch);
        assertEq(twabRewards.claimRewardedEpochs(vaultAddress, wallet1, promotionId, 0), rewardsPerEpoch);
    }

    function testClaimRewardedEpochs_minTwabAndContributionValues() public {
        // max out the twab controller
        uint256 totalShares = 10;
        vm.warp(firstDrawOpensAt);
        vm.startPrank(vaultAddress);
        twabController.mint(wallet1, uint96(totalShares / 2));
        twabController.mint(wallet2, uint96(totalShares / 2));
        vm.stopPrank();

        // tiny contribution, and only half
        mockPrizePoolContributions(vaultAddress, 1, 7, 2, 4);

        uint rewardsPerEpoch = tokensPerEpoch / 2;

        // claim the first epoch
        vm.warp(firstDrawOpensAt + epochDuration * 1);
        vm.expectEmit();
        emit RewardsClaimed(promotionId, bytes32(uint(1)), vaultAddress, wallet1, rewardsPerEpoch / 2);
        assertEq(twabRewards.claimRewardedEpochs(vaultAddress, wallet1, promotionId, 0), rewardsPerEpoch / 2);
    }

    function testClaimRewardedEpochs_maxTwabAndContributionValues_maxTokensPerEpoch() public {
        // max out tokens per epoch
        tokensPerEpoch = type(uint96).max;
        uint promotionId2 = createPromotion();

        // max out the twab controller
        uint256 totalShares = type(uint96).max;
        vm.warp(firstDrawOpensAt);
        vm.startPrank(vaultAddress);
        twabController.mint(wallet1, uint96(totalShares / 2));
        twabController.mint(wallet2, uint96(totalShares / 2));
        vm.stopPrank();

        // max contributions
        mockPrizePoolContributions(vaultAddress, 1, 7, type(uint128).max, type(uint128).max);

        uint rewardsPerEpoch = tokensPerEpoch / 2;

        // claim the first epoch
        vm.warp(firstDrawOpensAt + epochDuration * 1);
        vm.expectEmit();
        emit RewardsClaimed(promotionId2, bytes32(uint(1)), vaultAddress, wallet1, rewardsPerEpoch);
        assertEq(twabRewards.claimRewardedEpochs(vaultAddress, wallet1, promotionId2, 0), rewardsPerEpoch);
    }

    function testClaimRewardedEpochs_NoEpochsToClaim_atStart() public {
        vm.expectRevert(abi.encodeWithSelector(NoEpochsToClaim.selector, 0, 0));
        twabRewards.claimRewardedEpochs(vaultAddress, wallet1, promotionId, 0);
    }

    function testClaimRewardedEpochs_NoEpochsToClaim_midway() public {
        vm.warp(firstDrawOpensAt + epochDuration * 2);
        vm.expectRevert(abi.encodeWithSelector(NoEpochsToClaim.selector, 2, 2));
        twabRewards.claimRewardedEpochs(vaultAddress, wallet1, promotionId, 2);
    }

    /* ============ claimRewardedEpochs ============ */

    function testCalculateRewards_success() public {
        uint256 totalShares = 1000e18;
        vm.warp(firstDrawOpensAt);
        vm.startPrank(vaultAddress);
        twabController.mint(wallet1, uint96(totalShares / 2));
        vm.stopPrank();

        mockPrizePoolContributions(vaultAddress, 1, 7, 1e18, 1e18);
        mockPrizePoolContributions(vaultAddress, 8, 14, 0.5e18, 1e18);
        mockPrizePoolContributions(vaultAddress, 15, 21, 0.25e18, 1e18);

        vm.warp(firstDrawOpensAt + epochDuration * 3);

        uint8[] memory epochIds = new uint8[](3);
        epochIds[0] = 0;
        epochIds[1] = 1;
        epochIds[2] = 2;

        uint256[] memory rewards = twabRewards.calculateRewards(vaultAddress, wallet1, promotionId, epochIds);
        assertEq(rewards[0], tokensPerEpoch);
        assertEq(rewards[1], tokensPerEpoch / 2);
        assertEq(rewards[2], tokensPerEpoch / 4);
    }

    /* ============ claimTwabRewards ============ */

    function testClaimTwabRewards() public {
        ITwabRewards regularTwabRewards = ITwabRewards(makeAddr("TwabRewards"));
        vm.etch(address(regularTwabRewards), "twabRewards");

        uint8[] memory epochIds = new uint8[](1);
        epochIds[0] = 12;
        vm.mockCall(address(regularTwabRewards), abi.encodeWithSelector(regularTwabRewards.claimRewards.selector, wallet1, 3, epochIds), abi.encode(111));
        assertEq(twabRewards.claimTwabRewards(regularTwabRewards, wallet1, 3, epochIds), 111);
    }

    /* ============ Utilities ============ */

    function testEpochIdArrayToBytes() public {
        uint8[] memory epochIds = new uint8[](3);
        epochIds[0] = 2;
        epochIds[1] = 4;
        epochIds[2] = 0;
        // 10101 = 1 + 4 + 16 = 21
        assertEq(twabRewards.epochIdArrayToBytes(epochIds), bytes32(uint(21)));
    }

    function testEpochBytesToIdArray() public {
        // 10101 = 1 + 4 + 16 = 21
        uint8[] memory epochIds = twabRewards.epochBytesToIdArray(bytes32(uint(21)));
        assertEq(epochIds.length, 3);
        assertEq(epochIds[0], 0);
        assertEq(epochIds[1], 2);
        assertEq(epochIds[2], 4);
    }

    /* ============ Test Helpers ============ */

    function createPromotion() public returns (uint256) {
        uint256 amount = uint256(tokensPerEpoch) * numberOfEpochs;
        mockToken.mint(address(this), amount);
        mockToken.approve(address(twabRewards), amount);
        mockDelegateCheck(false);
        return
            twabRewards.createPromotion(
                mockToken,
                firstDrawOpensAt,
                tokensPerEpoch,
                epochDuration,
                numberOfEpochs
            );
    }

    function mockDelegateCheck(bool alreadyDelegated) public {
        vm.mockCall(address(twabController), abi.encodeWithSelector(twabController.delegateOf.selector, address(mockToken), address(twabRewards)), abi.encode(address(alreadyDelegated ? address(1) : address(0))));
        vm.mockCall(address(twabController), abi.encodeWithSelector(twabController.delegate.selector, address(mockToken), address(1)), abi.encode());
    }

    function mockPrizePoolContributions(address _vault, uint24 _startDrawId, uint24 _endDrawId, uint192 _vaultAmount, uint192 _totalAmount) public {
        vm.mockCall(address(prizePool), abi.encodeWithSelector(prizePool.getTotalContributedBetween.selector, _startDrawId, _endDrawId), abi.encode(_totalAmount));
        vm.mockCall(address(prizePool), abi.encodeWithSelector(prizePool.getContributedBetween.selector, _vault, _startDrawId, _endDrawId), abi.encode(_vaultAmount));
    }

    function setupGasProfiling() public returns (uint8[] memory) {
        uint8[] memory epochIds = new uint8[](1);
        epochIds[0] = 0;

        vm.warp(firstDrawOpensAt);
        vm.startPrank(vaultAddress);
        twabController.mint(wallet1, 1e18);
        twabController.mint(wallet2, 1e18);
        vm.stopPrank();

        // warp far enough ahead
        vm.warp(firstDrawOpensAt + epochDuration*6);

        return epochIds;
    }
}
