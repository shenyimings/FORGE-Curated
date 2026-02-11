// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.26;

import {
    IAccessControl
} from "../../../lib/common/lib/openzeppelin-contracts-upgradeable/lib/openzeppelin-contracts/contracts/access/IAccessControl.sol";

import { Upgrades, UnsafeUpgrades } from "../../../lib/openzeppelin-foundry-upgrades/src/Upgrades.sol";

import { IMExtension } from "../../../src/interfaces/IMExtension.sol";
import { IMEarnerManager } from "../../../src/projects/earnerManager/IMEarnerManager.sol";

import { IERC20 } from "../../../lib/common/src/interfaces/IERC20.sol";
import { IERC20Extended } from "../../../lib/common/src/interfaces/IERC20Extended.sol";

import { MEarnerManagerHarness } from "../../harness/MEarnerManagerHarness.sol";
import { BaseUnitTest } from "../../utils/BaseUnitTest.sol";

contract MEarnerManagerUnitTests is BaseUnitTest {
    MEarnerManagerHarness public mEarnerManager;

    // address public admin = makeAddr("admin");
    address public earnerManager = makeAddr("earnerManager");

    bytes32 public constant EARNER_MANAGER_ROLE = keccak256("EARNER_MANAGER_ROLE");

    function setUp() public override {
        super.setUp();

        mToken.setCurrentIndex(11e11);

        mEarnerManager = MEarnerManagerHarness(
            Upgrades.deployUUPSProxy(
                "MEarnerManagerHarness.sol:MEarnerManagerHarness",
                abi.encodeWithSelector(
                    MEarnerManagerHarness.initialize.selector,
                    "MEarnerManager",
                    "MEM",
                    address(mToken),
                    address(swapFacility),
                    admin,
                    earnerManager,
                    feeRecipient
                )
            )
        );

        // Made mEarnerManager the earner, so it can be used in SwapFacility
        registrar.setEarner(address(mEarnerManager), true);

        // Whitelist SwapFacility
        mEarnerManager.setAccountOf(address(swapFacility), 0, 0, true, 0);
    }

    /* ============ initialize ============ */

    function test_initialize() external view {
        assertEq(mEarnerManager.ONE_HUNDRED_PERCENT(), 10_000);
        assertEq(mEarnerManager.feeRecipient(), feeRecipient);
        assertTrue(mEarnerManager.hasRole(DEFAULT_ADMIN_ROLE, admin));
        assertTrue(mEarnerManager.hasRole(EARNER_MANAGER_ROLE, earnerManager));
    }

    function test_initialize_zeroMToken() external {
        address implementation = address(new MEarnerManagerHarness());

        vm.expectRevert(IMExtension.ZeroMToken.selector);
        MEarnerManagerHarness(
            UnsafeUpgrades.deployUUPSProxy(
                implementation,
                abi.encodeWithSelector(
                    MEarnerManagerHarness.initialize.selector,
                    "MEarnerManager",
                    "MEM",
                    address(0),
                    address(swapFacility),
                    admin,
                    earnerManager,
                    feeRecipient
                )
            )
        );
    }

    function test_initialize_zeroAdmin() external {
        address implementation = address(new MEarnerManagerHarness());

        vm.expectRevert(IMEarnerManager.ZeroAdmin.selector);
        MEarnerManagerHarness(
            UnsafeUpgrades.deployUUPSProxy(
                implementation,
                abi.encodeWithSelector(
                    MEarnerManagerHarness.initialize.selector,
                    "MEarnerManager",
                    "MEM",
                    address(mToken),
                    address(swapFacility),
                    address(0),
                    earnerManager,
                    feeRecipient
                )
            )
        );
    }

    function test_initialize_zeroEarnerManager() external {
        address implementation = address(new MEarnerManagerHarness());

        vm.expectRevert(IMEarnerManager.ZeroEarnerManager.selector);
        MEarnerManagerHarness(
            UnsafeUpgrades.deployUUPSProxy(
                implementation,
                abi.encodeWithSelector(
                    MEarnerManagerHarness.initialize.selector,
                    "MEarnerManager",
                    "MEM",
                    address(mToken),
                    address(swapFacility),
                    admin,
                    address(0),
                    feeRecipient
                )
            )
        );
    }

    function test_initialize_zeroFeeRecipient() external {
        address implementation = address(new MEarnerManagerHarness());

        vm.expectRevert(IMEarnerManager.ZeroFeeRecipient.selector);
        MEarnerManagerHarness(
            UnsafeUpgrades.deployUUPSProxy(
                implementation,
                abi.encodeWithSelector(
                    MEarnerManagerHarness.initialize.selector,
                    "MEarnerManager",
                    "MEM",
                    address(mToken),
                    address(swapFacility),
                    admin,
                    earnerManager,
                    address(0)
                )
            )
        );
    }

    // /* ============ setAccountInfo ============ */

    function test_setAccountInfo_zeroYieldRecipient() external {
        vm.expectRevert(IMEarnerManager.ZeroAccount.selector);

        vm.prank(earnerManager);
        mEarnerManager.setAccountInfo(address(0), true, 1000);
    }

    function test_setAccountInfo_invalidFeeRate() external {
        vm.expectRevert(IMEarnerManager.InvalidFeeRate.selector);

        vm.prank(earnerManager);
        mEarnerManager.setAccountInfo(alice, true, 10_001);
    }

    function test_setAccountInfo_invalidAccountInfo() external {
        vm.expectRevert(IMEarnerManager.InvalidAccountInfo.selector);

        vm.prank(earnerManager);
        mEarnerManager.setAccountInfo(alice, false, 9_000);
    }

    function test_setAccountInfo_onlyEarnerManager() external {
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, alice, EARNER_MANAGER_ROLE)
        );

        vm.prank(alice);
        mEarnerManager.setAccountInfo(alice, true, 10_001);
    }

    function test_setAccountInfo_whitelistAccount() external {
        mEarnerManager.setAccountOf(alice, 1_000e6, 1_000e6, false, 0);

        assertFalse(mEarnerManager.isWhitelisted(alice));
        assertEq(mEarnerManager.feeRateOf(alice), 0);

        vm.expectEmit();
        emit IMEarnerManager.AccountInfoSet(alice, true, 1_000);

        vm.prank(earnerManager);
        mEarnerManager.setAccountInfo(alice, true, 1_000);

        assertTrue(mEarnerManager.isWhitelisted(alice));
        assertEq(mEarnerManager.feeRateOf(alice), 1_000);
    }

    function test_setAccountInfo_unwhitelistAccount() external {
        mEarnerManager.setAccountOf(alice, 1_000e6, 1_000e6, true, 1_000);

        assertEq(mEarnerManager.isWhitelisted(alice), true);
        assertEq(mEarnerManager.feeRateOf(alice), 1_000);

        uint256 yield = mEarnerManager.accruedYieldOf(alice);
        uint256 fee = mEarnerManager.accruedFeeOf(alice);

        vm.expectEmit();
        emit IMEarnerManager.AccountInfoSet(alice, false, 0);

        vm.expectEmit();
        emit IMEarnerManager.YieldClaimed(alice, yield);

        vm.expectEmit();
        emit IERC20.Transfer(address(0), alice, yield + fee);

        vm.expectEmit();
        emit IMEarnerManager.FeeClaimed(alice, feeRecipient, fee);

        vm.expectEmit();
        emit IERC20.Transfer(alice, feeRecipient, fee);

        vm.prank(earnerManager);
        mEarnerManager.setAccountInfo(alice, false, 0);

        assertEq(mEarnerManager.isWhitelisted(alice), false);
        assertEq(mEarnerManager.feeRateOf(alice), 10_000);

        assertEq(mEarnerManager.balanceOf(alice), 1_000e6 + yield);
        assertEq(mEarnerManager.balanceOf(feeRecipient), fee);
    }

    function test_setAccountInfo_changeFee() external {
        mEarnerManager.setAccountOf(alice, 1_000e6, 1_000e6, true, 1_000);

        assertEq(mEarnerManager.isWhitelisted(alice), true);
        assertEq(mEarnerManager.feeRateOf(alice), 1_000);

        uint256 yield = mEarnerManager.accruedYieldOf(alice);
        uint256 fee = mEarnerManager.accruedFeeOf(alice);

        // yield is claimed when changing fee rate
        vm.expectEmit();
        emit IMEarnerManager.YieldClaimed(alice, yield);

        vm.prank(earnerManager);
        mEarnerManager.setAccountInfo(alice, true, 2_000);

        assertEq(mEarnerManager.isWhitelisted(alice), true);
        assertEq(mEarnerManager.feeRateOf(alice), 2_000);

        assertEq(mEarnerManager.balanceOf(alice), 1_000e6 + yield);
        assertEq(mEarnerManager.balanceOf(feeRecipient), fee);
    }

    function test_setAccountInfo_noAction() external {
        mEarnerManager.setAccountOf(alice, 1_000e6, 1_000e6, false, 0);
        mEarnerManager.setAccountOf(bob, 1_000e6, 1_000e6, true, 1_000);

        assertEq(mEarnerManager.isWhitelisted(alice), false);
        assertEq(mEarnerManager.feeRateOf(alice), 0);

        assertEq(mEarnerManager.isWhitelisted(bob), true);
        assertEq(mEarnerManager.feeRateOf(bob), 1_000);

        vm.prank(earnerManager);
        mEarnerManager.setAccountInfo(alice, false, 0);

        vm.prank(earnerManager);
        mEarnerManager.setAccountInfo(bob, true, 1_000);

        // No changes
        assertEq(mEarnerManager.isWhitelisted(alice), false);
        assertEq(mEarnerManager.feeRateOf(alice), 0);

        assertEq(mEarnerManager.isWhitelisted(bob), true);
        assertEq(mEarnerManager.feeRateOf(bob), 1_000);
    }

    /* ============ setAccountInfo batch ============ */
    function test_setAccountInfo_batch_onlyEarnerManager() external {
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, alice, EARNER_MANAGER_ROLE)
        );

        vm.prank(alice);
        mEarnerManager.setAccountInfo(new address[](0), new bool[](0), new uint16[](0));
    }

    function test_setAccountInfo_batch_arrayLengthZero() external {
        vm.expectRevert(IMEarnerManager.ArrayLengthZero.selector);

        vm.prank(earnerManager);
        mEarnerManager.setAccountInfo(new address[](0), new bool[](2), new uint16[](2));
    }

    function test_setAccountInfo_batch_arrayLengthMismatch() external {
        vm.expectRevert(IMEarnerManager.ArrayLengthMismatch.selector);

        vm.prank(earnerManager);
        mEarnerManager.setAccountInfo(new address[](1), new bool[](2), new uint16[](2));

        vm.expectRevert(IMEarnerManager.ArrayLengthMismatch.selector);

        vm.prank(earnerManager);
        mEarnerManager.setAccountInfo(new address[](2), new bool[](1), new uint16[](2));

        vm.expectRevert(IMEarnerManager.ArrayLengthMismatch.selector);

        vm.prank(earnerManager);
        mEarnerManager.setAccountInfo(new address[](2), new bool[](2), new uint16[](1));
    }

    function test_setAccountInfo_batch() external {
        address[] memory accounts_ = new address[](2);
        accounts_[0] = alice;
        accounts_[1] = bob;

        bool[] memory statuses = new bool[](2);
        statuses[0] = true;
        statuses[1] = true;

        uint16[] memory feeRates = new uint16[](2);
        feeRates[0] = 1;
        feeRates[1] = 10_000;

        vm.expectEmit();
        emit IMEarnerManager.AccountInfoSet(alice, true, 1);

        vm.expectEmit();
        emit IMEarnerManager.AccountInfoSet(bob, true, 10_000);

        vm.prank(earnerManager);
        mEarnerManager.setAccountInfo(accounts_, statuses, feeRates);

        assertEq(mEarnerManager.isWhitelisted(alice), true);
        assertEq(mEarnerManager.feeRateOf(alice), 1);

        assertEq(mEarnerManager.isWhitelisted(bob), true);
        assertEq(mEarnerManager.feeRateOf(bob), 10_000);
    }

    // /* ============ setFeeRecipient ============ */

    function test_setFeeRecipient_onlyEarnerManager() external {
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, alice, EARNER_MANAGER_ROLE)
        );

        vm.prank(alice);
        mEarnerManager.setFeeRecipient(alice);
    }

    function test_setFeeRecipient_zeroFeeRecipient() external {
        vm.expectRevert(IMEarnerManager.ZeroFeeRecipient.selector);

        vm.prank(earnerManager);
        mEarnerManager.setFeeRecipient(address(0));
    }

    function test_setFeeRecipient_noUpdate() external {
        assertEq(mEarnerManager.feeRecipient(), feeRecipient);

        vm.prank(earnerManager);
        mEarnerManager.setFeeRecipient(feeRecipient);

        assertEq(mEarnerManager.feeRecipient(), feeRecipient);
    }

    function test_setFeeRecipient() external {
        assertEq(mEarnerManager.feeRecipient(), feeRecipient);

        assertEq(mEarnerManager.feeRateOf(feeRecipient), 0);

        address newFeeRecipient = makeAddr("newFeeRecipient");

        vm.expectEmit();
        emit IMEarnerManager.FeeRecipientSet(newFeeRecipient);

        vm.prank(earnerManager);
        mEarnerManager.setFeeRecipient(newFeeRecipient);

        assertEq(mEarnerManager.feeRecipient(), newFeeRecipient);
        assertEq(mEarnerManager.feeRateOf(newFeeRecipient), 0);
    }

    // /* ============ claimFor ============ */

    function test_claimFor_zeroAccount() external {
        vm.expectRevert(abi.encodeWithSelector(IMEarnerManager.ZeroAccount.selector));
        mEarnerManager.claimFor(address(0));
    }

    function test_claimFor_noYield() external {
        mEarnerManager.setAccountOf(alice, 1_900e6, 1_000e6, true, 1_000);

        (uint256 yieldWithFee, uint256 fee, uint256 yieldNetOfFees) = mEarnerManager.accruedYieldAndFeeOf(alice);

        assertEq(yieldWithFee, 0);
        assertEq(fee, 0);
        assertEq(yieldNetOfFees, 0);

        assertEq(mEarnerManager.accruedYieldOf(alice), 0);
        assertEq(mEarnerManager.accruedFeeOf(alice), 0);

        (yieldWithFee, fee, yieldNetOfFees) = mEarnerManager.claimFor(alice);

        assertEq(yieldWithFee, 0);
        assertEq(fee, 0);
        assertEq(yieldNetOfFees, 0);
    }

    function test_claimFor() external {
        mEarnerManager.setAccountOf(alice, 1_000e6, 1_000e6, true, 1_000);

        assertEq(mEarnerManager.isWhitelisted(alice), true);
        assertEq(mEarnerManager.isWhitelisted(feeRecipient), true);

        (uint256 yieldWithFee, uint256 fee, uint256 yieldNetOfFees) = mEarnerManager.accruedYieldAndFeeOf(alice);

        assertEq(yieldWithFee, 100e6);
        assertEq(fee, 10e6);
        assertEq(yieldNetOfFees, 90e6);

        // Sanity check
        assertEq(yieldWithFee, fee + yieldNetOfFees);

        assertEq(mEarnerManager.accruedYieldOf(alice), 90e6);
        assertEq(mEarnerManager.accruedFeeOf(alice), 10e6);

        vm.expectEmit();
        emit IMEarnerManager.YieldClaimed(alice, yieldNetOfFees);

        vm.expectEmit();
        emit IMEarnerManager.FeeClaimed(alice, feeRecipient, fee);

        (yieldWithFee, fee, yieldNetOfFees) = mEarnerManager.claimFor(alice);

        assertEq(yieldWithFee, 100e6);
        assertEq(fee, 10e6);
        assertEq(yieldNetOfFees, 90e6);

        // Yield + fees were claimed
        assertEq(mEarnerManager.accruedYieldOf(alice), 0);
        assertEq(mEarnerManager.accruedFeeOf(alice), 0);

        // Balances were updated
        assertEq(mEarnerManager.balanceOf(alice), 1_000e6 + yieldNetOfFees);
        assertEq(mEarnerManager.balanceOf(feeRecipient), fee);
    }

    function test_claimFor_feeRecipient() external {
        vm.prank(earnerManager);
        mEarnerManager.setFeeRecipient(alice);

        mEarnerManager.setAccountOf(alice, 1_000e6, 1_000e6, true, 0);

        (uint256 yieldWithFee, uint256 fee, uint256 yieldNetOfFees) = mEarnerManager.accruedYieldAndFeeOf(alice);

        assertEq(yieldWithFee, 100e6);
        assertEq(fee, 0e6);
        assertEq(yieldNetOfFees, 100e6);

        assertEq(mEarnerManager.accruedYieldOf(alice), 100e6);
        assertEq(mEarnerManager.accruedFeeOf(alice), 0e6);

        (yieldWithFee, fee, yieldNetOfFees) = mEarnerManager.claimFor(alice);

        assertEq(yieldWithFee, 100e6);
        assertEq(fee, 0e6);
        assertEq(yieldNetOfFees, 100e6);
    }

    function test_claimFor_fee_100() external {
        mEarnerManager.setAccountOf(alice, 1_000e6, 1_000e6, true, 10_000);

        (uint256 yieldWithFee, uint256 fee, uint256 yieldNetOfFees) = mEarnerManager.accruedYieldAndFeeOf(alice);

        assertEq(yieldWithFee, 100e6);
        assertEq(fee, 100e6);
        assertEq(yieldNetOfFees, 0e6);

        assertEq(mEarnerManager.accruedYieldOf(alice), 0e6);
        assertEq(mEarnerManager.accruedFeeOf(alice), 100e6);

        (yieldWithFee, fee, yieldNetOfFees) = mEarnerManager.claimFor(alice);

        assertEq(yieldWithFee, 100e6);
        assertEq(fee, 100e6);
        assertEq(yieldNetOfFees, 0e6);
    }

    /* ============ _approve ============ */

    function test_approve_notWhitelistedAccount() public {
        vm.expectRevert(abi.encodeWithSelector(IMEarnerManager.NotWhitelisted.selector, alice));

        vm.prank(alice);
        mEarnerManager.approve(bob, 1_000e6);
    }

    function test_approve_blacklistedSpender() public {
        mEarnerManager.setAccountOf(alice, 1_000e6, 1_000e6, true, 1_000);

        vm.expectRevert(abi.encodeWithSelector(IMEarnerManager.NotWhitelisted.selector, bob));

        vm.prank(alice);
        mEarnerManager.approve(bob, 1_000e6);
    }

    /* ============ _wrap ============ */

    function test_wrap_notWhitelistedAccount() external {
        uint256 amount = 1_000e6;
        mToken.setBalanceOf(alice, amount);

        vm.expectRevert(abi.encodeWithSelector(IMEarnerManager.NotWhitelisted.selector, alice));

        vm.prank(alice);
        swapFacility.swapInM(address(mEarnerManager), amount, alice);
    }

    function test_wrap_notWhitelistedRecipient() external {
        uint256 amount = 1_000e6;
        mToken.setBalanceOf(alice, amount);

        mEarnerManager.setAccountOf(alice, 0, 0, true, 1_000);

        vm.expectRevert(abi.encodeWithSelector(IMEarnerManager.NotWhitelisted.selector, bob));

        vm.prank(alice);
        swapFacility.swapInM(address(mEarnerManager), amount, bob);
    }

    function test_wrap_insufficientAmount() external {
        vm.expectRevert(abi.encodeWithSelector(IERC20Extended.InsufficientAmount.selector, 0));

        vm.prank(alice);
        swapFacility.swapInM(address(mEarnerManager), 0, alice);
    }

    function test_wrap_invalidRecipient() external {
        mToken.setBalanceOf(alice, 1_000);

        vm.expectRevert(abi.encodeWithSelector(IERC20Extended.InvalidRecipient.selector, address(0)));

        vm.prank(alice);
        swapFacility.swapInM(address(mEarnerManager), 0, address(0));
    }

    function test_wrap() external {
        mEarnerManager.setAccountOf(alice, 0, 0, true, 1_000);
        mEarnerManager.setAccountOf(bob, 0, 0, true, 1_000);

        mToken.setBalanceOf(alice, 2_000);

        assertEq(mToken.balanceOf(alice), 2_000);
        assertEq(mEarnerManager.totalSupply(), 0);
        assertEq(mEarnerManager.balanceOf(alice), 0);
        assertEq(mEarnerManager.accruedYieldOf(alice), 0);

        vm.expectEmit();
        emit IERC20.Transfer(address(0), alice, 1_000);

        vm.prank(alice);
        swapFacility.swapInM(address(mEarnerManager), 1_000, alice);

        assertEq(mToken.balanceOf(address(mEarnerManager)), 1_000);
        assertEq(mEarnerManager.totalSupply(), 1_000);
        assertEq(mEarnerManager.balanceOf(alice), 1_000);
        assertEq(mEarnerManager.accruedYieldOf(alice), 0);

        vm.expectEmit();
        emit IERC20.Transfer(address(0), bob, 1_000);

        vm.prank(alice);
        swapFacility.swapInM(address(mEarnerManager), 1_000, bob);

        assertEq(mToken.balanceOf(alice), 0);
        assertEq(mToken.balanceOf(address(mEarnerManager)), 2_000);
        assertEq(mEarnerManager.totalSupply(), 2_000);
        assertEq(mEarnerManager.balanceOf(bob), 1_000);
        assertEq(mEarnerManager.accruedYieldOf(alice), 0);

        // simulate yield accrual by increasing index
        mToken.setCurrentIndex(12e11);
        assertEq(mEarnerManager.balanceOf(bob), 1_000);

        (uint256 yieldWithFee, uint256 fee, uint256 yieldNetOfFees) = mEarnerManager.accruedYieldAndFeeOf(bob);
        assertEq(yieldWithFee, 90);
        assertEq(fee, 9);
        assertEq(yieldNetOfFees, 81);
    }

    /* ============ _unwrap ============ */
    function test_unwrap_notWhitelistedAccount() external {
        uint256 amount = 1_000e6;
        mToken.setBalanceOf(alice, amount);

        mEarnerManager.setAccountOf(alice, 0, 0, true, 1_000);

        vm.prank(alice);
        swapFacility.swapInM(address(mEarnerManager), amount, alice);

        vm.prank(alice);
        IERC20(address(mEarnerManager)).approve(address(swapFacility), amount);

        mEarnerManager.setAccountOf(alice, 0, 0, false, 1_000);

        vm.expectRevert(abi.encodeWithSelector(IMEarnerManager.NotWhitelisted.selector, alice));

        vm.prank(alice);
        swapFacility.swapOutM(address(mEarnerManager), amount, alice);
    }

    function test_unwrap_insufficientAmount() external {
        mEarnerManager.setAccountOf(alice, 0, 0, true, 1_000);

        vm.prank(alice);
        IERC20(address(mEarnerManager)).approve(address(swapFacility), 1_000);

        vm.expectRevert(abi.encodeWithSelector(IERC20Extended.InsufficientAmount.selector, 0));

        vm.prank(alice);
        swapFacility.swapOutM(address(mEarnerManager), 0, alice);
    }

    function test_unwrap_insufficientBalance() external {
        mEarnerManager.setAccountOf(alice, 0, 0, true, 1_000);
        mToken.setBalanceOf(alice, 999);

        vm.prank(alice);
        swapFacility.swapInM(address(mEarnerManager), 999, alice);

        vm.prank(alice);
        IERC20(address(mEarnerManager)).approve(address(swapFacility), 1_000);

        vm.expectRevert(abi.encodeWithSelector(IMExtension.InsufficientBalance.selector, alice, 999, 1_000));

        vm.prank(alice);
        swapFacility.swapOutM(address(mEarnerManager), 1_000, alice);
    }

    function test_unwrap() external {
        mToken.setBalanceOf(alice, 1000);
        mEarnerManager.setAccountOf(alice, 0, 0, true, 1_000);

        vm.prank(alice);
        swapFacility.swapInM(address(mEarnerManager), 1000, alice);

        assertEq(mToken.balanceOf(alice), 0);
        assertEq(mEarnerManager.balanceOf(alice), 1_000);
        assertEq(mEarnerManager.totalSupply(), 1_000);

        vm.expectEmit();
        emit IERC20.Transfer(alice, address(0), 1);

        vm.prank(alice);
        swapFacility.swapOutM(address(mEarnerManager), 1, alice);

        assertEq(mEarnerManager.totalSupply(), 999);
        assertEq(mEarnerManager.balanceOf(alice), 999);
        assertEq(mToken.balanceOf(alice), 1);

        vm.expectEmit();
        emit IERC20.Transfer(alice, address(0), 499);

        vm.prank(alice);
        swapFacility.swapOutM(address(mEarnerManager), 499, alice);

        assertEq(mEarnerManager.totalSupply(), 500);
        assertEq(mEarnerManager.balanceOf(alice), 500);
        assertEq(mToken.balanceOf(alice), 500);

        vm.expectEmit();
        emit IERC20.Transfer(alice, address(0), 500);

        vm.prank(alice);
        swapFacility.swapOutM(address(mEarnerManager), 500, alice);

        assertEq(mEarnerManager.totalSupply(), 0);
        assertEq(mEarnerManager.balanceOf(alice), 0);
        assertEq(mToken.balanceOf(alice), 1000);
    }

    /* ============ _transfer ============ */
    function test_transfer_insufficientBalance() external {
        uint256 amount = 1_000e6;
        mToken.setBalanceOf(alice, amount);

        mEarnerManager.setAccountOf(alice, 0, 0, true, 1_000);
        mEarnerManager.setAccountOf(bob, 0, 0, true, 1_000);

        vm.prank(alice);
        swapFacility.swapInM(address(mEarnerManager), amount, alice);

        vm.expectRevert(abi.encodeWithSelector(IMExtension.InsufficientBalance.selector, alice, amount, amount + 1));

        vm.prank(alice);
        mEarnerManager.transfer(bob, amount + 1);
    }

    function test_transfer_notWhitelistedSender() external {
        uint256 amount = 1_000e6;
        mToken.setBalanceOf(alice, amount);

        mEarnerManager.setAccountOf(alice, 0, 0, true, 1_000);

        vm.prank(alice);
        swapFacility.swapInM(address(mEarnerManager), amount, alice);

        mEarnerManager.setAccountOf(alice, 0, 0, false, 0);

        // Alice is not whitelisted, cannot transfer her tokens
        vm.expectRevert(abi.encodeWithSelector(IMEarnerManager.NotWhitelisted.selector, alice));

        vm.prank(alice);
        mEarnerManager.transfer(bob, amount);
    }

    function test_transfer_notWhitelistedApprovedSender() external {
        uint256 amount = 1_000e6;
        mToken.setBalanceOf(alice, amount);

        mEarnerManager.setAccountOf(alice, 0, 0, true, 1_000);
        mEarnerManager.setAccountOf(bob, 0, 0, true, 1_000);
        mEarnerManager.setAccountOf(carol, 0, 0, true, 1_000);

        vm.prank(alice);
        swapFacility.swapInM(address(mEarnerManager), amount, alice);

        // Alice allows Carol to transfer tokens on her behalf
        vm.prank(alice);
        mEarnerManager.approve(carol, amount);

        mEarnerManager.setAccountOf(carol, 0, 0, false, 0);

        // Reverts cause Carol is blacklisted and cannot transfer tokens on Alice's behalf
        vm.expectRevert(abi.encodeWithSelector(IMEarnerManager.NotWhitelisted.selector, carol));

        vm.prank(carol);
        mEarnerManager.transferFrom(alice, bob, amount);
    }

    function test_transfer_notWhitelistedRecipient() external {
        uint256 amount = 1_000e6;
        mToken.setBalanceOf(alice, amount);

        mEarnerManager.setAccountOf(alice, 0, 0, true, 1_000);

        vm.prank(alice);
        swapFacility.swapInM(address(mEarnerManager), amount, alice);

        vm.expectRevert(abi.encodeWithSelector(IMEarnerManager.NotWhitelisted.selector, bob));

        vm.prank(alice);
        mEarnerManager.transfer(bob, amount);
    }

    function test_transfer_invalidRecipient() external {
        uint256 amount = 1_000e6;
        mToken.setBalanceOf(alice, amount);

        mEarnerManager.setAccountOf(alice, 0, 0, true, 1_000);

        vm.prank(alice);
        swapFacility.swapInM(address(mEarnerManager), amount, alice);

        vm.expectRevert(abi.encodeWithSelector(IERC20Extended.InvalidRecipient.selector, 0));

        vm.prank(alice);
        mEarnerManager.transfer(address(0), amount);
    }

    function test_transfer() external {
        uint256 amount = 1_000e6;
        mToken.setBalanceOf(alice, amount);

        // whitelist accounts
        mEarnerManager.setAccountOf(alice, 0, 0, true, 1_000);
        mEarnerManager.setAccountOf(bob, 0, 0, true, 1_000);

        vm.prank(alice);
        swapFacility.swapInM(address(mEarnerManager), amount, alice);

        vm.expectEmit();
        emit IERC20.Transfer(alice, bob, amount);

        vm.prank(alice);
        mEarnerManager.transfer(bob, amount);

        assertEq(mEarnerManager.balanceOf(alice), 0);
        assertEq(mEarnerManager.balanceOf(bob), amount);
    }

    function testFuzz_transfer(uint256 supply, uint256 aliceBalance, uint256 transferAmount) external {
        supply = bound(supply, 1, type(uint112).max);
        aliceBalance = bound(aliceBalance, 1, supply);
        transferAmount = bound(transferAmount, 1, aliceBalance);
        uint256 bobBalance = supply - aliceBalance;

        if (bobBalance == 0) return;

        mToken.setBalanceOf(alice, aliceBalance);
        mToken.setBalanceOf(bob, bobBalance);

        // whitelist accounts
        mEarnerManager.setAccountOf(alice, 0, 0, true, 1_000);
        mEarnerManager.setAccountOf(bob, 0, 0, true, 1_000);

        vm.prank(alice);
        swapFacility.swapInM(address(mEarnerManager), aliceBalance, alice);

        vm.prank(bob);
        swapFacility.swapInM(address(mEarnerManager), bobBalance, bob);

        vm.prank(alice);
        mEarnerManager.transfer(bob, transferAmount);

        assertEq(mEarnerManager.balanceOf(alice), aliceBalance - transferAmount);
        assertEq(mEarnerManager.balanceOf(bob), bobBalance + transferAmount);
    }

    /* ============ enableEarning ============ */

    function test_enableEarning_earningEnabled() external {
        mEarnerManager.enableEarning();

        vm.expectRevert(IMExtension.EarningIsEnabled.selector);
        mEarnerManager.enableEarning();
    }

    function test_enableEarning() external {
        mToken.setCurrentIndex(1_210000000000);

        vm.expectEmit();
        emit IMExtension.EarningEnabled(1_210000000000);

        mEarnerManager.enableEarning();

        assertEq(mEarnerManager.isEarningEnabled(), true);
    }

    /* ============ disableEarning ============ */

    function test_disableEarning_earningIsDisabled() external {
        vm.expectRevert(IMExtension.EarningIsDisabled.selector);
        mEarnerManager.disableEarning();
    }

    function test_disableEarning() external {
        mToken.setCurrentIndex(1_100000000000);

        mEarnerManager.enableEarning();

        mToken.setCurrentIndex(1_200000000000);

        mEarnerManager.disableEarning();

        assertEq(mEarnerManager.isEarningEnabled(), false);
    }
}
