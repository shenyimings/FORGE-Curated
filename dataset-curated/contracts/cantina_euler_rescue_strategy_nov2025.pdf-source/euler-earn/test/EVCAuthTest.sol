// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.26;

import {IntegrationTest, CAP, ErrorsLib, IERC4626, MarketAllocation, Ownable} from "./helpers/IntegrationTest.sol";
import {EVCUtil} from "../lib/ethereum-vault-connector/src/utils/EVCUtil.sol";

import "forge-std/Test.sol";

contract EVCAuthTest is IntegrationTest {
    address internal OPERATOR;

    function setUp() public virtual override {
        super.setUp();

        _setGuardian(GUARDIAN);

        OPERATOR = makeAddr("operator");
    }

    function testCuratorCallsThroughEVC() public {
        // fails when not curator
        vm.startPrank(SUPPLIER);
        vm.expectRevert(ErrorsLib.NotCuratorRole.selector);
        evc.call(address(vault), SUPPLIER, 0, abi.encodeCall(vault.submitCap, (allMarkets[0], CAP)));
        vm.expectRevert(ErrorsLib.NotCuratorRole.selector);
        evc.call(address(vault), SUPPLIER, 0, abi.encodeCall(vault.submitMarketRemoval, (allMarkets[0])));

        // sub-account can't call
        address subacc = address(uint160(CURATOR) ^ 1);
        vm.startPrank(CURATOR);
        vm.expectRevert(EVCUtil.NotAuthorized.selector);
        evc.call(address(vault), subacc, 0, abi.encodeCall(vault.submitCap, (allMarkets[0], CAP)));
        vm.expectRevert(EVCUtil.NotAuthorized.selector);
        evc.call(address(vault), subacc, 0, abi.encodeCall(vault.submitMarketRemoval, (allMarkets[0])));

        // operator can't call
        bytes19 prefix = evc.getAddressPrefix(CURATOR);
        vm.startPrank(CURATOR);
        evc.setOperator(prefix, OPERATOR, 1);
        vm.startPrank(OPERATOR);
        vm.expectRevert(EVCUtil.NotAuthorized.selector);
        evc.call(address(vault), CURATOR, 0, abi.encodeCall(vault.submitCap, (allMarkets[0], CAP)));
        vm.expectRevert(EVCUtil.NotAuthorized.selector);
        evc.call(address(vault), CURATOR, 0, abi.encodeCall(vault.submitMarketRemoval, (allMarkets[0])));
        vm.stopPrank();

        // account owner can call
        vm.prank(CURATOR);
        evc.call(address(vault), CURATOR, 0, abi.encodeCall(vault.submitCap, (allMarkets[0], CAP)));
        _setCap(allMarkets[0], CAP);
        _setCap(allMarkets[0], 0);
        vm.prank(CURATOR);
        evc.call(address(vault), CURATOR, 0, abi.encodeCall(vault.submitMarketRemoval, (allMarkets[0])));
    }

    function testAllocatorCallsThroughEVC() public {
        IERC4626[] memory newSupplyQueue = new IERC4626[](0);
        uint256[] memory newWithdrawQueue = new uint256[](0);
        MarketAllocation[] memory newAllocations = new MarketAllocation[](0);

        // fails when not allocator
        vm.startPrank(SUPPLIER);
        vm.expectRevert(ErrorsLib.NotAllocatorRole.selector);
        evc.call(address(vault), SUPPLIER, 0, abi.encodeCall(vault.setSupplyQueue, (newSupplyQueue)));
        vm.expectRevert(ErrorsLib.NotAllocatorRole.selector);
        evc.call(address(vault), SUPPLIER, 0, abi.encodeCall(vault.updateWithdrawQueue, (newWithdrawQueue)));
        vm.expectRevert(ErrorsLib.NotAllocatorRole.selector);
        evc.call(address(vault), SUPPLIER, 0, abi.encodeCall(vault.reallocate, (newAllocations)));

        // sub-account can't call
        address subacc = address(uint160(ALLOCATOR) ^ 1);
        vm.startPrank(ALLOCATOR);
        vm.expectRevert(EVCUtil.NotAuthorized.selector);
        evc.call(address(vault), subacc, 0, abi.encodeCall(vault.setSupplyQueue, (newSupplyQueue)));
        vm.expectRevert(EVCUtil.NotAuthorized.selector);
        evc.call(address(vault), subacc, 0, abi.encodeCall(vault.updateWithdrawQueue, (newWithdrawQueue)));
        vm.expectRevert(EVCUtil.NotAuthorized.selector);
        evc.call(address(vault), subacc, 0, abi.encodeCall(vault.reallocate, (newAllocations)));

        // operator can't call
        bytes19 prefix = evc.getAddressPrefix(ALLOCATOR);
        vm.startPrank(ALLOCATOR);
        evc.setOperator(prefix, OPERATOR, 1);
        vm.startPrank(OPERATOR);
        vm.expectRevert(EVCUtil.NotAuthorized.selector);
        evc.call(address(vault), ALLOCATOR, 0, abi.encodeCall(vault.setSupplyQueue, (newSupplyQueue)));
        vm.expectRevert(EVCUtil.NotAuthorized.selector);
        evc.call(address(vault), ALLOCATOR, 0, abi.encodeCall(vault.updateWithdrawQueue, (newWithdrawQueue)));
        vm.expectRevert(EVCUtil.NotAuthorized.selector);
        evc.call(address(vault), ALLOCATOR, 0, abi.encodeCall(vault.reallocate, (newAllocations)));

        // account owner can call
        vm.startPrank(ALLOCATOR);
        evc.call(address(vault), ALLOCATOR, 0, abi.encodeCall(vault.setSupplyQueue, (newSupplyQueue)));
        vm.expectRevert(abi.encodeWithSelector(ErrorsLib.InvalidMarketRemovalNonZeroCap.selector, (idleVault)));
        evc.call(address(vault), ALLOCATOR, 0, abi.encodeCall(vault.updateWithdrawQueue, (newWithdrawQueue)));
        evc.call(address(vault), ALLOCATOR, 0, abi.encodeCall(vault.reallocate, (newAllocations)));
    }

    function testGuardianCallsThroughEVC() public {
        // fails when not guardian
        vm.startPrank(SUPPLIER);
        vm.expectRevert(ErrorsLib.NotGuardianRole.selector);
        evc.call(address(vault), SUPPLIER, 0, abi.encodeCall(vault.revokePendingTimelock, ()));
        vm.expectRevert(ErrorsLib.NotGuardianRole.selector);
        evc.call(address(vault), SUPPLIER, 0, abi.encodeCall(vault.revokePendingGuardian, ()));
        vm.expectRevert(ErrorsLib.NotCuratorNorGuardianRole.selector);
        evc.call(address(vault), SUPPLIER, 0, abi.encodeCall(vault.revokePendingCap, (allMarkets[0])));
        vm.expectRevert(ErrorsLib.NotCuratorNorGuardianRole.selector);
        evc.call(address(vault), SUPPLIER, 0, abi.encodeCall(vault.revokePendingMarketRemoval, (allMarkets[0])));

        // sub-account can't call
        address subacc = address(uint160(GUARDIAN) ^ 1);
        vm.startPrank(GUARDIAN);
        vm.expectRevert(EVCUtil.NotAuthorized.selector);
        evc.call(address(vault), subacc, 0, abi.encodeCall(vault.revokePendingTimelock, ()));
        vm.expectRevert(EVCUtil.NotAuthorized.selector);
        evc.call(address(vault), subacc, 0, abi.encodeCall(vault.revokePendingGuardian, ()));
        vm.expectRevert(EVCUtil.NotAuthorized.selector);
        evc.call(address(vault), subacc, 0, abi.encodeCall(vault.revokePendingCap, (allMarkets[0])));
        vm.expectRevert(EVCUtil.NotAuthorized.selector);
        evc.call(address(vault), subacc, 0, abi.encodeCall(vault.revokePendingMarketRemoval, (allMarkets[0])));

        // operator can't call
        bytes19 prefix = evc.getAddressPrefix(GUARDIAN);
        vm.startPrank(GUARDIAN);
        evc.setOperator(prefix, OPERATOR, 1);
        vm.startPrank(OPERATOR);
        vm.expectRevert(EVCUtil.NotAuthorized.selector);
        evc.call(address(vault), GUARDIAN, 0, abi.encodeCall(vault.revokePendingTimelock, ()));
        vm.expectRevert(EVCUtil.NotAuthorized.selector);
        evc.call(address(vault), GUARDIAN, 0, abi.encodeCall(vault.revokePendingGuardian, ()));
        vm.expectRevert(EVCUtil.NotAuthorized.selector);
        evc.call(address(vault), GUARDIAN, 0, abi.encodeCall(vault.revokePendingCap, (allMarkets[0])));
        vm.expectRevert(EVCUtil.NotAuthorized.selector);
        evc.call(address(vault), GUARDIAN, 0, abi.encodeCall(vault.revokePendingMarketRemoval, (allMarkets[0])));

        // account owner can call
        vm.startPrank(GUARDIAN);
        evc.call(address(vault), GUARDIAN, 0, abi.encodeCall(vault.revokePendingTimelock, ()));
        evc.call(address(vault), GUARDIAN, 0, abi.encodeCall(vault.revokePendingGuardian, ()));
        evc.call(address(vault), GUARDIAN, 0, abi.encodeCall(vault.revokePendingCap, (allMarkets[0])));
        evc.call(address(vault), GUARDIAN, 0, abi.encodeCall(vault.revokePendingMarketRemoval, (allMarkets[0])));
    }

    function testOwnerCallsThroughEVC() public {
        vm.startPrank(OWNER);
        _callOwnerFunctions(OWNER);

        vm.startPrank(SUPPLIER);
        _expectRevertOwnerFunctions(
            SUPPLIER, abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, (SUPPLIER))
        );
    }

    function testOwnerCanBeSubAccount() public {
        vm.startPrank(OWNER);

        address subacc = address(uint160(OWNER) ^ 1);
        vault.transferOwnership(subacc);
        evc.call(address(vault), subacc, 0, abi.encodeCall(vault.acceptOwnership, ()));

        _callOwnerFunctions(subacc);
    }

    function testOperatorCanCallOwnerFunctions() public {
        bytes19 prefix = evc.getAddressPrefix(OWNER);
        vm.prank(OWNER);
        evc.setOperator(prefix, OPERATOR, 1);

        vm.startPrank(OPERATOR);
        _callOwnerFunctions(OWNER);
    }

    function testUseVaultFromSubaccount() public {
        loanToken.setBalance(SUPPLIER, 2e18);
        address subacc1 = address(uint160(SUPPLIER) ^ 1);
        address subacc2 = address(uint160(SUPPLIER) ^ 2);

        vm.startPrank(SUPPLIER);
        loanToken.approve(address(vault), type(uint256).max);

        evc.call(address(vault), SUPPLIER, 0, abi.encodeCall(vault.deposit, (1e18, subacc1)));
        assertEq(vault.balanceOf(subacc1), 1e18);

        evc.call(address(vault), SUPPLIER, 0, abi.encodeCall(vault.mint, (1e18, subacc1)));
        assertEq(vault.balanceOf(subacc1), 2e18);

        assertEq(loanToken.balanceOf(SUPPLIER), 0);

        evc.call(address(vault), subacc1, 0, abi.encodeCall(vault.transfer, (subacc2, 1e18)));
        assertEq(vault.balanceOf(subacc2), 1e18);

        evc.call(address(vault), subacc1, 0, abi.encodeCall(vault.approve, (subacc2, 1e18)));
        evc.call(address(vault), subacc2, 0, abi.encodeCall(vault.transferFrom, (subacc1, subacc2, 1e18)));
        assertEq(vault.balanceOf(subacc2), 2e18);

        evc.call(address(vault), subacc2, 0, abi.encodeCall(vault.withdraw, (1e18, SUPPLIER, subacc2)));
        assertEq(vault.balanceOf(subacc2), 1e18);

        evc.call(address(vault), subacc2, 0, abi.encodeCall(vault.redeem, (1e18, SUPPLIER, subacc2)));
        assertEq(vault.balanceOf(subacc2), 0);

        assertEq(loanToken.balanceOf(SUPPLIER), 2e18);
    }

    function testPreventWithdrawingToSubAccount() public {
        loanToken.setBalance(SUPPLIER, 1e18);
        address subacc1 = address(uint160(SUPPLIER) ^ 1);

        vm.startPrank(SUPPLIER);
        loanToken.approve(address(vault), type(uint256).max);

        evc.call(address(vault), SUPPLIER, 0, abi.encodeCall(vault.deposit, (1e18, subacc1)));

        vm.expectRevert(ErrorsLib.BadAssetReceiver.selector);
        evc.call(address(vault), subacc1, 0, abi.encodeCall(vault.withdraw, (1e18, subacc1, subacc1)));

        vm.expectRevert(ErrorsLib.BadAssetReceiver.selector);
        evc.call(address(vault), subacc1, 0, abi.encodeCall(vault.redeem, (1e18, subacc1, subacc1)));
    }

    function _callOwnerFunctions(address onBehalfOf) internal {
        evc.call(address(vault), onBehalfOf, 0, abi.encodeCall(vault.setName, ("new name")));
        assertEq(vault.name(), "new name");
        evc.call(address(vault), onBehalfOf, 0, abi.encodeCall(vault.setSymbol, ("new symbol")));
        assertEq(vault.symbol(), "new symbol");
        evc.call(address(vault), onBehalfOf, 0, abi.encodeCall(vault.setCurator, makeAddr("new curator")));
        assertEq(vault.curator(), makeAddr("new curator"));
        evc.call(address(vault), onBehalfOf, 0, abi.encodeCall(vault.setIsAllocator, (makeAddr("new allocator"), true)));
        assertEq(vault.isAllocator(makeAddr("new allocator")), true);
        evc.call(address(vault), onBehalfOf, 0, abi.encodeCall(vault.submitTimelock, (3 days)));
        assertEq(vault.pendingTimelock().value, 3 days);
        evc.call(address(vault), onBehalfOf, 0, abi.encodeCall(vault.setFee, (0.123e18)));
        assertEq(vault.fee(), 0.123e18);
    }

    function _expectRevertOwnerFunctions(address onBehalfOf, bytes memory errorBytes) internal {
        vm.expectRevert(errorBytes);
        evc.call(address(vault), onBehalfOf, 0, abi.encodeCall(vault.setName, ("new name")));
        vm.expectRevert(errorBytes);
        evc.call(address(vault), onBehalfOf, 0, abi.encodeCall(vault.setSymbol, ("new symbol")));
        vm.expectRevert(errorBytes);
        evc.call(address(vault), onBehalfOf, 0, abi.encodeCall(vault.setCurator, makeAddr("new curator")));
        vm.expectRevert(errorBytes);
        evc.call(address(vault), onBehalfOf, 0, abi.encodeCall(vault.setIsAllocator, (makeAddr("new allocator"), true)));
        vm.expectRevert(errorBytes);
        evc.call(address(vault), onBehalfOf, 0, abi.encodeCall(vault.submitTimelock, (3 days)));
        vm.expectRevert(errorBytes);
        evc.call(address(vault), onBehalfOf, 0, abi.encodeCall(vault.setFee, (0.123e18)));
    }
}
