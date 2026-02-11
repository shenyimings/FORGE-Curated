// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.26;

import { Upgrades, UnsafeUpgrades } from "../../../../lib/openzeppelin-foundry-upgrades/src/Upgrades.sol";

import { IContinuousIndexing } from "../../../../src/projects/yieldToAllWithFee/interfaces/IContinuousIndexing.sol";
import { IRateOracle } from "../../../../src/projects/yieldToAllWithFee/interfaces/IRateOracle.sol";
import { IMSpokeYieldFee } from "../../../../src/projects/yieldToAllWithFee/interfaces/IMSpokeYieldFee.sol";

import { MSpokeYieldFeeHarness } from "../../../harness/MSpokeYieldFeeHarness.sol";
import { BaseUnitTest } from "../../../utils/BaseUnitTest.sol";

contract MSpokeYieldFeeUnitTests is BaseUnitTest {
    bytes32 public constant FEE_MANAGER_ROLE = keccak256("FEE_MANAGER_ROLE");

    MSpokeYieldFeeHarness public mYieldFee;

    function setUp() public override {
        super.setUp();

        mYieldFee = MSpokeYieldFeeHarness(
            Upgrades.deployUUPSProxy(
                "MSpokeYieldFeeHarness.sol:MSpokeYieldFeeHarness",
                abi.encodeWithSelector(
                    MSpokeYieldFeeHarness.initialize.selector,
                    "MSpokeYieldFee",
                    "MSYF",
                    address(mToken),
                    address(swapFacility),
                    YIELD_FEE_RATE,
                    feeRecipient,
                    admin,
                    yieldFeeManager,
                    claimRecipientManager,
                    address(rateOracle)
                )
            )
        );
    }

    /* ============ initialize ============ */

    function test_initialize() external view {
        assertEq(mYieldFee.ONE_HUNDRED_PERCENT(), 10_000);
        assertEq(mYieldFee.latestIndex(), EXP_SCALED_ONE);
        assertEq(mYieldFee.feeRate(), YIELD_FEE_RATE);
        assertEq(mYieldFee.feeRecipient(), feeRecipient);
        assertTrue(mYieldFee.hasRole(DEFAULT_ADMIN_ROLE, admin));
        assertTrue(mYieldFee.hasRole(FEE_MANAGER_ROLE, yieldFeeManager));
        assertEq(mYieldFee.rateOracle(), address(rateOracle));
    }

    function test_initialize_zeroRateOracle() external {
        address implementation = address(new MSpokeYieldFeeHarness());

        vm.expectRevert(IMSpokeYieldFee.ZeroRateOracle.selector);
        MSpokeYieldFeeHarness(
            UnsafeUpgrades.deployUUPSProxy(
                implementation,
                abi.encodeWithSelector(
                    MSpokeYieldFeeHarness.initialize.selector,
                    "MSpokeYieldFee",
                    "MSYF",
                    address(mToken),
                    address(swapFacility),
                    YIELD_FEE_RATE,
                    feeRecipient,
                    admin,
                    yieldFeeManager,
                    claimRecipientManager,
                    address(0)
                )
            )
        );
    }

    /* ============ _currentBlockTimestamp ============ */

    function test_currentBlockTimestamp() external {
        uint40 timestamp = uint40(22470340);

        vm.mockCall(
            address(mToken),
            abi.encodeWithSelector(IContinuousIndexing.latestUpdateTimestamp.selector),
            abi.encode(timestamp)
        );

        assertEq(mYieldFee.currentBlockTimestamp(), timestamp);
    }

    /* ============ _currentEarnerRate ============ */

    function test_currentEarnerRate() external {
        uint32 earnerRate = 415;

        vm.mockCall(
            address(rateOracle),
            abi.encodeWithSelector(IRateOracle.earnerRate.selector),
            abi.encode(earnerRate)
        );

        assertEq(mYieldFee.currentEarnerRate(), earnerRate);
    }
}
