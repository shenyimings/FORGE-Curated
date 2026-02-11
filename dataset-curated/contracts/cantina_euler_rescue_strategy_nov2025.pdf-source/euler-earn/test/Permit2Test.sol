// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.26;

import {IntegrationTest, EulerEarnFactory, TIMELOCK, IEulerEarn} from "./helpers/IntegrationTest.sol";
import {IAllowanceTransfer} from "../src/interfaces/IAllowanceTransfer.sol";

import "forge-std/Test.sol";

contract Permit2Test is IntegrationTest {
    IEulerEarn internal vaultWithPermit2;
    IEulerEarn internal vaultWithoutPermit2;

    function setUp() public virtual override {
        super.setUp();

        vaultWithPermit2 = eeFactory.createEulerEarn(
            OWNER, TIMELOCK, address(loanToken), "EulerEarn Vault", "EEV", bytes32(uint256(2))
        );

        EulerEarnFactory newFactory = new EulerEarnFactory(admin, address(evc), address(0), address(perspective));
        vaultWithoutPermit2 = newFactory.createEulerEarn(
            OWNER, TIMELOCK, address(loanToken), "EulerEarn Vault", "EEV", bytes32(uint256(1))
        );

        vm.startPrank(OWNER);

        vaultWithPermit2.setCurator(CURATOR);
        vaultWithPermit2.setIsAllocator(ALLOCATOR, true);
        vaultWithPermit2.setFeeRecipient(FEE_RECIPIENT);

        vaultWithoutPermit2.setCurator(CURATOR);
        vaultWithoutPermit2.setIsAllocator(ALLOCATOR, true);
        vaultWithoutPermit2.setFeeRecipient(FEE_RECIPIENT);

        vm.stopPrank();
    }

    function testPermit2DepositWithPermit2() public {
        address depositor = makeAddr("permit2depositor");
        loanToken.setBalance(depositor, 1e18);
        _setCap(vaultWithPermit2, idleVault, type(uint136).max);

        vm.startPrank(depositor);

        vm.expectRevert();
        vaultWithPermit2.deposit(1e18, depositor);

        loanToken.approve(permit2, type(uint256).max);
        IAllowanceTransfer(permit2).approve(
            address(loanToken), address(vaultWithPermit2), type(uint160).max, type(uint48).max
        );

        vaultWithPermit2.deposit(1e18, depositor);
        assertEq(vaultWithPermit2.balanceOf(depositor), 1e18);
    }

    function testPermit2DepositExpired() public {
        address depositor = makeAddr("permit2depositor");
        loanToken.setBalance(depositor, 1e18);
        _setCap(vaultWithPermit2, idleVault, type(uint136).max);

        vm.startPrank(depositor);

        vm.expectRevert();
        vaultWithPermit2.deposit(1e18, depositor);

        loanToken.approve(permit2, type(uint256).max);
        IAllowanceTransfer(permit2).approve(
            address(loanToken), address(vaultWithPermit2), type(uint160).max, uint48(block.timestamp + 1)
        );

        skip(2);

        vm.expectRevert();
        vaultWithPermit2.deposit(1e18, depositor);

        // deposit will fall back to token allowance if available
        loanToken.approve(address(vaultWithPermit2), type(uint256).max);
        vaultWithPermit2.deposit(1e18, depositor);
        assertEq(vaultWithPermit2.balanceOf(depositor), 1e18);
    }

    function testPermit2DepositWithoutPermit2() public {
        address depositor = makeAddr("permit2depositor");
        loanToken.setBalance(depositor, 1e18);
        _setCap(vaultWithoutPermit2, idleVault, type(uint136).max);

        vm.startPrank(depositor);

        vm.expectRevert();
        vaultWithoutPermit2.deposit(1e18, depositor);

        loanToken.approve(permit2, type(uint256).max);
        IAllowanceTransfer(permit2).approve(
            address(loanToken), address(vaultWithoutPermit2), type(uint160).max, type(uint48).max
        );

        vm.expectRevert();
        vaultWithoutPermit2.deposit(1e18, depositor);

        loanToken.approve(address(vaultWithoutPermit2), type(uint256).max);
        vaultWithoutPermit2.deposit(1e18, depositor);
        assertEq(vaultWithoutPermit2.balanceOf(depositor), 1e18);
    }

    function testSetCapsCreatesAndRemovesPermit2AllowancesForMarketsWithPermit2() public {
        (uint160 amount, uint48 expiration,) =
            IAllowanceTransfer(permit2).allowance(address(vaultWithPermit2), address(loanToken), address(allMarkets[0]));
        assertEq(amount, 0);
        assertEq(expiration, 0);
        assertEq(loanToken.allowance(address(vaultWithPermit2), address(permit2)), 0);
        assertEq(loanToken.allowance(address(vaultWithPermit2), address(allMarkets[0])), 0);

        _setCap(vaultWithPermit2, allMarkets[0], 100e18);

        (amount, expiration,) =
            IAllowanceTransfer(permit2).allowance(address(vaultWithPermit2), address(loanToken), address(allMarkets[0]));
        assertEq(amount, type(uint160).max);
        assertEq(expiration, type(uint48).max);
        assertEq(loanToken.allowance(address(vaultWithPermit2), address(permit2)), type(uint256).max);
        assertEq(loanToken.allowance(address(vaultWithPermit2), address(allMarkets[0])), 0);

        // remove allowances when setting cap to 0
        _setCap(vaultWithPermit2, allMarkets[0], 0);

        (amount, expiration,) =
            IAllowanceTransfer(permit2).allowance(address(vaultWithPermit2), address(loanToken), address(allMarkets[0]));
        assertEq(amount, 0);
        assertEq(expiration, block.timestamp); // Permit2 sets block.timestamp when called with expiration = 0
        assertEq(loanToken.allowance(address(vaultWithPermit2), address(allMarkets[0])), 0);
        // allowance for permit2 is preserved
        assertEq(loanToken.allowance(address(vaultWithPermit2), address(permit2)), type(uint256).max);
    }

    function testSetCapsCreatesAndRemovesERC20AllowancesForMarketsWithoutPermit2() public {
        (uint160 amount, uint48 expiration,) =
            IAllowanceTransfer(permit2).allowance(address(vaultWithPermit2), address(loanToken), address(allMarkets[0]));
        assertEq(amount, 0);
        assertEq(expiration, 0);
        assertEq(loanToken.allowance(address(vaultWithPermit2), address(permit2)), 0);
        assertEq(loanToken.allowance(address(vaultWithPermit2), address(allMarkets[0])), 0);

        vm.mockCall(address(allMarkets[0]), abi.encodeWithSignature("permit2Address()"), abi.encode(address(0)));
        _setCap(vaultWithPermit2, allMarkets[0], 100e18);

        (amount, expiration,) =
            IAllowanceTransfer(permit2).allowance(address(vaultWithPermit2), address(loanToken), address(allMarkets[0]));
        assertEq(amount, 0);
        assertEq(expiration, 0);
        assertEq(loanToken.allowance(address(vaultWithPermit2), address(permit2)), 0);
        assertEq(loanToken.allowance(address(vaultWithPermit2), address(allMarkets[0])), type(uint256).max);

        uint256 snapshot = vm.snapshotState();

        // remove allowances when setting cap to 0
        vm.mockCall(address(allMarkets[0]), abi.encodeWithSignature("permit2Address()"), abi.encode(address(0)));
        _setCap(vaultWithPermit2, allMarkets[0], 0);
        (amount, expiration,) =
            IAllowanceTransfer(permit2).allowance(address(vaultWithPermit2), address(loanToken), address(allMarkets[0]));
        assertEq(amount, 0);
        assertEq(expiration, 0);
        assertEq(loanToken.allowance(address(vaultWithPermit2), address(permit2)), 0);

        assertEq(loanToken.allowance(address(vaultWithPermit2), address(allMarkets[0])), 0);

        // try again with the approve call reverting
        vm.revertToState(snapshot);
        vm.mockCallRevert(address(loanToken), abi.encodeWithSignature("approve(address,uint256)"), "");

        // remove allowances when setting cap to 0
        _setCap(vaultWithPermit2, allMarkets[0], 0);
        (amount, expiration,) =
            IAllowanceTransfer(permit2).allowance(address(vaultWithPermit2), address(loanToken), address(allMarkets[0]));
        assertEq(amount, 0);
        assertEq(expiration, 0);
        assertEq(loanToken.allowance(address(vaultWithPermit2), address(permit2)), 0);

        // allowance was not removed
        assertGt(loanToken.allowance(address(vaultWithPermit2), address(allMarkets[0])), 1);
    }

    function testSetCapsCreatesAndRemovesERC20AllowancesForMarketsWithoutPermit2TokenReturnsVoid() public {
        loanToken.configure("approve/return-void", bytes("0"));

        testSetCapsCreatesAndRemovesERC20AllowancesForMarketsWithoutPermit2();
    }

    function testSetCapsRemovesERC20AllowancesForMarketsWithoutPermit2TokenRevertsOnZeroAllowance() public {
        loanToken.configure("approve/require-non-zero-allowance", bytes("0"));

        vm.mockCall(address(allMarkets[0]), abi.encodeWithSignature("permit2Address()"), abi.encode(address(0)));
        _setCap(vaultWithPermit2, allMarkets[0], 100e18);

        vm.mockCall(address(allMarkets[0]), abi.encodeWithSignature("permit2Address()"), abi.encode(address(0)));
        _setCap(vaultWithPermit2, allMarkets[0], 0);

        assertEq(loanToken.allowance(address(vaultWithPermit2), address(allMarkets[0])), 1);
    }
}
