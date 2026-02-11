// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.27;

import {Test, console} from "forge-std/Test.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {SonicStaking} from "src/SonicStaking.sol";
import {SonicStakingTestSetup} from "./SonicStakingTestSetup.sol";

import {ISFC} from "src/interfaces/ISFC.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {IAccessControl} from "openzeppelin-contracts/access/IAccessControl.sol";

contract SonicStakingTest is Test, SonicStakingTestSetup {
    error AccessControlUnauthorizedAccount(address account, bytes32 neededRole);

    uint256 constant S_MAX_SUPPLY = 4e27;

    function testFuzzUserWithdraws(
        uint256 amount,
        uint256 undelegateAmount1,
        uint256 undelegateAmount2,
        uint256 undelegateAmount3
    ) public {
        uint256 validatorId = 1;
        vm.assume(amount >= 1 ether);
        uint256 validatorSelfStake = SFC.getSelfStake(validatorId);
        amount = bound(amount, 3 ether, validatorSelfStake * 15);
        undelegateAmount1 = bound(amount, 1 ether, amount / 3);
        undelegateAmount2 = bound(amount, 1 ether, amount / 3);
        undelegateAmount3 = bound(amount, 1 ether, amount / 3);

        address user = makeDeposit(amount);

        delegate(validatorId, amount);

        // Create 3 undelegate requests
        uint256[] memory validatorIds = new uint256[](3);
        uint256[] memory undelegateAmountShares = new uint256[](3);

        validatorIds[0] = validatorId;
        validatorIds[1] = validatorId;
        validatorIds[2] = validatorId;

        undelegateAmountShares[0] = undelegateAmount1;
        undelegateAmountShares[1] = undelegateAmount2;
        undelegateAmountShares[2] = undelegateAmount3;

        vm.prank(user);
        sonicStaking.undelegateMany(validatorIds, undelegateAmountShares);

        // Test getting all withdraws
        SonicStaking.WithdrawRequest[] memory withdraws = sonicStaking.getUserWithdraws(user, 0, 3, false);
        assertEq(withdraws.length, 3);
        assertEq(withdraws[0].assetAmount, undelegateAmount1);
        assertEq(withdraws[1].assetAmount, undelegateAmount2);
        assertEq(withdraws[2].assetAmount, undelegateAmount3);

        // Test pagination
        withdraws = sonicStaking.getUserWithdraws(user, 1, 2, false);
        assertEq(withdraws.length, 2);
        assertEq(withdraws[0].assetAmount, undelegateAmount2);
        assertEq(withdraws[1].assetAmount, undelegateAmount3);

        // Test reverse order
        withdraws = sonicStaking.getUserWithdraws(user, 0, 3, true);
        assertEq(withdraws.length, 3);
        assertEq(withdraws[0].assetAmount, undelegateAmount3);
        assertEq(withdraws[1].assetAmount, undelegateAmount2);
        assertEq(withdraws[2].assetAmount, undelegateAmount1);

        // Test reverse order with pagination
        withdraws = sonicStaking.getUserWithdraws(user, 1, 2, true);
        assertEq(withdraws.length, 2);
        assertEq(withdraws[0].assetAmount, undelegateAmount2);
        assertEq(withdraws[1].assetAmount, undelegateAmount1);
    }

    function testFuzzDeposit(uint256 amountAssets) public {
        amountAssets = bound(amountAssets, 1 ether, S_MAX_SUPPLY);
        uint256 amountShares = sonicStaking.convertToShares(amountAssets);

        assertEq(sonicStaking.totalPool(), 0);
        assertEq(sonicStaking.totalAssets(), 0);
        assertEq(sonicStaking.totalSupply(), 0);

        address user = vm.addr(200);

        vm.expectEmit(true, true, true, true);
        emit SonicStaking.Deposited(user, amountAssets, amountShares);

        makeDepositFromSpecifcUser(amountAssets, user);

        assertEq(sonicStaking.totalPool(), amountAssets);
        assertEq(sonicStaking.totalAssets(), amountAssets);

        assertEq(sonicStaking.totalSupply(), amountShares);
        assertEq(sonicStaking.balanceOf(user), amountShares);
    }

    function testFuzzUndelegate(uint256 amount, uint256 undelegateAmount) public {
        uint256 validatorId = 1;
        uint256 validatorSelfStake = SFC.getSelfStake(validatorId);
        amount = bound(amount, 3 ether, validatorSelfStake * 15);
        undelegateAmount = bound(undelegateAmount, 1 ether, amount);

        uint256 amountShares = sonicStaking.convertToShares(undelegateAmount);

        address user = makeDeposit(amount);
        delegate(validatorId, amount);

        uint256 userSharesBefore = sonicStaking.balanceOf(user);

        vm.expectEmit(true, true, true, true);
        emit IERC20.Transfer(user, address(0), amountShares);

        vm.prank(user);
        vm.expectEmit(true, true, true, true);
        emit SonicStaking.Undelegated(user, 101, validatorId, undelegateAmount, SonicStaking.WithdrawKind.VALIDATOR);
        uint256 withdrawId = sonicStaking.undelegate(validatorId, amountShares);

        assertEq(sonicStaking.balanceOf(user), userSharesBefore - amountShares);
        assertEq(sonicStaking.totalDelegated(), amount - undelegateAmount);
        assertEq(sonicStaking.totalAssets(), amount - undelegateAmount);

        SonicStaking.WithdrawRequest memory withdrawRequest = sonicStaking.getWithdrawRequest(withdrawId);

        assertEq(withdrawRequest.assetAmount, undelegateAmount);
        assertEq(withdrawRequest.isWithdrawn, false);
        assertEq(withdrawRequest.user, user);
        assertEq(withdrawRequest.validatorId, validatorId);
    }

    function testFuzzExtremeRatesAlwaysRoundInFavorOfProtocol(
        uint256 depositAmount,
        uint256 donationAmount,
        uint256 undelegateAmount
    ) public {
        depositAmount = bound(depositAmount, sonicStaking.MIN_DEPOSIT(), S_MAX_SUPPLY);
        donationAmount = bound(donationAmount, 10_000 ether, S_MAX_SUPPLY);

        makeDeposit(sonicStaking.MIN_DEPOSIT());

        // This will blow up the rate
        donate(donationAmount);

        uint256 rateBefore = sonicStaking.getRate();

        uint256 sharesExpected = sonicStaking.convertToShares(depositAmount);
        uint256 sharesExpectedCalculated = depositAmount * rateBefore / 1e18;

        // Make a deposit of various sizes (min - Max s supply)
        address newUser = vm.addr(201);
        makeDepositFromSpecifcUser(depositAmount, newUser);

        uint256 raterAfterDeposit = sonicStaking.getRate();
        uint256 sharesActual = sonicStaking.balanceOf(newUser);

        // The rate should never go down after a deposit
        assertGe(raterAfterDeposit, rateBefore);
        // The shares received should always equal what convertToShares returned
        assertEq(sharesActual, sharesExpected);
        // Any rounding should always favor the protocol, so the user should receive less than what was calculated
        assertLe(sharesActual, sharesExpectedCalculated);
    }
}
