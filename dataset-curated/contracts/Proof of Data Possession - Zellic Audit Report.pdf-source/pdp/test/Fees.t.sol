// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console2} from "forge-std/Test.sol";
import {PDPFees} from "../src/Fees.sol";

contract PDPFeesTest is Test {
    uint256 constant epochs_per_day = 2880;

    function computeRewardPerPeriod(uint64 filUsdPrice, int32 filUsdPriceExpo, uint256 rawSize) internal pure returns (uint256) {
        uint256 rewardPerEpochPerByte;
        if (filUsdPriceExpo >= 0) {
            rewardPerEpochPerByte = (PDPFees.ESTIMATED_MONTHLY_TIB_STORAGE_REWARD_USD * PDPFees.FIL_TO_ATTO_FIL) /
                (PDPFees.TIB_IN_BYTES * PDPFees.EPOCHS_PER_MONTH * filUsdPrice * (10 ** uint32(filUsdPriceExpo)));
        } else {
            rewardPerEpochPerByte = (PDPFees.ESTIMATED_MONTHLY_TIB_STORAGE_REWARD_USD * PDPFees.FIL_TO_ATTO_FIL * (10 ** uint32(-filUsdPriceExpo))) /
                (PDPFees.TIB_IN_BYTES * PDPFees.EPOCHS_PER_MONTH * filUsdPrice);
        }
        uint256 rewardPerPeriod = rewardPerEpochPerByte * epochs_per_day * rawSize;
        return rewardPerPeriod;
    }

    /// forge-config: default.allow_internal_expect_revert = true
    function testProofFeeWithGasFeeBoundZeroGasFee() public {
        vm.expectRevert("failed to validate: estimated gas fee must be greater than 0");
        vm.fee(1000);
        PDPFees.proofFeeWithGasFeeBound(0, 5, 0, 1e18, epochs_per_day);
    }

    /// forge-config: default.allow_internal_expect_revert = true
    function testProofFeeWithGasFeeBoundZeroAttoFilUsdPrice() public {
        vm.expectRevert("failed to validate: AttoFIL price must be greater than 0");
        PDPFees.proofFeeWithGasFeeBound(1, 0, 0, 1e18, epochs_per_day);
    }

    /// forge-config: default.allow_internal_expect_revert = true
    function testProofFeeWithGasFeeBoundZeroRawSize() public {
        vm.expectRevert("failed to validate: raw size must be greater than 0");
        PDPFees.proofFeeWithGasFeeBound(1, 5, 0, 0, epochs_per_day);
    }

    function testProofFeeWithGasFeeBoundHighGasFee() public view {
        uint64 filUsdPrice = 5;
        int32 filUsdPriceExpo = 0;
        uint256 rawSize = 1e18;

        uint256 rewardPerPeriod = computeRewardPerPeriod(filUsdPrice, filUsdPriceExpo, rawSize);

        uint256 gasLimitRight = (rewardPerPeriod * PDPFees.GAS_LIMIT_RIGHT_PERCENTAGE) / 100;

        uint256 estimatedGasFee = gasLimitRight;

        uint256 fee = PDPFees.proofFeeWithGasFeeBound(estimatedGasFee, filUsdPrice, filUsdPriceExpo, rawSize, epochs_per_day);

        assertEq(fee, 0, "Fee should be 0 when gas fee is high");
    }

    function testProofFeeWithGasFeeBoundMediumGasFee() public view {
        uint64 filUsdPrice = 5;
        int32 filUsdPriceExpo = 0;
        uint256 rawSize = 1e18;

        uint256 rewardPerPeriod = computeRewardPerPeriod(filUsdPrice, filUsdPriceExpo, rawSize);

        uint256 gasLimitLeft = (rewardPerPeriod * PDPFees.GAS_LIMIT_LEFT_PERCENTAGE) / 100;
        uint256 gasLimitRight = (rewardPerPeriod * PDPFees.GAS_LIMIT_RIGHT_PERCENTAGE) / 100;

        uint256 estimatedGasFee = (gasLimitLeft + gasLimitRight) / 2;

        uint256 fee = PDPFees.proofFeeWithGasFeeBound(estimatedGasFee, filUsdPrice, filUsdPriceExpo, rawSize, epochs_per_day);

        uint256 expectedFee = gasLimitRight - estimatedGasFee;

        assertEq(fee, expectedFee, "Fee should be partially discounted");
    }

    function testProofFeeWithGasFeeBoundLowGasFee() public view {
        uint64 filUsdPrice = 5;
        int32 filUsdPriceExpo = 0;
        uint256 rawSize = 1e18;

        uint256 rewardPerPeriod = computeRewardPerPeriod(filUsdPrice, filUsdPriceExpo, rawSize);

        uint256 gasLimitLeft = (rewardPerPeriod * PDPFees.GAS_LIMIT_LEFT_PERCENTAGE) / 100;

        uint256 estimatedGasFee = gasLimitLeft / 2;

        uint256 fee = PDPFees.proofFeeWithGasFeeBound(estimatedGasFee, filUsdPrice, filUsdPriceExpo, rawSize, epochs_per_day);

        uint256 expectedFee = (rewardPerPeriod * PDPFees.PROOF_FEE_PERCENTAGE) / 100;

        assertEq(fee, expectedFee, "Fee should be full proof fee when gas fee is low");
    }

    function testProofFeeWithGasFeeBoundNegativeExponent() public view {
        uint64 filUsdPrice = 5000;
        int32 filUsdPriceExpo = -3;
        uint256 rawSize = 1e18;
        uint256 estimatedGasFee = 1e15;

        uint256 fee = PDPFees.proofFeeWithGasFeeBound(estimatedGasFee, filUsdPrice, filUsdPriceExpo, rawSize, epochs_per_day);
        assertTrue(fee > 0, "Fee should be positive with negative exponent");
    }

    function testProofFeeWithGasFeeBoundLargeRawSize() public view {
        uint64 filUsdPrice = 5;
        int32 filUsdPriceExpo = 0;
        uint256 rawSize = 1e30;
        uint256 estimatedGasFee = 1e15;

        uint256 fee = PDPFees.proofFeeWithGasFeeBound(estimatedGasFee, filUsdPrice, filUsdPriceExpo, rawSize, epochs_per_day);
        assertTrue(fee > 0, "Fee should be positive for large raw size");
    }

    function testProofFeeWithGasFeeBoundSmallRawSize() public view {
        uint64 filUsdPrice = 5;
        int32 filUsdPriceExpo = 0;
        uint256 rawSize = 1;

        uint256 rewardPerPeriod = computeRewardPerPeriod(filUsdPrice, filUsdPriceExpo, rawSize);
        uint256 gasLimitLeft = (rewardPerPeriod * PDPFees.GAS_LIMIT_LEFT_PERCENTAGE) / 100;

        uint256 estimatedGasFee = gasLimitLeft / 2;

        uint256 fee = PDPFees.proofFeeWithGasFeeBound(estimatedGasFee, filUsdPrice, filUsdPriceExpo, rawSize, epochs_per_day);

        uint256 expectedFee = (rewardPerPeriod * PDPFees.PROOF_FEE_PERCENTAGE) / 100;

        assertEq(fee, expectedFee, "Fee should be full proof fee when gas fee is low");
    }

    function testProofFeeWithGasFeeBoundHalfDollarFil() public view {
        uint64 filUsdPrice = 5;
        int32 filUsdPriceExpo = -1; // 0.5 USD per FIL
        uint256 rawSize = 1e18;
        uint256 estimatedGasFee = 1e15;

        uint256 fee = PDPFees.proofFeeWithGasFeeBound(estimatedGasFee, filUsdPrice, filUsdPriceExpo, rawSize,epochs_per_day);
        assertTrue(fee > 0, "Fee should be positive with FIL price at $0.50");

        // With lower FIL price, fee should be higher than when price is $5
        uint256 feeAt5Dollars = PDPFees.proofFeeWithGasFeeBound(estimatedGasFee, filUsdPrice, 0, rawSize, epochs_per_day);
        assertTrue(fee > feeAt5Dollars, "Fee should be higher with lower FIL price");
    }

    function testSybilFee() public pure {
        uint256 fee = PDPFees.sybilFee();
        assertEq(fee, PDPFees.SYBIL_FEE, "Sybil fee should match the constant");
    }

    function testProofFeeWithGasFeeBoundAtLeftBoundary() public view {
        uint64 filUsdPrice = 5;
        int32 filUsdPriceExpo = 0;
        uint256 rawSize = 1e18;

        uint256 rewardPerPeriod = computeRewardPerPeriod(filUsdPrice, filUsdPriceExpo, rawSize);
        uint256 gasLimitLeft = (rewardPerPeriod * PDPFees.GAS_LIMIT_LEFT_PERCENTAGE) / 100;
        
        // Test exactly at gasLimitLeft
        uint256 estimatedGasFee = gasLimitLeft;
        
        uint256 fee = PDPFees.proofFeeWithGasFeeBound(estimatedGasFee, filUsdPrice, filUsdPriceExpo, rawSize, epochs_per_day);
        
        uint256 expectedFee = (rewardPerPeriod * PDPFees.PROOF_FEE_PERCENTAGE) / 100;
        assertEq(fee, expectedFee, "Fee should be full proof fee at left boundary");
    }

    function testProofFeeWithGasFeeBoundNearRightBoundary() public view {
        uint64 filUsdPrice = 5;
        int32 filUsdPriceExpo = 0;
        uint256 rawSize = 1e18;

        uint256 rewardPerPeriod = computeRewardPerPeriod(filUsdPrice, filUsdPriceExpo, rawSize);
        uint256 gasLimitRight = (rewardPerPeriod * PDPFees.GAS_LIMIT_RIGHT_PERCENTAGE) / 100;
        
        // Test at gasLimitRight - 1
        uint256 estimatedGasFee = gasLimitRight - 1;
        
        uint256 fee = PDPFees.proofFeeWithGasFeeBound(estimatedGasFee, filUsdPrice, filUsdPriceExpo, rawSize, epochs_per_day);
        
        uint256 expectedFee = 1; // Should be gasLimitRight - estimatedGasFee = 1
        assertEq(fee, expectedFee, "Fee should be 1 when estimatedGasFee is just below right boundary");
    }
}
