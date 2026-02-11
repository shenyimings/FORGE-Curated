// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import { INonceManager } from "../src/interfaces/INonceManager.sol";
import { IPermit } from "../src/interfaces/IPermit.sol";
import { IPermit3 } from "../src/interfaces/IPermit3.sol";
import { MockToken } from "./utils/TestUtils.sol";

import { Permit3 } from "../src/Permit3.sol";
import { PermitBase } from "../src/PermitBase.sol";
import { IERC7702TokenApprover } from "../src/interfaces/IERC7702TokenApprover.sol";
import { ERC7702TokenApprover } from "../src/modules/ERC7702TokenApprover.sol";

contract ZeroAddressValidationTest is Test {
    Permit3 public permit3;
    MockToken public token;
    ERC7702TokenApprover public approver;

    address alice = address(0x1);
    address bob = address(0x2);

    function setUp() public {
        permit3 = new Permit3();
        token = new MockToken();
        approver = new ERC7702TokenApprover(address(permit3));

        // MockToken automatically mints to the deployer, transfer to alice
        token.transfer(alice, 1000e18);
    }

    function test_permit_RejectsZeroOwner() public {
        IPermit3.AllowanceOrTransfer[] memory permits = new IPermit3.AllowanceOrTransfer[](1);
        permits[0] = IPermit3.AllowanceOrTransfer({
            modeOrExpiration: uint48(100),
            tokenKey: bytes32(uint256(uint160(address(token)))),
            account: bob,
            amountDelta: 100
        });

        vm.expectRevert(abi.encodeWithSelector(INonceManager.InvalidSignature.selector, address(0)));
        permit3.permit(address(0), bytes32(0), uint48(block.timestamp + 1), uint48(block.timestamp), permits, "");
    }

    function test_permitWitness_RejectsZeroOwner() public {
        IPermit3.AllowanceOrTransfer[] memory permits = new IPermit3.AllowanceOrTransfer[](1);
        permits[0] = IPermit3.AllowanceOrTransfer({
            modeOrExpiration: uint48(100),
            tokenKey: bytes32(uint256(uint160(address(token)))),
            account: bob,
            amountDelta: 100
        });

        vm.expectRevert(abi.encodeWithSelector(INonceManager.InvalidSignature.selector, address(0)));
        permit3.permitWitness(
            address(0),
            bytes32(0),
            uint48(block.timestamp + 1),
            uint48(block.timestamp),
            permits,
            bytes32(0),
            "WitnessData witness)",
            ""
        );
    }

    function test_approve_RejectsZeroToken() public {
        vm.startPrank(alice);
        vm.expectRevert(IPermit.ZeroToken.selector);
        permit3.approve(address(0), bob, 100, uint48(block.timestamp + 100));
        vm.stopPrank();
    }

    function test_approve_RejectsZeroSpender() public {
        vm.startPrank(alice);
        vm.expectRevert(IPermit.ZeroSpender.selector);
        permit3.approve(address(token), address(0), 100, uint48(block.timestamp + 100));
        vm.stopPrank();
    }

    function test_transferFrom_RejectsZeroFrom() public {
        vm.startPrank(bob);
        vm.expectRevert(abi.encodeWithSelector(IPermit.InsufficientAllowance.selector, 100, 0));
        permit3.transferFrom(address(0), alice, 100, address(token));
        vm.stopPrank();
    }

    function test_transferFrom_RejectsZeroToken() public {
        vm.startPrank(bob);
        vm.expectRevert(abi.encodeWithSelector(IPermit.InsufficientAllowance.selector, 100, 0));
        permit3.transferFrom(alice, bob, 100, address(0));
        vm.stopPrank();
    }

    function test_transferFrom_RejectsZeroTo() public {
        vm.startPrank(bob);
        vm.expectRevert(abi.encodeWithSelector(IPermit.InsufficientAllowance.selector, 100, 0));
        permit3.transferFrom(alice, address(0), 100, address(token));
        vm.stopPrank();
    }

    function test_lockdown_RejectsZeroToken() public {
        IPermit.TokenSpenderPair[] memory approvals = new IPermit.TokenSpenderPair[](1);
        approvals[0] = IPermit.TokenSpenderPair({ token: address(0), spender: bob });

        vm.startPrank(alice);
        vm.expectRevert(IPermit.ZeroToken.selector);
        permit3.lockdown(approvals);
        vm.stopPrank();
    }

    function test_lockdown_RejectsZeroSpender() public {
        IPermit.TokenSpenderPair[] memory approvals = new IPermit.TokenSpenderPair[](1);
        approvals[0] = IPermit.TokenSpenderPair({ token: address(token), spender: address(0) });

        vm.startPrank(alice);
        vm.expectRevert(IPermit.ZeroSpender.selector);
        permit3.lockdown(approvals);
        vm.stopPrank();
    }

    function test_processAllowanceOperation_RejectsZeroToken() public {
        IPermit3.AllowanceOrTransfer[] memory permits = new IPermit3.AllowanceOrTransfer[](1);
        permits[0] = IPermit3.AllowanceOrTransfer({
            modeOrExpiration: uint48(100),
            tokenKey: bytes32(0),
            account: bob,
            amountDelta: 100
        });

        vm.startPrank(alice);
        vm.expectRevert(IPermit.ZeroToken.selector);
        permit3.permit(permits);
        vm.stopPrank();
    }

    function test_processAllowanceOperation_RejectsZeroAccount() public {
        IPermit3.AllowanceOrTransfer[] memory permits = new IPermit3.AllowanceOrTransfer[](1);
        permits[0] = IPermit3.AllowanceOrTransfer({
            modeOrExpiration: uint48(100),
            tokenKey: bytes32(uint256(uint160(address(token)))),
            account: address(0),
            amountDelta: 100
        });

        vm.startPrank(alice);
        vm.expectRevert(IPermit.ZeroAccount.selector);
        permit3.permit(permits);
        vm.stopPrank();
    }

    function test_ERC7702TokenApprover_RejectsZeroPermit3() public {
        vm.expectRevert(IERC7702TokenApprover.ZeroPermit3.selector);
        new ERC7702TokenApprover(address(0));
    }

    function test_ERC7702TokenApprover_RejectsZeroToken() public {
        address[] memory tokens = new address[](1);
        tokens[0] = address(0);

        vm.expectRevert(IERC7702TokenApprover.ZeroToken.selector);
        approver.approve(tokens);
    }

    function test_invalidateNonces_RejectsZeroOwner() public {
        bytes32[] memory salts = new bytes32[](1);
        salts[0] = bytes32(uint256(1));

        vm.expectRevert(abi.encodeWithSelector(INonceManager.InvalidSignature.selector, address(0)));
        permit3.invalidateNonces(address(0), uint48(block.timestamp + 100), salts, "");
    }
}
