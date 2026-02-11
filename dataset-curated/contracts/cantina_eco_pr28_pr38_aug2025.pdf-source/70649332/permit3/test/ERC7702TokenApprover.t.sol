// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { IERC20 } from "@openzeppelin/contracts/interfaces/IERC20.sol";
import { Test, Vm } from "forge-std/Test.sol";

import { Permit3 } from "../src/Permit3.sol";
import { IPermit3 } from "../src/interfaces/IPermit3.sol";
import { ERC7702TokenApprover } from "../src/modules/ERC7702TokenApprover.sol";

// Mock ERC20 for testing
contract MockERC20 {
    mapping(address => mapping(address => uint256)) public allowance;
    mapping(address => uint256) public balanceOf;

    string public name;
    string public symbol;
    uint8 public decimals = 18;

    bool public shouldFailApproval = false;

    constructor(string memory _name, string memory _symbol) {
        name = _name;
        symbol = _symbol;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        if (shouldFailApproval) {
            return false;
        }
        allowance[msg.sender][spender] = amount;
        return true;
    }

    function setShouldFailApproval(
        bool _shouldFail
    ) external {
        shouldFailApproval = _shouldFail;
    }
}

contract ERC7702TokenApproverTest is Test {
    ERC7702TokenApprover public approver;
    Permit3 public permit3;
    MockERC20 public token1;
    MockERC20 public token2;
    MockERC20 public token3;

    uint256 public ownerPrivateKey = uint256(keccak256("test-owner"));
    address public owner;
    address public spender = makeAddr("SPENDER");

    function setUp() public {
        owner = vm.addr(ownerPrivateKey);
        permit3 = new Permit3();
        approver = new ERC7702TokenApprover(address(permit3));
        token1 = new MockERC20("Token1", "TK1");
        token2 = new MockERC20("Token2", "TK2");
        token3 = new MockERC20("Token3", "TK3");
    }

    function test_Constructor() public view {
        assertEq(approver.PERMIT3(), address(permit3));
    }

    function test_Approve_SingleToken() public {
        address[] memory tokens = new address[](1);
        tokens[0] = address(token1);

        // Use proper EIP-7702 cheatcodes
        Vm.SignedDelegation memory signedDelegation = vm.signDelegation(address(approver), ownerPrivateKey);

        vm.startPrank(owner);
        vm.attachDelegation(signedDelegation);
        ERC7702TokenApprover(owner).approve(tokens);
        vm.stopPrank();

        assertEq(token1.allowance(owner, address(permit3)), type(uint256).max);
    }

    function test_Approve_MultipleTokens() public {
        address[] memory tokens = new address[](3);
        tokens[0] = address(token1);
        tokens[1] = address(token2);
        tokens[2] = address(token3);

        // Use proper EIP-7702 cheatcodes
        Vm.SignedDelegation memory signedDelegation = vm.signDelegation(address(approver), ownerPrivateKey);

        vm.startPrank(owner);
        vm.attachDelegation(signedDelegation);
        ERC7702TokenApprover(owner).approve(tokens);
        vm.stopPrank();

        assertEq(token1.allowance(owner, address(permit3)), type(uint256).max);
        assertEq(token2.allowance(owner, address(permit3)), type(uint256).max);
        assertEq(token3.allowance(owner, address(permit3)), type(uint256).max);
    }

    function test_Approve_EmptyArray() public {
        address[] memory tokens = new address[](0);

        // Use proper EIP-7702 cheatcodes
        Vm.SignedDelegation memory signedDelegation = vm.signDelegation(address(approver), ownerPrivateKey);

        vm.startPrank(owner);
        vm.attachDelegation(signedDelegation);
        vm.expectRevert(abi.encodeWithSignature("NoTokensProvided()"));
        ERC7702TokenApprover(owner).approve(tokens);
        vm.stopPrank();
    }

    function test_Approve_ApprovalFails() public {
        token1.setShouldFailApproval(true);

        address[] memory tokens = new address[](1);
        tokens[0] = address(token1);

        // Use proper EIP-7702 cheatcodes
        Vm.SignedDelegation memory signedDelegation = vm.signDelegation(address(approver), ownerPrivateKey);

        vm.startPrank(owner);
        vm.attachDelegation(signedDelegation);
        vm.expectRevert(); // SafeERC20.forceApprove will revert on failure
        ERC7702TokenApprover(owner).approve(tokens);
        vm.stopPrank();
    }

    function test_Approve_PartialFailure() public {
        // Set token2 to fail approval
        token2.setShouldFailApproval(true);

        address[] memory tokens = new address[](3);
        tokens[0] = address(token1);
        tokens[1] = address(token2);
        tokens[2] = address(token3);

        // Use proper EIP-7702 cheatcodes
        Vm.SignedDelegation memory signedDelegation = vm.signDelegation(address(approver), ownerPrivateKey);

        vm.startPrank(owner);
        vm.attachDelegation(signedDelegation);
        vm.expectRevert(); // SafeERC20.forceApprove will revert on failure
        ERC7702TokenApprover(owner).approve(tokens);
        vm.stopPrank();

        // When transaction reverts, no state changes are applied
        assertEq(token1.allowance(owner, address(permit3)), 0);
        assertEq(token2.allowance(owner, address(permit3)), 0);
        assertEq(token3.allowance(owner, address(permit3)), 0);
    }

    function test_Approve_OverwritesExistingAllowance() public {
        // Set initial allowance
        vm.prank(owner);
        token1.approve(address(permit3), 1000);
        assertEq(token1.allowance(owner, address(permit3)), 1000);

        // Approve should overwrite with infinite using EIP-7702
        address[] memory tokens = new address[](1);
        tokens[0] = address(token1);

        Vm.SignedDelegation memory signedDelegation = vm.signDelegation(address(approver), ownerPrivateKey);

        vm.startPrank(owner);
        vm.attachDelegation(signedDelegation);
        ERC7702TokenApprover(owner).approve(tokens);
        vm.stopPrank();

        assertEq(token1.allowance(owner, address(permit3)), type(uint256).max);
    }

    function test_Approve_DifferentEOAs() public {
        uint256 owner2PrivateKey = uint256(keccak256("test-owner-2"));
        address owner2 = vm.addr(owner2PrivateKey);

        address[] memory tokens = new address[](1);
        tokens[0] = address(token1);

        // First EOA approves using EIP-7702
        Vm.SignedDelegation memory signedDelegation1 = vm.signDelegation(address(approver), ownerPrivateKey);
        vm.startPrank(owner);
        vm.attachDelegation(signedDelegation1);
        ERC7702TokenApprover(owner).approve(tokens);
        vm.stopPrank();

        // Second EOA approves using EIP-7702
        Vm.SignedDelegation memory signedDelegation2 = vm.signDelegation(address(approver), owner2PrivateKey);
        vm.startPrank(owner2);
        vm.attachDelegation(signedDelegation2);
        ERC7702TokenApprover(owner2).approve(tokens);
        vm.stopPrank();

        // Both should have infinite allowance
        assertEq(token1.allowance(owner, address(permit3)), type(uint256).max);
        assertEq(token1.allowance(owner2, address(permit3)), type(uint256).max);
    }

    function testFuzz_Approve(
        uint8 tokenCount
    ) public {
        vm.assume(tokenCount > 0 && tokenCount <= 10);

        address[] memory tokens = new address[](tokenCount);
        for (uint256 i = 0; i < tokenCount; i++) {
            tokens[i] = address(new MockERC20("Token", "TK"));
        }

        // Use proper EIP-7702 cheatcodes
        Vm.SignedDelegation memory signedDelegation = vm.signDelegation(address(approver), ownerPrivateKey);

        vm.startPrank(owner);
        vm.attachDelegation(signedDelegation);
        ERC7702TokenApprover(owner).approve(tokens);
        vm.stopPrank();

        for (uint256 i = 0; i < tokenCount; i++) {
            assertEq(IERC20(tokens[i]).allowance(owner, address(permit3)), type(uint256).max);
        }
    }

    // Test direct contract calls (non-ERC7702 scenario)
    // Note: When called directly, the approve calls are made BY the approver contract
    // So the approver contract gets the allowances, which is not useful behavior
    function test_DirectCall_Approve() public {
        address[] memory tokens = new address[](1);
        tokens[0] = address(token1);

        approver.approve(tokens);

        // The allowance will be set for the approver contract (not useful)
        assertEq(token1.allowance(address(approver), address(permit3)), type(uint256).max);
    }
}
