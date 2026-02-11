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
    uint256 constant S_MAX_SUPPLY = 4e27;

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

    function testFuzzGetRateIncrease(
        uint256 assetAmount,
        uint256 delegateAmount,
        uint256 pendingRewards,
        uint256 newUserAssetAmount
    ) public {
        assetAmount = bound(assetAmount, 1 ether, S_MAX_SUPPLY);
        newUserAssetAmount = bound(newUserAssetAmount, 1 ether, S_MAX_SUPPLY);
        pendingRewards = bound(pendingRewards, 1 ether, 10000 ether);
        delegateAmount = bound(delegateAmount, 1 ether, assetAmount);

        uint256 validatorId = 1;
        address user = makeDeposit(assetAmount);
        delegate(validatorId, delegateAmount);

        SFCMock(sfcMock).setPendingRewards{value: pendingRewards}(address(sonicStaking), validatorId, pendingRewards);

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

        // check that the conversion rate is applied for new deposits
        address newUser = vm.addr(201);
        uint256 rateBeforeSecondDeposit = sonicStaking.getRate();
        makeDepositFromSpecifcUser(newUserAssetAmount, newUser);
        assertLt(sonicStaking.balanceOf(newUser), newUserAssetAmount); // got less shares than assets deposited (rate is >1)
        assertApproxEqAbs(sonicStaking.balanceOf(newUser) * sonicStaking.getRate() / 1e18, newUserAssetAmount, 1e18); // balance multiplied by rate should be equal to deposit amount
        //We expect that the rate will never go down
        assertGe(sonicStaking.getRate(), rateBeforeSecondDeposit);
    }

    function testFuzzExtremeRatesAlwaysRoundInFavorOfProtocolUndelegateWithdraw(
        uint256 depositAmount,
        uint256 donationAmount,
        uint256 undelegateAmount
    ) public {
        depositAmount = bound(depositAmount, sonicStaking.MIN_DEPOSIT(), 100 ether);
        donationAmount = bound(donationAmount, 10_000 ether, S_MAX_SUPPLY);

        // We burn 1 ether to make sure the supply cannot go back to zero
        address burnAddress = vm.addr(1);
        makeDepositFromSpecifcUser(1 ether, burnAddress);

        address user = makeDeposit(depositAmount);
        uint256 userShares = sonicStaking.balanceOf(user);

        // This will blow up the rate
        donate(donationAmount);

        uint256 rateAfterDonate = sonicStaking.getRate();

        // delegate everything
        delegate(1, depositAmount + donationAmount);

        undelegateAmount = bound(undelegateAmount, sonicStaking.MIN_UNDELEGATE_AMOUNT_SHARES(), userShares);

        vm.prank(user);
        uint256 withdrawId = sonicStaking.undelegate(1, undelegateAmount);

        uint256 rateAfterUndelegate = sonicStaking.getRate();

        // The rate should never go down after an undelegate
        assertGe(rateAfterUndelegate, rateAfterDonate);

        // need to increase time to allow for withdraw
        vm.warp(block.timestamp + 14 days);

        vm.prank(user);
        // Withdraw the undelegated amount
        sonicStaking.withdraw(withdrawId, false);

        uint256 rateAfterWithdraw = sonicStaking.getRate();

        // The rate should never go down after a withdraw
        assertGe(rateAfterWithdraw, rateAfterUndelegate);
    }
}
