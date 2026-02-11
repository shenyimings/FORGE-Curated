// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.29;

import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

import { ControllerTest } from "./Controller.t.sol";

using Math for uint256;

abstract contract Controller_VaultLimitsLogic_Test is ControllerTest {
    uint256 errDelta = 0.001e18; // 0.1%
    address thisVault = makeAddr("thisVault");
    address otherVault1 = makeAddr("otherVault1");
    address otherVault2 = makeAddr("otherVault2");

    function _mockVault(
        address vault,
        uint256 normalizedAssets,
        uint224 maxCapacity,
        uint16 minProportionality,
        uint16 maxProportionality
    )
        internal
    {
        _mockVault(
            vault,
            makeAddr("asset"),
            normalizedAssets,
            makeAddr("feed"),
            1e8,
            8,
            maxCapacity,
            minProportionality,
            maxProportionality
        );
    }
}

contract Controller_VaultLimitsLogic_MaxDeposit_Test is Controller_VaultLimitsLogic_Test {
    // One vault
    function test_shouldPanic_whenVaultNotInContext() public {
        _mockVault(thisVault, 200e18, 0, 0, MAX_BPS);

        vm.expectRevert();
        controller.exposed_maxDepositLimit(makeAddr("not-a-vault"));
    }

    function test_shouldReturnMax_whenNoCapacity_whenNoProportionality_whenOneVault() public {
        _mockVault(thisVault, 100e18, 0, 0, MAX_BPS);

        assertEq(controller.exposed_maxDepositLimit(thisVault), type(uint256).max);
    }

    function testFuzz_shouldReturnCapacity_whenCapacity_whenNoProportionality_whenOneVault(
        uint256 capacity,
        uint256 vaultAssets
    )
        public
    {
        vaultAssets = bound(vaultAssets, 0, 100_000e18);
        capacity = bound(capacity, vaultAssets + 1, type(uint224).max);
        // forge-lint: disable-next-line(unsafe-typecast)
        _mockVault(thisVault, vaultAssets, uint224(capacity), 0, MAX_BPS);

        assertEq(controller.exposed_maxDepositLimit(thisVault), capacity - vaultAssets);
    }

    function testFuzz_shouldReturnZero_whenNoMaxCapacity_whenProportionality_whenOneVault(uint16 limit) public {
        limit = uint16(bound(limit, 0, MAX_BPS - 1));
        _mockVault(thisVault, 100e18, 0, 0, limit);

        assertEq(controller.exposed_maxDepositLimit(thisVault), 0);
    }

    // Multiple vaults
    function test_shouldReturnMax_whenNoCapacity_whenNoProportionality_whenMultipleVaults() public {
        _mockVault(thisVault, 100e18, 0, 0, MAX_BPS);
        _mockVault(otherVault1, 200e18, 0, 0, MAX_BPS);
        _mockVault(otherVault2, 300e18, 0, 0, MAX_BPS);

        assertEq(controller.exposed_maxDepositLimit(thisVault), type(uint256).max);
    }

    function testFuzz_shouldReturnCapacity_whenCapacity_whenNoProportionality_whenMultipleVaults(
        uint256 capacity,
        uint256 vaultAssets
    )
        public
    {
        vaultAssets = bound(vaultAssets, 0, 100_000e18);
        capacity = bound(capacity, vaultAssets + 1, type(uint224).max);
        // casting to 'uint256' is safe because 'capacity' is guaranteed to be less than or equal to 'type(uint224).max'
        // forge-lint: disable-next-line(unsafe-typecast)
        _mockVault(thisVault, vaultAssets, uint224(capacity), 0, MAX_BPS);
        _mockVault(otherVault1, 200e18, 0, 0, MAX_BPS);
        _mockVault(otherVault2, 300e18, 0, 0, MAX_BPS);

        assertEq(controller.exposed_maxDepositLimit(thisVault), capacity - vaultAssets);
    }

    function test_shouldReturnLimit_whenNoCapacity_whenThisMaxProportionality_whenMultipleVaults() public {
        _mockVault(thisVault, 100e18, 0, 0, 5000);
        _mockVault(otherVault1, 200e18, 0, 0, MAX_BPS);
        _mockVault(otherVault2, 300e18, 0, 0, MAX_BPS);

        assertEq(controller.exposed_maxDepositLimit(thisVault), 400e18);
    }

    function test_shouldReturnLimit_whenNoCapacity_whenOtherMinProportionality_whenMultipleVaults() public {
        _mockVault(thisVault, 100e18, 0, 0, MAX_BPS);
        _mockVault(otherVault1, 200e18, 0, 2000, MAX_BPS);
        _mockVault(otherVault2, 300e18, 0, 0, MAX_BPS);

        assertEq(controller.exposed_maxDepositLimit(thisVault), 400e18);
    }

    function test_shouldReturnMinLimit_whenAllLimitsSet_whenMultipleVaults() public {
        _mockVault(thisVault, 100e18, 150e18, 0, 5000);
        _mockVault(otherVault1, 200e18, 0, 2000, MAX_BPS);
        _mockVault(otherVault2, 300e18, 0, 0, MAX_BPS);

        // By capacity: 50
        // By this max proportionality: 400
        // By other min proportionality: 400
        // => min(50, 400, 400) = 50
        assertEq(controller.exposed_maxDepositLimit(thisVault), 50e18);

        controller.workaround_setVaultSettings(thisVault, 600e18, 0, 5000);
        controller.workaround_setVaultSettings(otherVault1, 0, 2000, MAX_BPS);
        controller.workaround_setVaultSettings(otherVault2, 0, 0, MAX_BPS);

        // By capacity: 500
        // By this max proportionality: 400
        // By other min proportionality: 400
        // => min(500, 400, 400) = 400
        assertEq(controller.exposed_maxDepositLimit(thisVault), 400e18);
    }

    function test_shouldIgnoreThisMinProportionality() public {
        _mockVault(thisVault, 100e18, 0, MAX_BPS, MAX_BPS);
        _mockVault(otherVault1, 200e18, 0, 0, MAX_BPS);
        _mockVault(otherVault2, 300e18, 0, 0, MAX_BPS);

        assertEq(controller.exposed_maxDepositLimit(thisVault), type(uint256).max);
    }

    function test_shouldIgnoreOtherMaxProportionality() public {
        _mockVault(thisVault, 100e18, 0, 0, MAX_BPS);
        _mockVault(otherVault1, 200e18, 0, 0, 0);
        _mockVault(otherVault2, 300e18, 0, 0, 0);

        assertEq(controller.exposed_maxDepositLimit(thisVault), type(uint256).max);
    }

    function testFuzz_shouldNotRevertWithAnyValidInputs(
        uint16 thisMaxProportionality,
        uint16 otherMinProportionality
    )
        public
    {
        thisMaxProportionality = uint16(bound(thisMaxProportionality, 0, MAX_BPS));
        otherMinProportionality = uint16(bound(otherMinProportionality, 0, MAX_BPS));
        _mockVault(thisVault, 100e18, 0, 0, thisMaxProportionality);
        _mockVault(otherVault1, 200e18, 0, 0, MAX_BPS);
        _mockVault(otherVault2, 300e18, 0, otherMinProportionality, MAX_BPS);

        controller.exposed_maxDepositLimit(thisVault);
    }
}

contract Controller_VaultLimitsLogic_MaxWithdraw_Test is Controller_VaultLimitsLogic_Test {
    // One vault
    function test_shouldPanic_VaultNotInContext() public {
        _mockVault(thisVault, 200e18, 0, 0, MAX_BPS);

        vm.expectRevert();
        controller.exposed_maxWithdrawLimit(makeAddr("not-a-vault"));
    }

    function testFuzz_shouldReturnMax_whenOneVault(uint16 limit) public {
        limit = uint16(bound(limit, 0, MAX_BPS));
        _mockVault(thisVault, 200e18, 0, limit, MAX_BPS);

        assertEq(controller.exposed_maxWithdrawLimit(thisVault), 200e18);
    }

    // Multiple vaults
    function test_shouldReturnMax_whenNoProportionality_whenMultipleVaults() public {
        _mockVault(thisVault, 200e18, 0, 0, MAX_BPS);
        _mockVault(otherVault1, 200e18, 0, 0, MAX_BPS);
        _mockVault(otherVault2, 300e18, 0, 0, MAX_BPS);

        assertEq(controller.exposed_maxWithdrawLimit(thisVault), 200e18);
    }

    function test_shouldReturnLimit_whenThisMinProportionality_whenMultipleVaults() public {
        _mockVault(thisVault, 200e18, 0, 2000, MAX_BPS);
        _mockVault(otherVault1, 200e18, 0, 0, MAX_BPS);
        _mockVault(otherVault2, 400e18, 0, 0, MAX_BPS);

        assertEq(controller.exposed_maxWithdrawLimit(thisVault), 50e18);
    }

    function test_shouldReturnLimit_whenOtherMaxProportionality_whenMultipleVaults() public {
        _mockVault(thisVault, 200e18, 0, 0, MAX_BPS);
        _mockVault(otherVault1, 200e18, 0, 0, MAX_BPS);
        _mockVault(otherVault2, 200e18, 0, 0, 4000);

        assertEq(controller.exposed_maxWithdrawLimit(thisVault), 100e18);
    }

    function test_shouldReturnMinLimit_whenAllLimitsSet_whenMultipleVaults() public {
        _mockVault(thisVault, 200e18, 0, 2000, MAX_BPS);
        _mockVault(otherVault1, 200e18, 0, 0, MAX_BPS);
        _mockVault(otherVault2, 400e18, 0, 0, 8000);

        // By capacity: 200
        // By this min proportionality: 50
        // By other max proportionality: 300
        // => min(200, 50, 300) = 50
        assertEq(controller.exposed_maxWithdrawLimit(thisVault), 50e18);

        controller.workaround_setVaultSettings(thisVault, 0, 0, MAX_BPS);
        controller.workaround_setVaultSettings(otherVault1, 0, 0, MAX_BPS);
        controller.workaround_setVaultSettings(otherVault2, 0, 0, 8000);

        // By capacity: 200
        // By this min proportionality: 200
        // By other max proportionality: 300
        // => min(200, 200, 300) = 200
        assertEq(controller.exposed_maxWithdrawLimit(thisVault), 200e18);
    }

    function test_shouldIgnoreThisMaxProportionality() public {
        _mockVault(thisVault, 200e18, 0, 0, 0);
        _mockVault(otherVault1, 200e18, 0, 0, MAX_BPS);
        _mockVault(otherVault2, 400e18, 0, 0, MAX_BPS);

        assertEq(controller.exposed_maxWithdrawLimit(thisVault), 200e18);
    }

    function test_shouldIgnoreOtherMaxProportionality() public {
        _mockVault(thisVault, 200e18, 0, 0, MAX_BPS);
        _mockVault(otherVault1, 200e18, 0, MAX_BPS, MAX_BPS);
        _mockVault(otherVault2, 400e18, 0, MAX_BPS, MAX_BPS);

        assertEq(controller.exposed_maxWithdrawLimit(thisVault), 200e18);
    }

    function testFuzz_shouldNotReturnMoreThanVaultAssets(
        uint16 thisMinProportionality,
        uint16 otherMaxProportionality
    )
        public
    {
        thisMinProportionality = uint16(bound(thisMinProportionality, 0, MAX_BPS));
        otherMaxProportionality = uint16(bound(otherMaxProportionality, 0, MAX_BPS));
        _mockVault(thisVault, 200e18, 0, thisMinProportionality, MAX_BPS);
        _mockVault(otherVault1, 200e18, 0, 0, MAX_BPS);
        _mockVault(otherVault2, 400e18, 0, 0, otherMaxProportionality);

        assertLe(controller.exposed_maxWithdrawLimit(thisVault), 200e18);
    }
}

contract Controller_VaultLimitsLogic_MaxDepositByThisVaultMaxCapacity_Test is Controller_VaultLimitsLogic_Test {
    uint256 capacity = 1000e18;

    function testFuzz_shouldReturnMax_whenVaultHasNoMaxCapacity(uint256 vaultAssets) public view {
        assertEq(controller.exposed_maxDepositByThisVaultMaxCapacity(0, vaultAssets), type(uint256).max);
    }

    function testFuzz_shouldReturnZero_whenVaultAtMaxCapacity(uint256 vaultAssets) public view {
        vaultAssets = bound(vaultAssets, capacity, type(uint256).max);
        assertEq(controller.exposed_maxDepositByThisVaultMaxCapacity(capacity, vaultAssets), 0);
    }

    function testFuzz_shouldReturnMaxDeposit_whenVaultBelowMaxCapacity(uint256 vaultAssets) public view {
        vaultAssets = bound(vaultAssets, 0, capacity);
        assertEq(controller.exposed_maxDepositByThisVaultMaxCapacity(capacity, vaultAssets), capacity - vaultAssets);
    }
}

contract Controller_VaultLimitsLogic_MaxDepositByThisVaultMaxProportionality_Test is Controller_VaultLimitsLogic_Test {
    uint256 vaultAssets = 10_000e18;
    uint256 totalAssets = 20_000e18;

    function test_shouldHandleEdgeCases() public view {
        // Limit
        assertEq(
            controller.exposed_maxDepositByThisVaultMaxProportionality(MAX_BPS, vaultAssets, totalAssets),
            type(uint256).max
        );
        assertEq(controller.exposed_maxDepositByThisVaultMaxProportionality(0, vaultAssets, totalAssets), 0);
        // Assets
        assertEq(controller.exposed_maxDepositByThisVaultMaxProportionality(5000, 0, 0), 0);
        assertEq(controller.exposed_maxDepositByThisVaultMaxProportionality(5000, vaultAssets, vaultAssets), 0);
    }

    function test_shouldReturnZero_whenCurrentStateAboveOrEqualToLimit() public view {
        assertEq(controller.exposed_maxDepositByThisVaultMaxProportionality(5000, vaultAssets, totalAssets), 0);
        assertEq(controller.exposed_maxDepositByThisVaultMaxProportionality(4000, vaultAssets, totalAssets), 0);
        assertEq(controller.exposed_maxDepositByThisVaultMaxProportionality(1000, vaultAssets, totalAssets), 0);
    }

    function test_shouldReturnMaxDeposit_whenCurrentStateBelowLimit() public view {
        assertEq(controller.exposed_maxDepositByThisVaultMaxProportionality(6000, vaultAssets, totalAssets), 5000e18);
        assertEq(controller.exposed_maxDepositByThisVaultMaxProportionality(9000, vaultAssets, totalAssets), 80_000e18);
    }
}

contract Controller_VaultLimitsLogic_MaxDepositByOtherVaultMinProportionality_Test is Controller_VaultLimitsLogic_Test {
    uint256 vaultAssets = 10_000e18;
    uint256 totalAssets = 20_000e18;

    function test_shouldHandleEdgeCases() public view {
        // Limit
        assertEq(
            controller.exposed_maxDepositByOtherVaultMinProportionality(0, vaultAssets, totalAssets), type(uint256).max
        );
        assertEq(controller.exposed_maxDepositByOtherVaultMinProportionality(MAX_BPS, vaultAssets, totalAssets), 0);
        // Assets
        assertEq(controller.exposed_maxDepositByOtherVaultMinProportionality(5000, 0, totalAssets), 0);
    }

    function test_shouldReturnMaxDeposit_whenCurrentStateBelowToLimit() public view {
        assertEq(controller.exposed_maxDepositByOtherVaultMinProportionality(4000, vaultAssets, totalAssets), 5000e18);
        assertEq(controller.exposed_maxDepositByOtherVaultMinProportionality(2000, vaultAssets, totalAssets), 30_000e18);
        assertEq(controller.exposed_maxDepositByOtherVaultMinProportionality(500, vaultAssets, totalAssets), 180_000e18);
    }

    function test_shouldReturnZero_whenCurrentStateAboveOrEqualLimit() public view {
        assertEq(controller.exposed_maxDepositByOtherVaultMinProportionality(5000, vaultAssets, totalAssets), 0);
        assertEq(controller.exposed_maxDepositByOtherVaultMinProportionality(7000, vaultAssets, totalAssets), 0);
        assertEq(controller.exposed_maxDepositByOtherVaultMinProportionality(9000, vaultAssets, totalAssets), 0);
    }
}

contract Controller_VaultLimitsLogic_MaxWithdrawByThisVaultMinProportionality_Test is Controller_VaultLimitsLogic_Test {
    uint256 vaultAssets = 10_000e18;
    uint256 totalAssets = 20_000e18;

    function test_shouldHandleEdgeCases() public view {
        // Limit
        assertEq(controller.exposed_maxWithdrawByThisVaultMinProportionality(MAX_BPS, vaultAssets, totalAssets), 0);
        assertEq(
            controller.exposed_maxWithdrawByThisVaultMinProportionality(MAX_BPS, vaultAssets, vaultAssets),
            totalAssets - vaultAssets
        );
        assertEq(controller.exposed_maxWithdrawByThisVaultMinProportionality(0, vaultAssets, totalAssets), vaultAssets);
        // Assets
        assertEq(controller.exposed_maxWithdrawByThisVaultMinProportionality(5000, 0, totalAssets), 0);
        assertEq(
            controller.exposed_maxWithdrawByThisVaultMinProportionality(5000, vaultAssets, vaultAssets), vaultAssets
        );
    }

    function test_shouldReturnMaxWithdraw_whenCurrentStateBelowToLimit() public view {
        assertApproxEqRel(
            controller.exposed_maxWithdrawByThisVaultMinProportionality(3750, vaultAssets, totalAssets),
            4000e18,
            errDelta
        );
        assertApproxEqRel(
            controller.exposed_maxWithdrawByThisVaultMinProportionality(2308, vaultAssets, totalAssets),
            7000e18,
            errDelta
        );
        assertApproxEqRel(
            controller.exposed_maxWithdrawByThisVaultMinProportionality(909, vaultAssets, totalAssets),
            9000e18,
            errDelta
        );
    }

    function test_shouldReturnZero_whenCurrentStateAboveOrEqualLimit() public view {
        assertEq(controller.exposed_maxWithdrawByThisVaultMinProportionality(5000, vaultAssets, totalAssets), 0);
        assertEq(controller.exposed_maxWithdrawByThisVaultMinProportionality(7000, vaultAssets, totalAssets), 0);
        assertEq(controller.exposed_maxWithdrawByThisVaultMinProportionality(9000, vaultAssets, totalAssets), 0);
    }
}

contract Controller_VaultLimitsLogic_MaxWithdrawByOtherVaultMaxProportionality_Test is
    Controller_VaultLimitsLogic_Test
{
    uint256 vaultAssets = 10_000e18;
    uint256 totalAssets = 20_000e18;

    function test_shouldHandleEdgeCases() public view {
        // Limit
        assertEq(
            controller.exposed_maxWithdrawByOtherVaultMaxProportionality(MAX_BPS, vaultAssets, totalAssets),
            totalAssets - vaultAssets
        );
        assertEq(controller.exposed_maxWithdrawByOtherVaultMaxProportionality(0, vaultAssets, totalAssets), 0);
        // Assets
        assertEq(controller.exposed_maxWithdrawByOtherVaultMaxProportionality(5000, 0, totalAssets), totalAssets);
    }

    function test_shouldReturnZero_whenCurrentStateBelowOrEqualToLimit() public view {
        assertEq(controller.exposed_maxWithdrawByOtherVaultMaxProportionality(4000, vaultAssets, totalAssets), 0);
        assertEq(controller.exposed_maxWithdrawByOtherVaultMaxProportionality(2000, vaultAssets, totalAssets), 0);
        assertEq(controller.exposed_maxWithdrawByOtherVaultMaxProportionality(500, vaultAssets, totalAssets), 0);
    }

    function test_shouldReturnMaxWithdraw_whenCurrentStateAboveLimit() public view {
        assertApproxEqRel(
            controller.exposed_maxWithdrawByOtherVaultMaxProportionality(8000, vaultAssets, totalAssets),
            7500e18,
            errDelta
        );
        assertApproxEqRel(
            controller.exposed_maxWithdrawByOtherVaultMaxProportionality(6000, vaultAssets, totalAssets),
            3333e18,
            errDelta
        );
        assertApproxEqRel(
            controller.exposed_maxWithdrawByOtherVaultMaxProportionality(9700, vaultAssets, totalAssets),
            9690e18,
            errDelta
        );
        assertApproxEqRel(
            controller.exposed_maxWithdrawByOtherVaultMaxProportionality(5001, vaultAssets, totalAssets),
            3.9992e18,
            errDelta
        );
    }
}

contract Controller_VaultLimitsLogic_VaultAssetsDeltaToHitProportionality_Test is Controller_VaultLimitsLogic_Test {
    uint256 vaultAssets = 10_000e18;
    uint256 totalAssets = 20_000e18;

    function test_shouldPanic_whenProportionalityLimitOutOfBounds() public {
        vm.expectRevert();
        controller.exposed_vaultAssetsDeltaToHitProportionality(10_000, vaultAssets, totalAssets);

        vm.expectRevert();
        controller.exposed_vaultAssetsDeltaToHitProportionality(0, vaultAssets, totalAssets);
    }

    function test_shouldPanic_whenVaultAssetsGreaterThanOrEqualToTotalAssets() public {
        vm.expectRevert();
        controller.exposed_vaultAssetsDeltaToHitProportionality(5000, totalAssets, totalAssets);
    }

    function test_shouldPanic_whenTotalAssetsZero() public {
        vm.expectRevert();
        controller.exposed_vaultAssetsDeltaToHitProportionality(5000, 0, 0);
    }

    function test_shouldReturnPositiveChange_whenProportionalityLimitAboveCurrentProportionality() public view {
        assertApproxEqRel(
            controller.exposed_vaultAssetsDeltaToHitProportionality(6000, vaultAssets, totalAssets), 5000e18, errDelta
        );
        assertApproxEqRel(
            controller.exposed_vaultAssetsDeltaToHitProportionality(7058, vaultAssets, totalAssets), 14_000e18, errDelta
        );
        assertApproxEqRel(
            controller.exposed_vaultAssetsDeltaToHitProportionality(9000, vaultAssets, totalAssets), 80_000e18, errDelta
        );
    }

    function test_shouldReturnNegativeChange_whenProportionalityLimitBellowCurrentProportionality() public view {
        assertApproxEqRel(
            controller.exposed_vaultAssetsDeltaToHitProportionality(3750, vaultAssets, totalAssets), -4000e18, errDelta
        );
        assertApproxEqRel(
            controller.exposed_vaultAssetsDeltaToHitProportionality(2308, vaultAssets, totalAssets), -7000e18, errDelta
        );
        assertApproxEqRel(
            controller.exposed_vaultAssetsDeltaToHitProportionality(909, vaultAssets, totalAssets), -9000e18, errDelta
        );
    }

    function testFuzz_shouldReturnCorrectChange(
        uint16 limit,
        uint256 _vaultAssets,
        uint256 _totalAssets
    )
        public
        view
    {
        limit = uint16(bound(limit, 1, 9999));
        _totalAssets = bound(_totalAssets, 1, type(uint256).max / 1e10);
        _vaultAssets = bound(_vaultAssets, 0, _totalAssets - 1);

        int256 change = controller.exposed_vaultAssetsDeltaToHitProportionality(limit, _vaultAssets, _totalAssets);

        // casting to 'uint256' is safe because 'change' sign is checked
        // forge-lint: disable-next-line(unsafe-typecast)
        _vaultAssets = change > 0 ? _vaultAssets + uint256(change) : _vaultAssets - uint256(-change);
        // casting to 'uint256' is safe because 'change' sign is checked
        // forge-lint: disable-next-line(unsafe-typecast)
        _totalAssets = change > 0 ? _totalAssets + uint256(change) : _totalAssets - uint256(-change);
        if (_vaultAssets < 1e4) {
            assertApproxEqAbs(_totalAssets.mulDiv(limit, MAX_BPS), _vaultAssets, 1);
        } else {
            assertApproxEqRel(_totalAssets.mulDiv(limit, MAX_BPS), _vaultAssets, errDelta);
        }
    }
}

contract Controller_VaultLimitsLogic_TotalAssetsDeltaToHitProportionality_Test is Controller_VaultLimitsLogic_Test {
    uint256 vaultAssets = 10_000e18;
    uint256 totalAssets = 20_000e18;

    function test_shouldPanic_whenProportionalityLimitOutOfBounds() public {
        vm.expectRevert();
        controller.exposed_totalAssetsDeltaToHitProportionality(10_000, vaultAssets, totalAssets);

        vm.expectRevert();
        controller.exposed_totalAssetsDeltaToHitProportionality(0, vaultAssets, totalAssets);
    }

    function test_shouldPanic_whenVaultAssetsGreaterThanTotalAssets() public {
        vm.expectRevert();
        controller.exposed_totalAssetsDeltaToHitProportionality(5000, totalAssets + 1, totalAssets);
    }

    function test_shouldPanic_whenTotalAssetsZero() public {
        vm.expectRevert();
        controller.exposed_totalAssetsDeltaToHitProportionality(5000, 0, 1);
    }

    function test_shouldReturnNegativeChange_whenProportionalityLimitAboveCurrentProportionality() public view {
        assertApproxEqRel(
            controller.exposed_totalAssetsDeltaToHitProportionality(8000, vaultAssets, totalAssets), -7500e18, errDelta
        );
        assertApproxEqRel(
            controller.exposed_totalAssetsDeltaToHitProportionality(6000, vaultAssets, totalAssets), -3333e18, errDelta
        );
        assertApproxEqRel(
            controller.exposed_totalAssetsDeltaToHitProportionality(9700, vaultAssets, totalAssets), -9690e18, errDelta
        );
        assertApproxEqRel(
            controller.exposed_totalAssetsDeltaToHitProportionality(5001, vaultAssets, totalAssets),
            -3.9992e18,
            errDelta
        );
    }

    function test_shouldReturnPositiveChange_whenProportionalityLimitBellowCurrentProportionality() public view {
        assertApproxEqRel(
            controller.exposed_totalAssetsDeltaToHitProportionality(4000, vaultAssets, totalAssets), 5000e18, errDelta
        );
        assertApproxEqRel(
            controller.exposed_totalAssetsDeltaToHitProportionality(3400, vaultAssets, totalAssets), 9411.7e18, errDelta
        );
        assertApproxEqRel(
            controller.exposed_totalAssetsDeltaToHitProportionality(2000, vaultAssets, totalAssets), 30_000e18, errDelta
        );
        assertApproxEqRel(
            controller.exposed_totalAssetsDeltaToHitProportionality(500, vaultAssets, totalAssets), 180_000e18, errDelta
        );
    }

    function testFuzz_shouldReturnCorrectChange(
        uint16 limit,
        uint256 _vaultAssets,
        uint256 _totalAssets
    )
        public
        view
    {
        limit = uint16(bound(limit, 1, 9999));
        _totalAssets = bound(_totalAssets, 1, type(uint256).max / 1e10);
        _vaultAssets = bound(_vaultAssets, 1, _totalAssets);

        int256 change = controller.exposed_totalAssetsDeltaToHitProportionality(limit, _vaultAssets, _totalAssets);

        // casting to 'uint256' is safe because 'change' sign is checked
        // forge-lint: disable-next-line(unsafe-typecast)
        _totalAssets = change > 0 ? _totalAssets + uint256(change) : _totalAssets - uint256(-change);
        if (_vaultAssets < 1e4) {
            assertApproxEqAbs(_totalAssets.mulDiv(limit, MAX_BPS), _vaultAssets, 1);
        } else {
            assertApproxEqRel(_totalAssets.mulDiv(limit, MAX_BPS), _vaultAssets, errDelta);
        }
    }
}
