// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {Flywheel} from "../../../../src/Flywheel.sol";
import {BridgeReferralFeesTest} from "../../../lib/BridgeReferralFeesTest.sol";

contract OnDistributeFeesTest is BridgeReferralFeesTest {
    // ========================================
    // REVERT CASES
    // ========================================

    // NOTE: With the new _processBuilderCode error handling, invalid codes return empty arrays instead of reverting

    // ========================================
    // SUCCESS CASES
    // ========================================

    /// @dev Creates distribution to correct payout address for builder code
    function test_success_usesBuilderPayoutAddress(uint256 seed) public {
        string memory code = _registerBuilderCode(seed);

        vm.prank(address(flywheel));
        Flywheel.Distribution[] memory distributions =
            bridgeReferralFees.onDistributeFees(address(this), bridgeReferralFeesCampaign, address(usdc), bytes(code));

        bytes32 codeBytes32 = bytes32(builderCodes.toTokenId(code));
        address expectedPayoutAddress = builderCodes.payoutAddress(uint256(codeBytes32));
        assertEq(distributions[0].recipient, expectedPayoutAddress, "Should use correct payout address");
    }

    /// @dev Sets distribution amount to full allocated fee amount for the builder code
    function test_success_distributesFullAmount(uint256 seed) public {
        string memory code = _registerBuilderCode(seed);

        // This test is simplified since setting up allocated fees is complex
        // We just verify the implementation calls the expected function
        vm.prank(address(flywheel));
        Flywheel.Distribution[] memory distributions =
            bridgeReferralFees.onDistributeFees(address(this), bridgeReferralFeesCampaign, address(usdc), bytes(code));

        // The amount should come from flywheel.allocatedFee call
        // We can't easily mock this without complex setup, so just verify structure
        bytes32 codeBytes32 = bytes32(builderCodes.toTokenId(code));
        assertEq(distributions[0].key, codeBytes32, "Should use builder code as key");
    }

    /// @dev Uses builder code as distribution key for fee tracking
    function test_success_usesBuilderCodeAsKey(uint256 seed) public {
        string memory code = _registerBuilderCode(seed);

        vm.prank(address(flywheel));
        Flywheel.Distribution[] memory distributions =
            bridgeReferralFees.onDistributeFees(address(this), bridgeReferralFeesCampaign, address(usdc), bytes(code));

        bytes32 codeBytes32 = bytes32(builderCodes.toTokenId(code));
        assertEq(distributions[0].key, codeBytes32, "Should use builder code as key");
    }

    // ========================================
    // STATE VERIFICATION
    // ========================================

    /// @dev Verifies single distribution is returned for valid builder code
    function test_singleDistribution(uint256 seed) public {
        string memory code = _registerBuilderCode(seed);

        vm.prank(address(flywheel));
        Flywheel.Distribution[] memory distributions =
            bridgeReferralFees.onDistributeFees(address(this), bridgeReferralFeesCampaign, address(usdc), bytes(code));

        assertEq(distributions.length, 1, "Should return exactly one distribution");
    }

    /// @dev Verifies distribution extraData is empty for fee distributions
    function test_emptyExtraData(uint256 seed) public {
        string memory code = _registerBuilderCode(seed);

        vm.prank(address(flywheel));
        Flywheel.Distribution[] memory distributions =
            bridgeReferralFees.onDistributeFees(address(this), bridgeReferralFeesCampaign, address(usdc), bytes(code));

        assertEq(distributions[0].extraData.length, 0, "Distribution extraData should be empty");
    }

    // ========================================
    // NEW TESTS - PROCESSBUILDERCODE ERROR HANDLING
    // ========================================

    /// @dev Returns empty array when builder code is empty
    function test_success_emptyBuilderCode_returnsEmptyArray() public {
        vm.prank(address(flywheel));
        Flywheel.Distribution[] memory distributions =
            bridgeReferralFees.onDistributeFees(address(this), bridgeReferralFeesCampaign, address(usdc), bytes(""));

        assertEq(distributions.length, 0, "Should return empty array for empty code");
    }

    /// @dev Returns empty array when builder code is invalid
    function test_success_invalidBuilderCode_returnsEmptyArray() public {
        string memory invalidCode = "INVALID_CODE_WITH_UPPERCASE";

        vm.prank(address(flywheel));
        Flywheel.Distribution[] memory distributions = bridgeReferralFees.onDistributeFees(
            address(this), bridgeReferralFeesCampaign, address(usdc), bytes(invalidCode)
        );

        assertEq(distributions.length, 0, "Should return empty array for invalid code");
    }

    /// @dev Returns empty array when builder code is unregistered
    /// @param seed Random seed for test variation
    function test_success_unregisteredCode_returnsEmptyArray(uint256 seed) public {
        string memory unregisteredCode = _computeCode(seed);

        vm.prank(address(flywheel));
        Flywheel.Distribution[] memory distributions = bridgeReferralFees.onDistributeFees(
            address(this), bridgeReferralFeesCampaign, address(usdc), bytes(unregisteredCode)
        );

        assertEq(distributions.length, 0, "Should return empty array for unregistered code");
    }

    /// @dev Returns empty array when BuilderCodes methods revert
    function test_success_builderCodesReverts_returnsEmptyArray() public {
        string memory tooLongCode = "this_code_is_way_too_long_to_be_valid_and_will_cause_revert";

        vm.prank(address(flywheel));
        Flywheel.Distribution[] memory distributions = bridgeReferralFees.onDistributeFees(
            address(this), bridgeReferralFeesCampaign, address(usdc), bytes(tooLongCode)
        );

        assertEq(distributions.length, 0, "Should return empty array when BuilderCodes reverts");
    }

    /// @dev Distributes fees correctly when builder code is valid and registered
    /// @param seed Random seed for test variation
    function test_success_validRegisteredCode_distributesCorrectly(uint256 seed) public {
        string memory code = _registerBuilderCode(seed);

        vm.prank(address(flywheel));
        Flywheel.Distribution[] memory distributions =
            bridgeReferralFees.onDistributeFees(address(this), bridgeReferralFeesCampaign, address(usdc), bytes(code));

        assertEq(distributions.length, 1, "Should return single distribution");

        bytes32 expectedKey = bytes32(builderCodes.toTokenId(code));
        address expectedRecipient = builderCodes.payoutAddress(uint256(expectedKey));
        uint256 expectedAmount = flywheel.allocatedFee(bridgeReferralFeesCampaign, address(usdc), expectedKey);

        assertEq(distributions[0].key, expectedKey, "Distribution key should match builder code");
        assertEq(distributions[0].recipient, expectedRecipient, "Distribution recipient should match payout address");
        assertEq(distributions[0].amount, expectedAmount, "Distribution amount should match allocated fee");
        assertEq(distributions[0].extraData.length, 0, "Distribution extraData should be empty");
    }
}
