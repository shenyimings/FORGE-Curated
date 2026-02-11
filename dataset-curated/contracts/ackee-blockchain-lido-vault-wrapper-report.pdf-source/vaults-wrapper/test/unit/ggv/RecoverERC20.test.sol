// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {SetupGGVStrategy} from "./SetupGGVStrategy.sol";
import {GGVStrategy} from "src/strategy/GGVStrategy.sol";
import {IStrategyCallForwarder} from "src/interfaces/IStrategyCallForwarder.sol";
import {StrategyCallForwarder} from "src/strategy/StrategyCallForwarder.sol";

// Mock ERC20 that returns bool (standard)
contract MockERC20Standard is ERC20 {
    constructor() ERC20("Standard Token", "STD") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

// Mock ERC20 that returns no value (like USDT)
contract MockERC20NoReturn is ERC20 {
    constructor() ERC20("No Return Token", "NRT") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    // Override transfer to return nothing (like USDT)
    function transfer(address to, uint256 amount) public override returns (bool) {
        _transfer(msg.sender, to, amount);
        // Use assembly to return empty data (no return value)
        assembly {
            return(0, 0)
        }
    }
}

// Mock ERC20 that can return false
contract MockERC20ReturnsFalse is ERC20 {
    bool public shouldFail;

    constructor() ERC20("Fail Token", "FAIL") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function setShouldFail(bool _shouldFail) external {
        shouldFail = _shouldFail;
    }

    function transfer(address to, uint256 amount) public override returns (bool) {
        if (shouldFail) {
            return false;
        }
        return super.transfer(to, amount);
    }
}

contract RecoverERC20Test is Test, SetupGGVStrategy {
    MockERC20Standard public standardToken;
    MockERC20NoReturn public noReturnToken;
    MockERC20ReturnsFalse public failToken;

    address public recipient;

    function setUp() public override {
        super.setUp();

        recipient = makeAddr("recipient");

        // Deploy mock tokens
        standardToken = new MockERC20Standard();
        noReturnToken = new MockERC20NoReturn();
        failToken = new MockERC20ReturnsFalse();
    }

    function test_recoverERC20_StandardToken_Success() public {
        uint256 amount = 100 ether;

        // Get user's call forwarder
        IStrategyCallForwarder callForwarder = ggvStrategy.getStrategyCallForwarderAddress(userAlice);

        // Mint tokens to call forwarder
        standardToken.mint(address(callForwarder), amount);

        // Verify initial balances
        assertEq(standardToken.balanceOf(address(callForwarder)), amount);
        assertEq(standardToken.balanceOf(recipient), 0);

        // Recover tokens
        vm.prank(userAlice);
        ggvStrategy.safeTransferERC20(address(standardToken), recipient, amount);

        // Verify final balances
        assertEq(standardToken.balanceOf(address(callForwarder)), 0);
        assertEq(standardToken.balanceOf(recipient), amount);
    }

    function test_recoverERC20_NoReturnToken_Success() public {
        uint256 amount = 100 ether;

        // Get user's call forwarder
        IStrategyCallForwarder callForwarder = ggvStrategy.getStrategyCallForwarderAddress(userAlice);

        // Mint tokens to call forwarder
        noReturnToken.mint(address(callForwarder), amount);

        // Verify initial balances
        assertEq(noReturnToken.balanceOf(address(callForwarder)), amount);
        assertEq(noReturnToken.balanceOf(recipient), 0);

        // Recover tokens (should work even though token doesn't return value)
        vm.prank(userAlice);
        ggvStrategy.safeTransferERC20(address(noReturnToken), recipient, amount);

        // Verify final balances
        assertEq(noReturnToken.balanceOf(address(callForwarder)), 0);
        assertEq(noReturnToken.balanceOf(recipient), amount);
    }

    function test_recoverERC20_ReturnsFalse_Reverts() public {
        uint256 amount = 100 ether;

        // Get user's call forwarder
        IStrategyCallForwarder callForwarder = ggvStrategy.getStrategyCallForwarderAddress(userAlice);

        // Mint tokens to call forwarder
        failToken.mint(address(callForwarder), amount);

        // Set token to return false (and NOT perform transfer)
        failToken.setShouldFail(true);

        // Verify initial balances
        assertEq(failToken.balanceOf(address(callForwarder)), amount);
        assertEq(failToken.balanceOf(recipient), 0);

        // The implementation now uses safeTransferERC20 which uses SafeERC20.safeTransfer.
        // SafeERC20 checks the return value and reverts with SafeERC20FailedOperation
        // if the token returns false, which is the correct behavior to fix the audit issue.
        vm.prank(userAlice);
        vm.expectRevert(
            abi.encodeWithSelector(
                SafeERC20.SafeERC20FailedOperation.selector, address(failToken)
            )
        );
        ggvStrategy.safeTransferERC20(address(failToken), recipient, amount);

        // Verify balances remain unchanged after revert
        assertEq(failToken.balanceOf(address(callForwarder)), amount, "Tokens should still be in call forwarder");
        assertEq(failToken.balanceOf(recipient), 0, "Recipient should not receive tokens");
    }

    function test_recoverERC20_ZeroToken_Reverts() public {
        vm.prank(userAlice);
        vm.expectRevert(abi.encodeWithSelector(GGVStrategy.ZeroArgument.selector, "_token"));
        ggvStrategy.safeTransferERC20(address(0), recipient, 100 ether);
    }

    function test_recoverERC20_ZeroRecipient_Reverts() public {
        vm.prank(userAlice);
        vm.expectRevert(abi.encodeWithSelector(GGVStrategy.ZeroArgument.selector, "_recipient"));
        ggvStrategy.safeTransferERC20(address(standardToken), address(0), 100 ether);
    }

    function test_recoverERC20_ZeroAmount_Reverts() public {
        vm.prank(userAlice);
        vm.expectRevert(abi.encodeWithSelector(GGVStrategy.ZeroArgument.selector, "_amount"));
        ggvStrategy.safeTransferERC20(address(standardToken), recipient, 0);
    }

    function test_recoverERC20_PartialAmount_Success() public {
        uint256 totalAmount = 100 ether;
        uint256 recoverAmount = 30 ether;

        // Get user's call forwarder
        IStrategyCallForwarder callForwarder = ggvStrategy.getStrategyCallForwarderAddress(userAlice);

        // Mint tokens to call forwarder
        standardToken.mint(address(callForwarder), totalAmount);

        // Recover partial amount
        vm.prank(userAlice);
        ggvStrategy.safeTransferERC20(address(standardToken), recipient, recoverAmount);

        // Verify balances
        assertEq(standardToken.balanceOf(address(callForwarder)), totalAmount - recoverAmount);
        assertEq(standardToken.balanceOf(recipient), recoverAmount);
    }

    function test_recoverERC20_InsufficientBalance_Reverts() public {
        uint256 amount = 100 ether;
        uint256 availableAmount = amount - 1;

        // Get user's call forwarder
        IStrategyCallForwarder callForwarder = ggvStrategy.getStrategyCallForwarderAddress(userAlice);

        // Mint less than requested
        standardToken.mint(address(callForwarder), availableAmount);

        // Recover should revert due to insufficient balance
        // ERC20 transfer will revert when balance is insufficient
        vm.prank(userAlice);
        vm.expectRevert();
        ggvStrategy.safeTransferERC20(address(standardToken), recipient, amount);
    }

    function test_recoverERC20_OnlyOwnerCanRecover() public {
        uint256 amount = 100 ether;

        // Get user's call forwarder
        IStrategyCallForwarder callForwarder = ggvStrategy.getStrategyCallForwarderAddress(userAlice);

        // Mint tokens to call forwarder
        standardToken.mint(address(callForwarder), amount);

        // Try to recover from different user's call forwarder
        // Should fail because userBob doesn't own userAlice's call forwarder
        vm.prank(userBob);
        vm.expectRevert();
        ggvStrategy.safeTransferERC20(address(standardToken), recipient, amount);
    }
}

