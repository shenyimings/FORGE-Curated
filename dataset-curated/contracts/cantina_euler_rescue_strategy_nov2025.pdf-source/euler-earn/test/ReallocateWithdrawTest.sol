// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.26;

import {UtilsLib} from "../src/libraries/UtilsLib.sol";

import "./helpers/IntegrationTest.sol";

uint256 constant CAP2 = 100e18;
uint256 constant INITIAL_DEPOSIT = 4 * CAP2;

contract ReallocateWithdrawTest is IntegrationTest {
    using UtilsLib for uint256;

    MarketAllocation[] internal allocations;

    function setUp() public override {
        super.setUp();

        _setCap(allMarkets[0], CAP2);
        _setCap(allMarkets[1], CAP2);
        _setCap(allMarkets[2], CAP2);

        _sortSupplyQueueIdleLast();

        loanToken.setBalance(SUPPLIER, INITIAL_DEPOSIT);

        vm.prank(SUPPLIER);
        vault.deposit(INITIAL_DEPOSIT, ONBEHALF);
    }

    function testReallocateWithdrawMax() public {
        allocations.push(MarketAllocation(allMarkets[0], 0));
        allocations.push(MarketAllocation(allMarkets[1], 0));
        allocations.push(MarketAllocation(allMarkets[2], 0));
        allocations.push(MarketAllocation(idleVault, type(uint256).max));

        vm.expectEmit();
        emit EventsLib.ReallocateWithdraw(ALLOCATOR, allMarkets[0], CAP2, allMarkets[0].balanceOf(address(vault)));
        emit EventsLib.ReallocateWithdraw(ALLOCATOR, allMarkets[1], CAP2, allMarkets[1].balanceOf(address(vault)));
        emit EventsLib.ReallocateWithdraw(ALLOCATOR, allMarkets[2], CAP2, allMarkets[2].balanceOf(address(vault)));

        vm.prank(ALLOCATOR);
        vault.reallocate(allocations);

        assertEq(allMarkets[0].balanceOf(address(vault)), 0, "balanceOf(0)");
        assertEq(allMarkets[1].balanceOf(address(vault)), 0, "balanceOf(1)");
        assertEq(allMarkets[2].balanceOf(address(vault)), 0, "balanceOf(2)");
        assertEq(_idle(), INITIAL_DEPOSIT, "idle");
    }

    function testReallocateWithdrawMarketNotEnabled() public {
        ERC20Mock loanToken2 = new ERC20Mock("loan2", "B2");
        IERC4626 id = IERC4626(
            factory.createProxy(address(0), true, abi.encodePacked(address(loanToken2), address(oracle), unitOfAccount))
        );
        _toEVault(id).setHookConfig(address(0), 0);

        loanToken2.setBalance(SUPPLIER, 1);

        vm.startPrank(SUPPLIER);
        loanToken2.approve(address(id), type(uint256).max);
        id.deposit(1, address(vault));
        vm.stopPrank();

        allocations.push(MarketAllocation(id, 0));

        vm.prank(ALLOCATOR);
        vm.expectRevert(abi.encodeWithSelector(ErrorsLib.MarketNotEnabled.selector, id));
        vault.reallocate(allocations);
    }

    function testReallocateWithdrawSupply(uint256[3] memory newAssets) public {
        uint256[3] memory totalAssets;
        uint256[3] memory totalSupply;

        totalAssets[0] = allMarkets[0].totalAssets();
        totalAssets[1] = allMarkets[1].totalAssets();
        totalAssets[2] = allMarkets[2].totalAssets();

        totalSupply[0] = allMarkets[0].totalSupply();
        totalSupply[1] = allMarkets[1].totalSupply();
        totalSupply[2] = allMarkets[2].totalSupply();

        newAssets[0] = bound(newAssets[0], 0, CAP2);
        newAssets[1] = bound(newAssets[1], 0, CAP2);
        newAssets[2] = bound(newAssets[2], 0, CAP2);

        uint256[3] memory assets;
        assets[0] = _expectedSupplyAssets(allMarkets[0], address(vault));
        assets[1] = _expectedSupplyAssets(allMarkets[1], address(vault));
        assets[2] = _expectedSupplyAssets(allMarkets[2], address(vault));

        allocations.push(MarketAllocation(idleVault, 0));
        allocations.push(MarketAllocation(allMarkets[0], newAssets[0]));
        allocations.push(MarketAllocation(allMarkets[1], newAssets[1]));
        allocations.push(MarketAllocation(allMarkets[2], newAssets[2]));
        allocations.push(MarketAllocation(idleVault, type(uint256).max));

        uint256 expectedIdle = _idle() + 3 * CAP2 - newAssets[0] - newAssets[1] - newAssets[2];

        emit EventsLib.ReallocateWithdraw(ALLOCATOR, idleVault, 0, 0);

        if (newAssets[0] < assets[0]) emit EventsLib.ReallocateWithdraw(ALLOCATOR, allMarkets[0], 0, 0);
        else if (newAssets[0] > assets[0]) emit EventsLib.ReallocateSupply(ALLOCATOR, allMarkets[0], 0, 0);

        if (newAssets[1] < assets[1]) emit EventsLib.ReallocateWithdraw(ALLOCATOR, allMarkets[1], 0, 0);
        else if (newAssets[1] > assets[1]) emit EventsLib.ReallocateSupply(ALLOCATOR, allMarkets[1], 0, 0);

        if (newAssets[2] < assets[2]) emit EventsLib.ReallocateWithdraw(ALLOCATOR, allMarkets[2], 0, 0);
        else if (newAssets[2] > assets[2]) emit EventsLib.ReallocateSupply(ALLOCATOR, allMarkets[2], 0, 0);

        emit EventsLib.ReallocateSupply(ALLOCATOR, idleVault, 0, 0);

        vm.prank(ALLOCATOR);
        vault.reallocate(allocations);

        assertEq(allMarkets[0].balanceOf(address(vault)), newAssets[0], "balanceOf(0)");
        assertEq(allMarkets[1].balanceOf(address(vault)), newAssets[1], "balanceOf(1)");
        assertEq(allMarkets[2].balanceOf(address(vault)), newAssets[2], "balanceOf(2)");
        assertEq(_idle(), expectedIdle, "idle");
    }

    function testReallocateWithdrawIncreaseSupply() public {
        _setCap(allMarkets[2], 3 * CAP2);

        allocations.push(MarketAllocation(allMarkets[0], 0));
        allocations.push(MarketAllocation(allMarkets[1], 0));
        allocations.push(MarketAllocation(allMarkets[2], 3 * CAP2));

        vm.expectEmit();
        emit EventsLib.ReallocateWithdraw(ALLOCATOR, allMarkets[0], CAP2, allMarkets[0].balanceOf(address(vault)));
        emit EventsLib.ReallocateWithdraw(ALLOCATOR, allMarkets[1], CAP2, allMarkets[1].balanceOf(address(vault)));
        emit EventsLib.ReallocateSupply(ALLOCATOR, allMarkets[2], 3 * CAP2, 3 * allMarkets[2].balanceOf(address(vault)));

        vm.prank(ALLOCATOR);
        vault.reallocate(allocations);

        assertEq(allMarkets[0].balanceOf(address(vault)), 0, "balanceOf(0)");
        assertEq(allMarkets[1].balanceOf(address(vault)), 0, "balanceOf(1)");
        assertEq(allMarkets[2].balanceOf(address(vault)), 3 * CAP2, "balanceOf(2)");
    }

    function testReallocateUnauthorizedMarket(uint256[3] memory suppliedAssets) public {
        suppliedAssets[0] = bound(suppliedAssets[0], 1, CAP2);
        suppliedAssets[1] = bound(suppliedAssets[1], 1, CAP2);
        suppliedAssets[2] = bound(suppliedAssets[2], 1, CAP2);

        _setCap(allMarkets[1], 0);

        allocations.push(MarketAllocation(allMarkets[0], 0));
        allocations.push(MarketAllocation(allMarkets[1], 0));
        allocations.push(MarketAllocation(allMarkets[2], 0));

        allocations.push(MarketAllocation(allMarkets[0], suppliedAssets[0]));
        allocations.push(MarketAllocation(allMarkets[1], suppliedAssets[1]));
        allocations.push(MarketAllocation(allMarkets[2], suppliedAssets[2]));

        vm.prank(ALLOCATOR);
        vm.expectRevert(abi.encodeWithSelector(ErrorsLib.SupplyCapExceeded.selector, allMarkets[1]));
        vault.reallocate(allocations);
    }

    function testReallocateSupplyCapExceeded() public {
        allocations.push(MarketAllocation(allMarkets[0], 0));
        allocations.push(MarketAllocation(allMarkets[1], 0));
        allocations.push(MarketAllocation(allMarkets[2], 0));

        allocations.push(MarketAllocation(allMarkets[0], CAP2 + 1));

        vm.prank(ALLOCATOR);
        vm.expectRevert(abi.encodeWithSelector(ErrorsLib.SupplyCapExceeded.selector, allMarkets[0]));
        vault.reallocate(allocations);
    }

    function testReallocateInconsistentReallocation(uint256 rewards) public {
        rewards = bound(rewards, 1, MAX_TEST_ASSETS);

        loanToken.setBalance(address(vault), rewards);

        _setCap(allMarkets[0], type(uint136).max);

        allocations.push(MarketAllocation(idleVault, 0));
        allocations.push(MarketAllocation(allMarkets[0], 2 * CAP2 + rewards));

        vm.prank(ALLOCATOR);
        vm.expectRevert(ErrorsLib.InconsistentReallocation.selector);
        vault.reallocate(allocations);
    }

    function testReallocateZeroToDisabledMarket() public {
        allocations.push(MarketAllocation(allMarkets[0], CAP2));
        allocations.push(MarketAllocation(allMarkets[1], CAP2));
        allocations.push(MarketAllocation(allMarkets[2], CAP2));
        allocations.push(MarketAllocation(allMarkets[3], 0)); // non enabled market.
        allocations.push(MarketAllocation(idleVault, type(uint256).max));

        vm.prank(ALLOCATOR);
        vm.expectRevert(abi.encodeWithSelector(ErrorsLib.MarketNotEnabled.selector, allMarkets[3]));
        vault.reallocate(allocations);
    }
}
