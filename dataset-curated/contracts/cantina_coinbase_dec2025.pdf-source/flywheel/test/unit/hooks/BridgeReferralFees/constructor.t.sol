// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {BridgeReferralFees} from "../../../../src/hooks/BridgeReferralFees.sol";
import {BridgeReferralFeesTest} from "../../../lib/BridgeReferralFeesTest.sol";

contract ConstructorTest is BridgeReferralFeesTest {
    /// @dev Sets flywheel address correctly
    function test_setsFlywheel() public {
        assertEq(address(bridgeReferralFees.FLYWHEEL()), address(flywheel));
    }

    /// @dev Sets builderCodes address correctly
    function test_setsBuilderCodes() public {
        assertEq(address(bridgeReferralFees.BUILDER_CODES()), address(builderCodes));
    }

    /// @dev Sets uriPrefix correctly
    function test_setsUriPrefix() public {
        assertEq(bridgeReferralFees.uriPrefix(), CAMPAIGN_URI);
    }

    /// @dev Sets maxFeeBasisPoints correctly
    function test_setsMaxFeeBasisPoints() public {
        assertEq(bridgeReferralFees.MAX_FEE_BASIS_POINTS(), MAX_FEE_BASIS_POINTS);
    }

    /// @dev Sets metadataManager correctly
    function test_setsMetadataManager() public {
        assertEq(address(bridgeReferralFees.METADATA_MANAGER()), address(owner));
    }

    // ========================================
    // NEW TESTS - UINT8 MAX_FEE_BASIS_POINTS
    // ========================================

    /// @dev Verifies maxFeeBasisPoints is stored as uint8 type
    function test_success_maxFeeBasisPoints_uint8Type() public {
        assertEq(bridgeReferralFees.MAX_FEE_BASIS_POINTS(), MAX_FEE_BASIS_POINTS);
        assertLe(bridgeReferralFees.MAX_FEE_BASIS_POINTS(), type(uint8).max);
    }

    /// @dev Verifies maxFeeBasisPoints respects uint8 max value (255)
    function test_edge_maxFeeBasisPoints_uint8Boundary() public {
        uint8 maxUint8Value = type(uint8).max;
        BridgeReferralFees testHook =
            new BridgeReferralFees(address(flywheel), address(builderCodes), maxUint8Value, owner, CAMPAIGN_URI);
        assertEq(testHook.MAX_FEE_BASIS_POINTS(), maxUint8Value);
        assertEq(testHook.MAX_FEE_BASIS_POINTS(), 255);
    }
}
