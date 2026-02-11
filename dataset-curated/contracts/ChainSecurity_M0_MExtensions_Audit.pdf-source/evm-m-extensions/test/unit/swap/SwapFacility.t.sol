// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.26;

import { Test } from "../../../lib/forge-std/src/Test.sol";

import { Upgrades, UnsafeUpgrades } from "../../../lib/openzeppelin-foundry-upgrades/src/Upgrades.sol";

import { ISwapFacility } from "../../../src/swap/interfaces/ISwapFacility.sol";

import { SwapFacility } from "../../../src/swap/SwapFacility.sol";

import { MockM, MockMExtension, MockRegistrar } from "../../utils/Mocks.sol";

contract SwapFacilityUnitTests is Test {
    bytes32 public constant M_SWAPPER_ROLE = keccak256("M_SWAPPER_ROLE");

    SwapFacility public swapFacility;

    MockM public mToken;
    MockRegistrar public registrar;
    MockMExtension public extensionA;
    MockMExtension public extensionB;
    address public swapAdapter = makeAddr("swapAdapter");

    address public owner = makeAddr("owner");
    address public alice = makeAddr("alice");

    function setUp() public {
        mToken = new MockM();
        registrar = new MockRegistrar();

        swapFacility = SwapFacility(
            UnsafeUpgrades.deployUUPSProxy(
                address(new SwapFacility(address(mToken), address(registrar), swapAdapter)),
                abi.encodeWithSelector(SwapFacility.initialize.selector, owner)
            )
        );

        extensionA = new MockMExtension(address(mToken), address(swapFacility));
        extensionB = new MockMExtension(address(mToken), address(swapFacility));

        // Add Extensions to Earners List
        registrar.setEarner(address(extensionA), true);
        registrar.setEarner(address(extensionB), true);
    }

    function test_initialState() external {
        assertEq(swapFacility.mToken(), address(mToken));
        assertEq(swapFacility.registrar(), address(registrar));
        assertTrue(swapFacility.hasRole(swapFacility.DEFAULT_ADMIN_ROLE(), owner));
    }

    function test_constructor_zeroMToken() external {
        vm.expectRevert(ISwapFacility.ZeroMToken.selector);
        new SwapFacility(address(0), address(registrar), swapAdapter);
    }

    function test_constructor_zeroRegistrar() external {
        vm.expectRevert(ISwapFacility.ZeroRegistrar.selector);
        new SwapFacility(address(mToken), address(0), swapAdapter);
    }

    function test_constructor_zeroSwapAdapter() external {
        vm.expectRevert(ISwapFacility.ZeroSwapAdapter.selector);
        new SwapFacility(address(mToken), address(registrar), address(0));
    }

    function test_swap() external {
        uint256 amount = 1_000;
        mToken.setBalanceOf(alice, amount);

        vm.startPrank(alice);
        mToken.approve(address(swapFacility), amount);
        swapFacility.swapInM(address(extensionA), amount, alice);

        assertEq(mToken.balanceOf(alice), 0);
        assertEq(extensionA.balanceOf(alice), amount);
        assertEq(extensionB.balanceOf(alice), 0);

        vm.expectEmit(true, true, true, true);
        emit ISwapFacility.Swapped(address(extensionA), address(extensionB), amount, alice);

        swapFacility.swap(address(extensionA), address(extensionB), amount, alice);

        assertEq(mToken.balanceOf(alice), 0);
        assertEq(extensionA.balanceOf(alice), 0);
        assertEq(extensionB.balanceOf(alice), amount);
    }

    function test_swap_notApprovedExtension() external {
        address notApprovedExtension = address(0x123);

        vm.expectRevert(abi.encodeWithSelector(ISwapFacility.NotApprovedExtension.selector, notApprovedExtension));
        swapFacility.swap(address(0x123), address(extensionA), 1_000, alice);

        vm.expectRevert(abi.encodeWithSelector(ISwapFacility.NotApprovedExtension.selector, notApprovedExtension));
        swapFacility.swap(address(extensionB), address(0x123), 1_000, alice);
    }

    function test_swapInM() external {
        uint256 amount = 1_000;
        mToken.setBalanceOf(alice, amount);

        vm.prank(alice);
        mToken.approve(address(swapFacility), amount);

        vm.expectEmit(true, true, true, true);
        emit ISwapFacility.SwappedInM(address(extensionA), amount, alice);

        vm.prank(alice);
        swapFacility.swapInM(address(extensionA), amount, alice);

        assertEq(mToken.balanceOf(alice), 0);
        assertEq(extensionA.balanceOf(alice), amount);
    }

    function test_swapInM_notApprovedExtension() external {
        address notApprovedExtension = address(0x123);

        vm.expectRevert(abi.encodeWithSelector(ISwapFacility.NotApprovedExtension.selector, notApprovedExtension));
        swapFacility.swapInM(address(0x123), 1, alice);
    }

    function test_swapOutM() external {
        uint256 amount = 1_000;
        mToken.setBalanceOf(alice, amount);

        vm.prank(owner);
        swapFacility.grantRole(M_SWAPPER_ROLE, alice);

        vm.startPrank(alice);
        swapFacility.swapInM(address(extensionA), amount, alice);

        assertEq(mToken.balanceOf(alice), 0);
        assertEq(extensionA.balanceOf(alice), amount);

        extensionA.approve(address(swapFacility), amount);

        vm.expectEmit(true, true, true, true);
        emit ISwapFacility.SwappedOutM(address(extensionA), amount, alice);

        swapFacility.swapOutM(address(extensionA), amount, alice);

        assertEq(mToken.balanceOf(alice), amount);
        assertEq(extensionA.balanceOf(alice), 0);
    }

    function test_swapOutM_notApprovedExtension() external {
        address notApprovedExtension = address(0x123);

        vm.expectRevert(abi.encodeWithSelector(ISwapFacility.NotApprovedExtension.selector, notApprovedExtension));
        swapFacility.swapOutM(address(0x123), 1, alice);
    }

    function test_swapOutM_notApprovedSwapper() external {
        vm.expectRevert(abi.encodeWithSelector(ISwapFacility.NotApprovedSwapper.selector, alice));

        vm.prank(alice);
        swapFacility.swapOutM(address(extensionA), 1, alice);
    }
}
