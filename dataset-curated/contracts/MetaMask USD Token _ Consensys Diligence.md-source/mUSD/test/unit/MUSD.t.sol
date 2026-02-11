// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { IAccessControl } from "../../lib/evm-m-extensions/lib/common/lib/openzeppelin-contracts-upgradeable/lib/openzeppelin-contracts/contracts/access/IAccessControl.sol";

import { PausableUpgradeable } from "../../lib/evm-m-extensions/lib/common/lib/openzeppelin-contracts-upgradeable/contracts/utils/PausableUpgradeable.sol";

import { IERC20 } from "../../lib/forge-std/src/interfaces/IERC20.sol";

import { Upgrades } from "../../lib/evm-m-extensions/lib/openzeppelin-foundry-upgrades/src/Upgrades.sol";

import { IERC20Extended } from "../../lib/evm-m-extensions/lib/common/src/interfaces/IERC20Extended.sol";
import { IMYieldToOne } from "../../lib/evm-m-extensions/src/projects/yieldToOne/IMYieldToOne.sol";
import { IFreezable } from "../../lib/evm-m-extensions/src/components/IFreezable.sol";
import { IMExtension } from "../../lib/evm-m-extensions/src/interfaces/IMExtension.sol";

import { IMUSD } from "../../src/IMUSD.sol";

import { BaseUnitTest } from "../../lib/evm-m-extensions/test/utils/BaseUnitTest.sol";

import { MUSDHarness } from "../harness/MUSDHarness.sol";

contract MUSDUnitTests is BaseUnitTest {
    MUSDHarness public mUSD;

    string public constant NAME = "MUSD";
    string public constant SYMBOL = "mUSD";

    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    address public pauser = makeAddr("pauser");
    address public forcedTransferManager = makeAddr("forcedTransferManager");

    function setUp() public override {
        super.setUp();

        mUSD = MUSDHarness(
            Upgrades.deployTransparentProxy(
                "MUSDHarness.sol:MUSDHarness",
                admin,
                abi.encodeWithSelector(
                    MUSDHarness.initialize.selector,
                    yieldRecipient,
                    admin,
                    freezeManager,
                    yieldRecipientManager,
                    pauser,
                    forcedTransferManager
                ),
                mExtensionDeployOptions
            )
        );

        registrar.setEarner(address(mUSD), true);
    }

    /* ============ initialize ============ */

    function test_initialize() external view {
        assertEq(mUSD.name(), NAME);
        assertEq(mUSD.symbol(), SYMBOL);
        assertEq(mUSD.decimals(), 6);
        assertEq(mUSD.mToken(), address(mToken));
        assertEq(mUSD.swapFacility(), address(swapFacility));
        assertEq(mUSD.yieldRecipient(), yieldRecipient);

        assertTrue(IAccessControl(address(mUSD)).hasRole(DEFAULT_ADMIN_ROLE, admin));
        assertTrue(IAccessControl(address(mUSD)).hasRole(FREEZE_MANAGER_ROLE, freezeManager));
        assertTrue(IAccessControl(address(mUSD)).hasRole(YIELD_RECIPIENT_MANAGER_ROLE, yieldRecipientManager));
        assertTrue(IAccessControl(address(mUSD)).hasRole(mUSD.PAUSER_ROLE(), pauser));
        assertTrue(IAccessControl(address(mUSD)).hasRole(mUSD.FORCED_TRANSFER_MANAGER_ROLE(), forcedTransferManager));
    }

    /* ============ claimYield ============ */

    function test_claimYield_onlyYieldRecipientManager() external {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                alice,
                YIELD_RECIPIENT_MANAGER_ROLE
            )
        );

        vm.prank(alice);
        mUSD.claimYield();
    }

    function test_claimYield() external {
        uint256 yield = 500e6;

        mToken.setBalanceOf(address(mUSD), 1_500e6);
        mUSD.setTotalSupply(1_000e6);

        assertEq(mUSD.yield(), yield);

        vm.expectEmit();
        emit IMYieldToOne.YieldClaimed(yield);

        vm.prank(yieldRecipientManager);
        assertEq(mUSD.claimYield(), yield);

        assertEq(mUSD.yield(), 0);

        assertEq(mToken.balanceOf(address(mUSD)), 1_500e6);
        assertEq(mUSD.totalSupply(), 1_500e6);

        assertEq(mToken.balanceOf(yieldRecipient), 0);
        assertEq(mUSD.balanceOf(yieldRecipient), yield);
    }

    /* ============ pause ============ */

    function test_pause_onlyPauser() external {
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, alice, mUSD.PAUSER_ROLE())
        );

        vm.prank(alice);
        mUSD.pause();
    }

    function test_pause() external {
        vm.prank(pauser);
        mUSD.pause();

        assertTrue(mUSD.paused());
    }

    /* ============ unpause ============ */

    function test_unpause_onlyPauser() external {
        vm.prank(pauser);
        mUSD.pause();

        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, alice, mUSD.PAUSER_ROLE())
        );

        vm.prank(alice);
        mUSD.unpause();
    }

    function test_unpause() external {
        vm.prank(pauser);
        mUSD.pause();

        vm.prank(pauser);
        mUSD.unpause();

        assertFalse(mUSD.paused());
    }

    /* ============ wrap ============ */

    function test_wrap_whenPaused() external {
        vm.prank(pauser);
        mUSD.pause();

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);

        vm.prank(address(swapFacility));
        mUSD.wrap(alice, 1e6);
    }

    function test_wrap() external {
        uint256 amount_ = 1_000e6;
        mToken.setBalanceOf(address(swapFacility), amount_);

        vm.expectCall(
            address(mToken),
            abi.encodeWithSelector(mToken.transferFrom.selector, address(swapFacility), address(mUSD), amount_)
        );

        vm.expectEmit();
        emit IERC20.Transfer(address(0), alice, amount_);

        vm.prank(address(swapFacility));
        mUSD.wrap(alice, amount_);

        assertEq(mUSD.balanceOf(alice), amount_);
        assertEq(mUSD.totalSupply(), amount_);

        assertEq(mToken.balanceOf(alice), 0);
        assertEq(mToken.balanceOf(address(mUSD)), amount_);
    }

    /* ============ unwrap ============ */

    function test_unwrap_whenPaused() external {
        vm.prank(pauser);
        mUSD.pause();

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);

        vm.prank(address(swapFacility));
        mUSD.unwrap(alice, 1e6);
    }

    function test_unwrap() external {
        uint256 amount_ = 1_000e6;

        mUSD.setBalanceOf(address(swapFacility), amount_);
        mUSD.setBalanceOf(alice, amount_);
        mUSD.setTotalSupply(amount_);

        mToken.setBalanceOf(address(mUSD), amount_);

        vm.expectEmit();
        emit IERC20.Transfer(address(swapFacility), address(0), 1e6);

        vm.prank(address(swapFacility));
        mUSD.unwrap(alice, 1e6);

        assertEq(mUSD.totalSupply(), 999e6);
        assertEq(mUSD.balanceOf(address(swapFacility)), 999e6);
        assertEq(mToken.balanceOf(address(swapFacility)), 1e6);

        vm.expectEmit();
        emit IERC20.Transfer(address(swapFacility), address(0), 499e6);

        vm.prank(address(swapFacility));
        mUSD.unwrap(alice, 499e6);

        assertEq(mUSD.totalSupply(), 500e6);
        assertEq(mUSD.balanceOf(address(swapFacility)), 500e6);
        assertEq(mToken.balanceOf(address(swapFacility)), 500e6);

        vm.expectEmit();
        emit IERC20.Transfer(address(swapFacility), address(0), 500e6);

        vm.prank(address(swapFacility));
        mUSD.unwrap(alice, 500e6);

        assertEq(mUSD.totalSupply(), 0);
        assertEq(mUSD.balanceOf(address(swapFacility)), 0);

        // M tokens are sent to SwapFacility and then forwarded to Alice
        assertEq(mToken.balanceOf(address(swapFacility)), amount_);
        assertEq(mToken.balanceOf(address(mUSD)), 0);
    }

    /* ============ transfer ============ */

    function test_transfer_whenPaused() external {
        vm.prank(pauser);
        mUSD.pause();

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);

        vm.prank(alice);
        mUSD.transfer(bob, 1e6);
    }

    function test_transfer() external {
        uint256 amount_ = 1_000e6;
        mUSD.setBalanceOf(alice, amount_);

        vm.expectEmit();
        emit IERC20.Transfer(alice, bob, amount_);

        vm.prank(alice);
        mUSD.transfer(bob, amount_);

        assertEq(mUSD.balanceOf(alice), 0);
        assertEq(mUSD.balanceOf(bob), amount_);
    }

    /* ============ approve ============ */
    function test_approve_whenPaused() external {
        vm.prank(pauser);
        mUSD.pause();

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        vm.prank(alice);

        mUSD.approve(bob, 1e6);
    }

    /* ============ forceTransfer ============ */

    function test_forceTransfer_revertWhenNotForcedTransferManager() external {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                admin,
                mUSD.FORCED_TRANSFER_MANAGER_ROLE()
            )
        );

        vm.prank(admin);
        mUSD.forceTransfer(alice, bob, 1e6);
    }

    function test_forceTransfer_revertWhenAccountNotFrozen() external {
        vm.expectRevert(abi.encodeWithSelector(IFreezable.AccountNotFrozen.selector, alice));

        vm.prank(forcedTransferManager);
        mUSD.forceTransfer(alice, bob, 1e6);
    }

    function test_forceTransfer_revertWhenInvalidRecipient() external {
        vm.prank(freezeManager);
        mUSD.freeze(alice);

        vm.expectRevert(abi.encodeWithSelector(IERC20Extended.InvalidRecipient.selector, address(0)));

        vm.prank(forcedTransferManager);
        mUSD.forceTransfer(alice, address(0), 0);
    }

    function test_forceTransfer_revertWhenInsufficientBalance() external {
        uint256 amount_ = 1_000e6;
        mUSD.setBalanceOf(alice, amount_);

        vm.prank(freezeManager);
        mUSD.freeze(alice);

        vm.expectRevert(abi.encodeWithSelector(IMExtension.InsufficientBalance.selector, alice, amount_, 2 * amount_));

        vm.prank(forcedTransferManager);
        mUSD.forceTransfer(alice, bob, 2 * amount_);
    }

    function test_forceTransfer() external {
        uint256 amount_ = 1_000e6;
        mUSD.setBalanceOf(alice, amount_);

        vm.prank(freezeManager);
        mUSD.freeze(alice);

        vm.expectEmit();
        emit IERC20.Transfer(alice, bob, amount_);

        vm.expectEmit();
        emit IMUSD.ForcedTransfer(alice, bob, forcedTransferManager, amount_);

        vm.prank(forcedTransferManager);
        mUSD.forceTransfer(alice, bob, amount_);

        assertEq(mUSD.balanceOf(alice), 0);
        assertEq(mUSD.balanceOf(bob), amount_);
    }

    /* ============ forceTransfers ============ */

    function test_forceTransfers_revertWhenNotForcedTransferManager() external {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                admin,
                mUSD.FORCED_TRANSFER_MANAGER_ROLE()
            )
        );

        vm.prank(admin);
        mUSD.forceTransfers(new address[](0), new address[](0), new uint256[](0));
    }

    function test_forceTransfers_revertWhenArrayLengthMismatch_v1() external {
        vm.expectRevert(IMUSD.ArrayLengthMismatch.selector);

        vm.prank(forcedTransferManager);
        mUSD.forceTransfers(new address[](1), new address[](0), new uint256[](0));
    }

    function test_forceTransfers_revertWhenArrayLengthMismatch_v2() external {
        vm.expectRevert(IMUSD.ArrayLengthMismatch.selector);

        vm.prank(forcedTransferManager);
        mUSD.forceTransfers(new address[](0), new address[](0), new uint256[](1));
    }

    function test_forceTransfers() external {
        uint256 amount1 = 1_000e6;
        uint256 amount2 = 2_000e6;

        address[] memory frozenAccounts = new address[](2);
        frozenAccounts[0] = alice;
        frozenAccounts[1] = carol;

        address[] memory destinations = new address[](2);
        destinations[0] = bob;
        destinations[1] = charlie;

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = amount1;
        amounts[1] = amount2;

        mUSD.setBalanceOf(alice, amount1);
        mUSD.setBalanceOf(carol, amount2);

        vm.prank(freezeManager);
        mUSD.freeze(alice);

        vm.prank(freezeManager);
        mUSD.freeze(carol);

        vm.prank(forcedTransferManager);
        mUSD.forceTransfers(frozenAccounts, destinations, amounts);

        assertEq(mUSD.balanceOf(alice), 0);
        assertEq(mUSD.balanceOf(carol), 0);
        assertEq(mUSD.balanceOf(destinations[0]), amount1);
        assertEq(mUSD.balanceOf(destinations[1]), amount2);
    }
}
