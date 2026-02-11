// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.27;

import {Test, console} from "forge-std/Test.sol";
import {DeploySonicStaking} from "script/DeploySonicStaking.sol";
import {SonicStaking} from "src/SonicStaking.sol";
import {ERC20} from "openzeppelin-contracts/token/ERC20/ERC20.sol";
import {SFCMock} from "src/mock/SFCMock.sol";
import {SonicStakingTest} from "./SonicStakingTest.t.sol";
import {ISFC} from "src/interfaces/ISFC.sol";

contract SonicStakingMockTest is Test, SonicStakingTest {
    SFCMock sfcMock;

    // we inherit from SonicStakingTest and override the setSFCAddress function to setup the SonicStaking contract with the mock SFC.
    // we do that so we can run all tests defined there with the mock SFC also to make sure the mock doesnt do something funky.
    function setSFCAddress() public virtual override {
        // deploy the contract
        sfcMock = new SFCMock();
        SFC = ISFC(address(sfcMock));
    }

    function testRewardAccumulationInMock() public {
        // reward accumulation cant be tested in a fork test, as an epoch needs to be sealed by the node driver to accumulate rewards
        // hence we are using a mock SFC contract where we can set pending rewards.
        // make sure we have a delegation that accumulates rewards
        uint256 assetAmount = 100_000 ether;
        uint256 delegateAmount = 1_000 ether;
        uint256 toValidatorId = 1;
        makeDeposit(assetAmount);
        delegate(toValidatorId, delegateAmount);

        SFCMock(sfcMock).setPendingRewards{value: 100 ether}(address(sonicStaking), 1, 100 ether);
        assertEq(sfcMock.pendingRewards(address(sonicStaking), 1), 100 ether);
    }

    /*
    * Testing the withValidWithdrawId modifier
    */

    function testInvalidWithdrawId() public {
        vm.expectRevert(abi.encodeWithSelector(SonicStaking.WithdrawIdDoesNotExist.selector, 0));
        sonicStaking.withdraw(0, false);
    }

    function testWithdrawTooEarly() public {
        uint256 assetAmount = 10_000 ether;
        uint256 delegateAmount = 10_000 ether;
        uint256 undelegateAmount = 10_000 ether;
        uint256 validatorId = 1;

        address user = makeDeposit(assetAmount);
        delegate(validatorId, delegateAmount);

        vm.prank(user);
        sonicStaking.undelegate(validatorId, undelegateAmount);

        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(SonicStaking.WithdrawDelayNotElapsed.selector, 101));
        sonicStaking.withdraw(101, false);
    }

    function testWithdrawAlreadyProcessed() public {
        uint256 assetAmount = 10_000 ether;
        uint256 delegateAmount = 10_000 ether;
        uint256 undelegateAmount = 10_000 ether;
        uint256 validatorId = 1;

        address user = makeDeposit(assetAmount);
        delegate(validatorId, delegateAmount);

        vm.prank(user);
        sonicStaking.undelegate(validatorId, undelegateAmount);

        vm.warp(block.timestamp + 14 days);

        vm.prank(user);
        sonicStaking.withdraw(101, false);

        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(SonicStaking.WithdrawAlreadyProcessed.selector, 101));
        sonicStaking.withdraw(101, false);
    }

    function testUnauthorizedWithdraw() public {
        uint256 assetAmount = 10_000 ether;
        uint256 delegateAmount = 10_000 ether;
        uint256 undelegateAmount = 10_000 ether;
        uint256 validatorId = 1;

        address user = makeDeposit(assetAmount);
        delegate(validatorId, delegateAmount);

        vm.prank(user);
        sonicStaking.undelegate(validatorId, undelegateAmount);

        vm.warp(block.timestamp + 14 days);

        vm.expectRevert(abi.encodeWithSelector(SonicStaking.UnauthorizedWithdraw.selector, 101));
        sonicStaking.withdraw(101, false);
    }

    function testGetRateIncrease() public {
        uint256 assetAmount = 1_000 ether;
        uint256 delegateAmount = 1_000 ether;
        uint256 toValidatorId = 1;
        uint256 pendingRewards = 1 ether;
        address user = makeDeposit(assetAmount);
        delegate(toValidatorId, delegateAmount);

        SFCMock(sfcMock).setPendingRewards{value: pendingRewards}(address(sonicStaking), 1, pendingRewards);

        uint256 rateBefore = sonicStaking.getRate();
        assertEq(sonicStaking.balanceOf(user), assetAmount); // minted 1:1

        assertEq(rateBefore, 1 ether);

        uint256[] memory delegationIds = new uint256[](1);
        delegationIds[0] = 1;
        vm.prank(SONIC_STAKING_CLAIMOR);
        sonicStaking.claimRewards(delegationIds);

        uint256 protocolFee = pendingRewards * sonicStaking.protocolFeeBIPS() / sonicStaking.MAX_PROTOCOL_FEE_BIPS();

        uint256 assetIncrease = pendingRewards - protocolFee;
        uint256 newRate = (1 ether * (assetAmount + assetIncrease)) / assetAmount;

        assertGt(sonicStaking.getRate(), rateBefore);
        assertEq(sonicStaking.getRate(), newRate);

        // check that the conversion rate is applied for new deposits
        address newUser = vm.addr(201);
        uint256 newUserDepositAmount = 100 ether;
        makeDepositFromSpecifcUser(newUserDepositAmount, newUser);
        assertLt(sonicStaking.balanceOf(newUser), newUserDepositAmount); // got less shares than assets deposited (rate is >1)
        assertApproxEqAbs(sonicStaking.balanceOf(newUser) * sonicStaking.getRate() / 1e18, newUserDepositAmount, 1); // balance multiplied by rate should be equal to deposit amount
    }

    function testConvertToSharesRateOne() public {
        uint256 amount = 1000 ether;
        assertEq(sonicStaking.getRate(), 1 ether);
        uint256 shares = sonicStaking.convertToShares(amount);
        assertEq(shares, amount);
    }

    function testConvertToSharesIncreasedRate() public {
        uint256 assetAmount = 1_000 ether;
        uint256 delegateAmount = 1_000 ether;
        uint256 toValidatorId = 1;
        uint256 pendingRewards = 1 ether;
        address user = makeDeposit(assetAmount);
        delegate(toValidatorId, delegateAmount);

        SFCMock(sfcMock).setPendingRewards{value: pendingRewards}(address(sonicStaking), 1, pendingRewards);

        uint256 rateBefore = sonicStaking.getRate();
        assertEq(sonicStaking.balanceOf(user), assetAmount); // minted 1:1

        assertEq(rateBefore, 1 ether);

        uint256[] memory delegationIds = new uint256[](1);
        delegationIds[0] = 1;
        vm.prank(SONIC_STAKING_CLAIMOR);
        sonicStaking.claimRewards(delegationIds);

        uint256 protocolFee = pendingRewards * sonicStaking.protocolFeeBIPS() / sonicStaking.MAX_PROTOCOL_FEE_BIPS();

        uint256 assetIncrease = pendingRewards - protocolFee;

        // make sure that rate has increased for testing
        assertGt(sonicStaking.getRate(), rateBefore);

        uint256 sharesCalulcated = 1 ether * sonicStaking.totalSupply() / (assetAmount + assetIncrease);
        assertEq(sonicStaking.convertToShares(1 ether), sharesCalulcated);
    }

    function testConvertToAssetsRateOne() public {
        uint256 shares = 1000 ether;
        assertEq(sonicStaking.getRate(), 1 ether);
        uint256 amount = sonicStaking.convertToAssets(shares);
        assertEq(amount, shares);
    }

    function testConvertToAssetsIncreasedRate() public {
        uint256 assetAmount = 1_000 ether;
        uint256 delegateAmount = 1_000 ether;
        uint256 validatorId = 1;
        uint256 pendingRewards = 1 ether;
        address user = makeDeposit(assetAmount);
        delegate(validatorId, delegateAmount);

        SFCMock(sfcMock).setPendingRewards{value: pendingRewards}(address(sonicStaking), 1, pendingRewards);

        uint256 rateBefore = sonicStaking.getRate();
        assertEq(sonicStaking.balanceOf(user), assetAmount); // minted 1:1

        assertEq(rateBefore, 1 ether);

        uint256[] memory validatorIds = new uint256[](1);
        validatorIds[0] = 1;
        vm.prank(SONIC_STAKING_CLAIMOR);
        sonicStaking.claimRewards(validatorIds);

        uint256 protocolFee = pendingRewards * sonicStaking.protocolFeeBIPS() / sonicStaking.MAX_PROTOCOL_FEE_BIPS();

        uint256 assetIncrease = pendingRewards - protocolFee;

        // make sure that rate has increased for testing
        assertGt(sonicStaking.getRate(), rateBefore);

        uint256 assetsCalculated = 1 ether * (assetAmount + assetIncrease) / sonicStaking.totalSupply();
        assertEq(sonicStaking.convertToAssets(1 ether), assetsCalculated);
    }

    function testWithdraw() public {
        uint256 amount = 10_000 ether;
        uint256 delegateAmount = 10_000 ether;
        uint256 undelegateShares = sonicStaking.convertToShares(10_000 ether);
        uint256 validatorId = 1;

        address user = makeDeposit(amount);

        delegate(validatorId, delegateAmount);

        vm.prank(user);
        uint256 withdrawId = sonicStaking.undelegate(validatorId, undelegateShares);
        SonicStaking.WithdrawRequest memory withdrawRequestBefore = sonicStaking.getWithdrawRequest(withdrawId);

        vm.warp(block.timestamp + 14 days);

        uint256 balanceBefore = address(user).balance;

        vm.prank(user);
        vm.expectEmit(true, true, true, true);
        emit SonicStaking.Withdrawn(
            user, withdrawId, withdrawRequestBefore.assetAmount, SonicStaking.WithdrawKind.VALIDATOR, false
        );
        sonicStaking.withdraw(withdrawId, false);

        SonicStaking.WithdrawRequest memory withdrawRequest = sonicStaking.getWithdrawRequest(withdrawId);
        assertEq(address(user).balance, balanceBefore + withdrawRequest.assetAmount);

        assertEq(withdrawRequest.isWithdrawn, true);
    }

    function testWithdrawFromPool() public {
        uint256 amount = 10_000 ether;
        uint256 undelegateShares = sonicStaking.convertToShares(10_000 ether);

        address user = makeDeposit(amount);

        vm.prank(user);
        uint256 withdrawId = sonicStaking.undelegateFromPool(undelegateShares);
        SonicStaking.WithdrawRequest memory withdrawRequestBefore = sonicStaking.getWithdrawRequest(withdrawId);

        vm.warp(block.timestamp + 14 days);

        uint256 balanceBefore = address(user).balance;

        vm.prank(user);
        vm.expectEmit(true, true, true, true);
        emit SonicStaking.Withdrawn(
            user, withdrawId, withdrawRequestBefore.assetAmount, SonicStaking.WithdrawKind.POOL, false
        );
        sonicStaking.withdraw(withdrawId, false);

        SonicStaking.WithdrawRequest memory withdrawRequest = sonicStaking.getWithdrawRequest(withdrawId);
        assertEq(address(user).balance, balanceBefore + withdrawRequest.assetAmount);

        assertEq(withdrawRequest.isWithdrawn, true);
    }

    function testUndelegateAndWithdrawWithIncreasedRate() public {
        uint256 assetAmount = 10_000 ether;
        uint256 delegateAmount = 10_000 ether;
        uint256 undelegateAmount = 5_000 ether;
        uint256 pendingRewards = 100 ether;
        uint256 validatorId = 1;

        address user = makeDeposit(assetAmount);
        uint256 userBalanceBefore = address(user).balance;

        delegate(validatorId, delegateAmount);

        uint256[] memory validatorIds = new uint256[](1);
        validatorIds[0] = 1;

        SFCMock(sfcMock).setPendingRewards{value: pendingRewards}(address(sonicStaking), 1, pendingRewards);
        uint256[] memory delegationIds = new uint256[](1);
        delegationIds[0] = 1;
        vm.prank(SONIC_STAKING_CLAIMOR);
        sonicStaking.claimRewards(delegationIds);

        uint256 assetsToReceive = sonicStaking.convertToAssets(undelegateAmount);

        vm.prank(user);
        sonicStaking.undelegate(validatorId, undelegateAmount);

        // need to increase time to allow for withdraw
        vm.warp(block.timestamp + 14 days);

        SonicStaking.WithdrawRequest memory withdraw = sonicStaking.getWithdrawRequest(101);

        assertEq(withdraw.validatorId, validatorId);
        assertEq(withdraw.assetAmount, assetsToReceive);
        assertEq(withdraw.user, user);
        assertEq(withdraw.isWithdrawn, false);

        uint256 balanceBefore = address(user).balance;

        vm.prank(user);
        sonicStaking.withdraw(101, false);
        assertEq(address(user).balance, balanceBefore + assetsToReceive);
        assertGt(address(user).balance, userBalanceBefore);
    }

    function testWithdrawsPaused() public {
        uint256 amount = 10_000 ether;
        uint256 delegateAmount = 10_000 ether;
        uint256 undelegateShares = sonicStaking.convertToShares(10_000 ether);
        uint256 validatorId = 1;

        vm.prank(SONIC_STAKING_ADMIN);

        vm.expectEmit(true, true, true, true);
        emit SonicStaking.WithdrawPausedUpdated(address(SONIC_STAKING_ADMIN), true);
        sonicStaking.setWithdrawPaused(true);

        assertTrue(sonicStaking.withdrawPaused());

        address user = makeDeposit(amount);

        delegate(validatorId, delegateAmount);

        vm.prank(user);
        uint256 withdrawId = sonicStaking.undelegate(validatorId, undelegateShares);

        // need to increase time to allow for withdraw
        vm.warp(block.timestamp + 14 days);

        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(SonicStaking.WithdrawsPaused.selector));
        sonicStaking.withdraw(withdrawId, false);
    }

    function testUnsupportedWithdrawKind() public {
        uint256 amount = 10_000 ether;
        uint256 delegateAmount = 10_000 ether;
        uint256 validatorId = 1;

        makeDeposit(amount);

        delegate(validatorId, delegateAmount);

        vm.prank(SONIC_STAKING_OPERATOR);
        (uint256 withdrawId,) = sonicStaking.operatorInitiateClawBack(validatorId, delegateAmount);

        // need to increase time to allow for withdraw
        vm.warp(block.timestamp + 14 days);

        vm.prank(SONIC_STAKING_OPERATOR);
        vm.expectRevert(abi.encodeWithSelector(SonicStaking.UnsupportedWithdrawKind.selector));
        sonicStaking.withdraw(withdrawId, false);
    }

    function testEmergencyWithdraw() public {
        uint256 assetAmount = 1_000 ether;
        uint256 delegateAmount = 1_000 ether;
        uint256 validatorId = 1;
        address user = makeDeposit(assetAmount);
        uint256 slashRatio = 5 * 1e17;
        delegate(validatorId, delegateAmount);

        // slash the validator (slash half of the stake)
        sfcMock.setCheater(validatorId, true);
        sfcMock.setSlashRefundRatio(validatorId, slashRatio);

        vm.prank(user);
        uint256 withdrawId = sonicStaking.undelegate(validatorId, delegateAmount);
        assertEq(sonicStaking.withdrawCounter(), withdrawId);

        vm.warp(block.timestamp + 14 days);

        uint256 balanceBefore = address(user).balance;

        // do not emergency withdraw, will revert
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(SonicStaking.SfcSlashMustBeAccepted.selector, slashRatio));
        sonicStaking.withdraw(withdrawId, false);

        // emergency withdraw
        vm.prank(user);
        vm.expectEmit(true, true, true, true);
        // the SFC rounds the penalty 1 wei up, so we need to account for this
        emit SonicStaking.Withdrawn(user, withdrawId, delegateAmount / 2 - 1, SonicStaking.WithdrawKind.VALIDATOR, true);
        sonicStaking.withdraw(withdrawId, true);
        assertApproxEqAbs(address(user).balance, balanceBefore + (delegateAmount / 2), 1);
    }

    function testWithdrawMany() public {
        uint256 assetAmount = 10_000 ether;
        uint256 delegateAmount1 = 5_000 ether;
        uint256 delegateAmount2 = 5_000 ether;
        uint256 undelegateAmount1 = 5_000 ether;
        uint256 undelegateAmount2 = 5_000 ether;
        uint256 validatorId1 = 1;
        uint256 validatorId2 = 2;

        address user = makeDeposit(assetAmount);

        delegate(validatorId1, delegateAmount1);
        delegate(validatorId2, delegateAmount2);

        uint256[] memory validatorIds = new uint256[](2);
        validatorIds[0] = 1;
        validatorIds[1] = 2;

        uint256[] memory amountShares = new uint256[](2);
        amountShares[0] = undelegateAmount1;
        amountShares[1] = undelegateAmount2;

        uint256 undelegateAmountAssets1 = sonicStaking.convertToAssets(undelegateAmount1);
        uint256 undelegateAmountAssets2 = sonicStaking.convertToAssets(undelegateAmount2);

        vm.prank(user);
        uint256[] memory withdrawIds = sonicStaking.undelegateMany(validatorIds, amountShares);

        // need to increase time to allow for withdraw
        vm.warp(block.timestamp + 14 days);

        uint256 balanceBefore = user.balance;

        vm.prank(user);
        sonicStaking.withdrawMany(withdrawIds, false);
        assertEq(address(user).balance, balanceBefore + undelegateAmountAssets1 + undelegateAmountAssets2);

        SonicStaking.WithdrawRequest memory withdrawAfter1 = sonicStaking.getWithdrawRequest(101);
        assertEq(withdrawAfter1.isWithdrawn, true);

        SonicStaking.WithdrawRequest memory withdrawAfter2 = sonicStaking.getWithdrawRequest(102);
        assertEq(withdrawAfter2.isWithdrawn, true);
    }

    function testWithdrawManyWithIncreasedRate() public {
        uint256 assetAmount = 10_000 ether;
        uint256 delegateAmount1 = 5_000 ether;
        uint256 delegateAmount2 = 5_000 ether;
        uint256 undelegateAmount1 = 4_000 ether;
        uint256 undelegateAmount2 = 4_000 ether;
        uint256 pendingRewards = 1 ether;
        uint256 validatorId1 = 1;
        uint256 validatorId2 = 2;

        address user = makeDeposit(assetAmount);

        delegate(validatorId1, delegateAmount1);
        delegate(validatorId2, delegateAmount2);

        SFCMock(sfcMock).setPendingRewards{value: pendingRewards}(address(sonicStaking), 1, pendingRewards);

        uint256[] memory claimValidatorIds = new uint256[](1);
        claimValidatorIds[0] = 1;
        vm.prank(SONIC_STAKING_CLAIMOR);
        sonicStaking.claimRewards(claimValidatorIds);

        uint256[] memory validatorIds = new uint256[](2);
        validatorIds[0] = 1;
        validatorIds[1] = 2;

        uint256[] memory amountShares = new uint256[](2);
        amountShares[0] = undelegateAmount1;
        amountShares[1] = undelegateAmount2;

        uint256 undelegateAmountAssets1 = sonicStaking.convertToAssets(undelegateAmount1);
        uint256 undelegateAmountAssets2 = sonicStaking.convertToAssets(undelegateAmount2);

        vm.prank(user);
        uint256[] memory withdrawIds = sonicStaking.undelegateMany(validatorIds, amountShares);

        // need to increase time to allow for withdraw
        vm.warp(block.timestamp + 14 days);

        uint256 balanceBefore = user.balance;

        vm.prank(user);
        sonicStaking.withdrawMany(withdrawIds, false);
        assertEq(address(user).balance, balanceBefore + undelegateAmountAssets1 + undelegateAmountAssets2);

        SonicStaking.WithdrawRequest memory withdrawAfter1 = sonicStaking.getWithdrawRequest(101);
        assertEq(withdrawAfter1.isWithdrawn, true);

        SonicStaking.WithdrawRequest memory withdrawAfter2 = sonicStaking.getWithdrawRequest(102);
        assertEq(withdrawAfter2.isWithdrawn, true);
    }

    function testOperatorClawBackInitiateAndExecute() public {
        uint256 assetAmount = 10_000 ether;
        uint256 delegateAmount = 1_000 ether;
        uint256 undelegateAmount = 1_000 ether;
        uint256 toValidatorId = 1;

        (,,,, uint256 withdrawCounterStart) = getState();

        makeDeposit(assetAmount);
        delegate(toValidatorId, delegateAmount);

        vm.prank(SONIC_STAKING_OPERATOR);
        sonicStaking.operatorInitiateClawBack(1, undelegateAmount);

        assertEq(sonicStaking.totalDelegated(), 0);
        assertEq(sonicStaking.totalPool(), assetAmount - delegateAmount);
        assertEq(sonicStaking.totalAssets(), assetAmount);
        assertEq(sonicStaking.getRate(), 1 ether);
        assertEq(sonicStaking.withdrawCounter(), withdrawCounterStart + 1);
        assertEq(sonicStaking.pendingClawBackAmount(), undelegateAmount);

        // need to increase time to allow for withdraw
        vm.warp(block.timestamp + 14 days);

        vm.prank(SONIC_STAKING_OPERATOR);
        sonicStaking.operatorExecuteClawBack(101, false);

        assertEq(sonicStaking.totalDelegated(), 0);
        assertEq(sonicStaking.totalPool(), assetAmount);
        assertEq(sonicStaking.totalAssets(), assetAmount);
        assertEq(sonicStaking.getRate(), 1 ether);
        assertEq(sonicStaking.withdrawCounter(), withdrawCounterStart + 1);
        assertEq(sonicStaking.pendingClawBackAmount(), 0);
    }

    function testSlashedValidatorHasNoImpactWithoutWithdraw() public {
        uint256 assetAmount = 1_000 ether;
        uint256 delegateAmount = 1_000 ether;
        uint256 validatorId = 1;
        uint256 slashRatio = 5 * 1e17;
        makeDeposit(assetAmount);
        delegate(validatorId, delegateAmount);

        uint256 rateBefore = sonicStaking.getRate();
        uint256 totalPoolBefore = sonicStaking.totalPool();
        uint256 totalAssetsBefore = sonicStaking.totalAssets();
        uint256 totalDelegatedBefore = sonicStaking.totalDelegated();

        // slash the validator (slash half of the stake)
        sfcMock.setCheater(validatorId, true);
        sfcMock.setSlashRefundRatio(validatorId, slashRatio);

        assertEq(SFC.getStake(address(sonicStaking), validatorId), delegateAmount);

        assertEq(sonicStaking.getRate(), rateBefore);
        assertEq(sonicStaking.totalPool(), totalPoolBefore);
        assertEq(sonicStaking.totalAssets(), totalAssetsBefore);
        assertEq(sonicStaking.totalDelegated(), totalDelegatedBefore);
    }

    function testSlashedValidatorImpactOnOperatorClawBack() public {
        uint256 assetAmount = 1_000 ether;
        uint256 delegateAmount = 1_000 ether;
        uint256 undelegateAmount = 1_000 ether;
        uint256 validatorId = 1;
        uint256 slashRatio = 5 * 1e17;
        makeDeposit(assetAmount);
        delegate(validatorId, delegateAmount);

        uint256 rateBefore = sonicStaking.getRate();

        // slash the validator (slash half of the stake)
        sfcMock.setCheater(validatorId, true);
        sfcMock.setSlashRefundRatio(validatorId, slashRatio);

        uint256 undelegateAmountAsset = sonicStaking.convertToAssets(undelegateAmount);

        vm.prank(SONIC_STAKING_OPERATOR);
        (uint256 withdrawId,) = sonicStaking.operatorInitiateClawBack(validatorId, undelegateAmount);

        // need to increase time to allow for withdraw
        vm.warp(block.timestamp + 14 days);

        // emergency == false, should fail the invariant check
        vm.prank(SONIC_STAKING_OPERATOR);
        vm.expectRevert(abi.encodeWithSelector(SonicStaking.SfcSlashMustBeAccepted.selector, slashRatio));
        sonicStaking.operatorExecuteClawBack(withdrawId, false);

        // emergency withdraw
        vm.prank(SONIC_STAKING_OPERATOR);
        vm.expectEmit(true, true, true, true);
        // the SFC rounds the penalty 1 wei up, so we need to account for this
        emit SonicStaking.OperatorClawBackExecuted(withdrawId, undelegateAmount / 2 - 1, true);
        sonicStaking.operatorExecuteClawBack(withdrawId, true);

        assertEq(sonicStaking.totalDelegated(), 0);
        assertApproxEqAbs(sonicStaking.totalPool(), undelegateAmountAsset / 2, 1);
        assertApproxEqAbs(sonicStaking.totalAssets(), undelegateAmountAsset / 2, 1);
        assertLt(sonicStaking.getRate(), rateBefore);
        assertApproxEqAbs(sonicStaking.getRate(), rateBefore / 2, 1);
    }

    function testOperatorWithdrawUnsupportedWithdrawKind() public {
        uint256 amount = 1_000 ether;
        uint256 undelegateAmount = 100 ether;
        uint256 undelegateAmountShares = sonicStaking.convertToShares(undelegateAmount);
        uint256 validatorId = 1;

        makeDepositFromSpecifcUser(amount, SONIC_STAKING_OPERATOR);

        delegate(validatorId, amount);

        vm.startPrank(SONIC_STAKING_OPERATOR);
        (uint256 operatorWithdrawId,) = sonicStaking.operatorInitiateClawBack(validatorId, undelegateAmount);

        uint256 userWithdrawId = sonicStaking.undelegate(validatorId, undelegateAmountShares);

        // need to increase time to allow for withdraw
        vm.warp(block.timestamp + 14 days);

        vm.expectRevert(abi.encodeWithSelector(SonicStaking.UnsupportedWithdrawKind.selector));
        sonicStaking.withdraw(operatorWithdrawId, false);

        vm.expectRevert(abi.encodeWithSelector(SonicStaking.UnsupportedWithdrawKind.selector));
        sonicStaking.operatorExecuteClawBack(userWithdrawId, false);
    }

    // when rewards are claimed, a few things happen
    // 1. a protocol fee (sonicStaking.protocolFeeBIPS) is taken and sent to TREAUSRY_ADDRESS
    // 2. the total pool increases by the remaining rewards
    // 3. Because the total pool increases, the rate of shares increases
    function testClaimReward() public {
        uint256 assetAmount = 100_000 ether;
        uint256 delegateAmount = 1_000 ether;
        uint256 toValidatorId = 1;
        uint256 pendingRewards = 100 ether;
        makeDeposit(assetAmount);
        delegate(toValidatorId, delegateAmount);

        SFCMock(sfcMock).setPendingRewards{value: pendingRewards}(address(sonicStaking), 1, pendingRewards);
        assertEq(sfcMock.pendingRewards(address(sonicStaking), 1), pendingRewards);

        uint256 treasuryBalanceBefore = TREASURY_ADDRESS.balance;
        uint256 rateBefore = sonicStaking.getRate();
        uint256 poolBefore = sonicStaking.totalPool();
        uint256 totalAssets = sonicStaking.totalAssets();

        assertEq(rateBefore, 1 ether);
        uint256 protocolFee = pendingRewards * sonicStaking.protocolFeeBIPS() / sonicStaking.MAX_PROTOCOL_FEE_BIPS();

        uint256[] memory delegationIds = new uint256[](1);
        delegationIds[0] = 1;

        vm.prank(SONIC_STAKING_CLAIMOR);
        vm.expectEmit(true, true, true, true);
        emit SonicStaking.RewardsClaimed(pendingRewards, protocolFee);
        sonicStaking.claimRewards(delegationIds);

        assertEq(sfcMock.pendingRewards(address(sonicStaking), 1), 0);
        assertEq(TREASURY_ADDRESS.balance, treasuryBalanceBefore + protocolFee);
        assertEq(sonicStaking.totalPool(), poolBefore + (pendingRewards - protocolFee));
        assertEq(sonicStaking.totalAssets(), totalAssets + (pendingRewards - protocolFee));
        assertGt(sonicStaking.getRate(), rateBefore);
    }

    function testClaimRewardAmountTooSmall() public {
        uint256[] memory delegationIds = new uint256[](1);
        delegationIds[0] = 1;
        vm.prank(SONIC_STAKING_CLAIMOR);
        vm.expectRevert(abi.encodeWithSelector(SonicStaking.RewardsClaimedTooSmall.selector));
        sonicStaking.claimRewards(delegationIds);
    }

    function testClaimRewardUnauthorized() public {
        uint256[] memory delegationIds = new uint256[](1);
        delegationIds[0] = 1;
        vm.expectRevert(
            abi.encodeWithSelector(AccessControlUnauthorizedAccount.selector, address(this), sonicStaking.CLAIM_ROLE())
        );
        sonicStaking.claimRewards(delegationIds);
    }

    function testValidatorFullySlashed() public {
        uint256 assetAmount = 1_000 ether;
        uint256 delegateAmount = 1_000 ether;
        uint256 validatorId = 1;
        uint256 slashRatio = 0;

        makeDeposit(assetAmount);
        delegate(validatorId, delegateAmount);

        // slash the validator's full stake
        sfcMock.setCheater(validatorId, true);
        sfcMock.setSlashRefundRatio(validatorId, 0);

        vm.prank(SONIC_STAKING_OPERATOR);
        (uint256 withdrawId,) = sonicStaking.operatorInitiateClawBack(validatorId, delegateAmount);

        vm.warp(block.timestamp + 14 days);

        uint256 totalPoolBefore = sonicStaking.totalPool();

        vm.prank(SONIC_STAKING_OPERATOR);
        vm.expectRevert(abi.encodeWithSelector(SonicStaking.SfcSlashMustBeAccepted.selector, slashRatio));
        sonicStaking.operatorExecuteClawBack(withdrawId, false);

        vm.prank(SONIC_STAKING_OPERATOR);
        uint256 amountWithdrawn = sonicStaking.operatorExecuteClawBack(withdrawId, true);

        assertEq(amountWithdrawn, 0);
        assertEq(totalPoolBefore, sonicStaking.totalPool());
    }

    function getState()
        public
        view
        returns (uint256 totalDelegated, uint256 totalPool, uint256 totalSWorth, uint256 rate, uint256 lastUsedWrId)
    {
        totalDelegated = sonicStaking.totalDelegated();
        totalPool = sonicStaking.totalPool();
        totalSWorth = sonicStaking.totalAssets();
        rate = sonicStaking.getRate();
        lastUsedWrId = sonicStaking.withdrawCounter();
    }
}
