// SPDX-License-Identifier: BSL-1.1
pragma solidity =0.8.28;

import {Base_Unit_Test} from "../../Base_Unit_Test.t.sol";

import {Risc0VerifierMock} from "../../mocks/Risc0VerifierMock.sol";
import {LendingProtocolMock} from "../../mocks/LendingProtocolMock.sol";

contract LendingProtocolMock_test is Base_Unit_Test {
    LendingProtocolMock public protocol;
    Risc0VerifierMock public verifierMock;

    struct Commitment {
        uint256 id;
        bytes32 digest;
        bytes32 configID;
    }

    function setUp() public override {
        super.setUp();

        verifierMock = new Risc0VerifierMock();
        vm.label(address(verifierMock), "verifierMock");

        protocol = new LendingProtocolMock(address(weth), address(verifierMock), address(this));
        vm.label(address(protocol), "LendingProtocolMock");
    }

    function _createJournal(uint256 amount, address user) internal pure returns (bytes memory) {
        uint256 encodedID = uint256(0) << 240 | uint256(1); //version and value
        Commitment memory data = Commitment(encodedID, "", "0x123");
        return abi.encode(data, amount, user);
    }

    modifier whenSetVerifierIsCalled() {
        // does nothing; for readability only
        _;
    }

    function test_GivenTheCallerIsNotTheOwner() external whenSetVerifierIsCalled {
        _resetContext(alice);
        vm.expectRevert();
        protocol.setVerifier(address(this));
    }

    function test_GivenTheCallerIsTheOwner() external whenSetVerifierIsCalled {
        protocol.setVerifier(address(this));
        assertEq(address(protocol.verifier()), address(this));
    }

    modifier whenSetBorrowImageIdIsCalled() {
        // does nothing; for readability only
        _;
    }

    function test_GivenTheCallerIsNotOwner() external whenSetBorrowImageIdIsCalled {
        _resetContext(alice);
        vm.expectRevert();
        protocol.setBorrowImageId(bytes32("0x1"));
    }

    function test_GivenTheCallerIsOwnerX() external whenSetBorrowImageIdIsCalled {
        protocol.setBorrowImageId(bytes32("0x1"));
        assertEq(protocol.borrowImageId(), bytes32("0x1"));
    }

    modifier whenDepositIsCalled() {
        // does nothing; for readability only
        _;
    }

    function test_GivenTheAmountIsZero() external whenDepositIsCalled {
        uint256 balanceBefore = protocol.balanceOf(address(this));
        protocol.deposit(0, address(this));
        uint256 balanceAfter = protocol.balanceOf(address(this));

        assertEq(balanceAfter, balanceBefore);
    }

    function test_WhenTheAmountIsGreaterThanZero(uint256 amount)
        external
        inRange(amount, SMALL, LARGE)
        whenDepositIsCalled
    {
        _getTokens(weth, address(this), amount);
        weth.approve(address(protocol), amount);

        uint256 underlyingBalanceBefore = weth.balanceOf(address(this));
        uint256 balanceBefore = protocol.balanceOf(address(this));
        protocol.deposit(amount, address(this));
        uint256 underlyingBalanceAfter = weth.balanceOf(address(this));
        uint256 balanceAfter = protocol.balanceOf(address(this));

        // it should increase the recipient’s balance
        assertEq(balanceAfter, balanceBefore + amount);

        // it should transfer tokens to the contract
        assertEq(underlyingBalanceAfter + amount, underlyingBalanceBefore);
    }

    modifier whenBorrowIsCalled() {
        // does nothing; for readability only
        _;
    }

    function test_GivenTheJournalDataIsInvalid(uint256 amount)
        external
        inRange(amount, SMALL, LARGE)
        whenBorrowIsCalled
    {
        // it should revert with LendingProtocolMock_JournalNotValid
        vm.expectRevert(LendingProtocolMock.LendingProtocolMock_JournalNotValid.selector);
        protocol.borrow(amount, "", "0x123");
    }

    function test_GivenTheLiquidityIsInsufficientX(uint256 amount)
        external
        inRange(amount, SMALL, LARGE)
        whenBorrowIsCalled
    {
        bytes memory journalData = _createJournal(amount / 2, address(this));

        vm.expectRevert(LendingProtocolMock.LendingProtocolMock_InsufficientLiquidity.selector);
        protocol.borrow(amount, journalData, "0x123");
        // it should revert with LendingProtocolMock_InsufficientLiquidity
    }

    modifier whenLiquidityIsSufficient() {
        // does nothing; for readability only
        _;
    }

    function test_WhenThereAreEnoughTokensInTheContract(uint256 amount)
        external
        inRange(amount, SMALL, LARGE)
        whenBorrowIsCalled
        whenLiquidityIsSufficient
    {
        _getTokens(weth, address(this), amount);
        weth.approve(address(protocol), amount);

        protocol.deposit(amount, address(this));

        uint256 underlyingBalanceBefore = weth.balanceOf(address(this));
        uint256 balanceBorrowBefore = protocol.borrowBalanceOf(address(this));

        bytes memory journalData = _createJournal(amount, address(this));
        protocol.borrow(amount, journalData, "0x123");

        uint256 underlyingBalanceAfter = weth.balanceOf(address(this));
        uint256 balanceBorrowAfter = protocol.borrowBalanceOf(address(this));

        // it should transfer tokens to the user
        assertEq(underlyingBalanceAfter, underlyingBalanceBefore + amount);

        // it should increase the user's borrow balance
        assertEq(balanceBorrowAfter, balanceBorrowBefore + amount);
    }

    function test_GivenThereAreNotEnoughTokensInTheContract(uint256 amount)
        external
        inRange(amount, SMALL, LARGE)
        whenBorrowIsCalled
        whenLiquidityIsSufficient
    {
        bytes memory journalData = _createJournal(amount, address(this));

        vm.expectRevert(LendingProtocolMock.LendingProtocolMock_InsufficientBalance.selector);
        protocol.borrow(amount, journalData, "0x123");

        // it should revert with LendingProtocolMock_InsufficientBalance
    }

    modifier whenRepayIsCalled() {
        // does nothing; for readability only
        _;
    }

    function test_GivenTheBorrowBalanceIsInsufficient(uint256 amount)
        external
        inRange(amount, SMALL, LARGE)
        whenRepayIsCalled
    {
        vm.expectRevert(LendingProtocolMock.LendingProtocolMock_InsufficientBalance.selector);
        protocol.repay(amount);
    }

    function test_WhenTheBorrowBalanceIsSufficient(uint256 amount)
        external
        inRange(amount, SMALL, LARGE)
        whenRepayIsCalled
    {
        _getTokens(weth, address(this), amount);
        weth.approve(address(protocol), amount);
        protocol.deposit(amount, address(this));

        bytes memory journalData = _createJournal(amount, address(this));
        protocol.borrow(amount, journalData, "0x123");

        uint256 underlyingBalanceBefore = weth.balanceOf(address(this));
        uint256 balanceBorrowBefore = protocol.borrowBalanceOf(address(this));
        weth.approve(address(protocol), amount);
        protocol.repay(amount);
        uint256 balanceBorrowAfter = protocol.borrowBalanceOf(address(this));
        uint256 underlyingBalanceAfter = weth.balanceOf(address(this));

        // it should reduce the borrow balance
        assertEq(balanceBorrowBefore - amount, balanceBorrowAfter);

        // it should transfer tokens from the user to the contract
        assertEq(underlyingBalanceAfter + amount, underlyingBalanceBefore);
    }

    modifier whenWithdrawIsCalled() {
        // does nothing; for readability only
        _;
    }

    function test_GivenTheUsersBalanceIsInsufficient(uint256 amount)
        external
        inRange(amount, SMALL, LARGE)
        whenWithdrawIsCalled
    {
        bytes memory journalData = _createJournal(amount, address(this));
        vm.expectRevert(LendingProtocolMock.LendingProtocolMock_InsufficientBalance.selector);
        protocol.withdraw(amount, journalData, "0x123");
    }

    function test_WhenTheUsersBalanceIsSufficient(uint256 amount)
        external
        inRange(amount, SMALL, LARGE)
        whenWithdrawIsCalled
    {
        _getTokens(weth, address(this), amount);
        weth.approve(address(protocol), amount);
        protocol.deposit(amount, address(this));

        uint256 underlyingBalanceBefore = weth.balanceOf(address(this));
        uint256 balanceBefore = protocol.balanceOf(address(this));

        bytes memory journalData = _createJournal(amount, address(this));
        protocol.withdraw(amount, journalData, "0x123");

        uint256 underlyingBalanceAfter = weth.balanceOf(address(this));
        uint256 balanceAfter = protocol.balanceOf(address(this));

        // it should reduce the user's balance
        assertEq(balanceAfter + amount, balanceBefore);

        // it should transfer tokens to the user
        assertEq(underlyingBalanceBefore + amount, underlyingBalanceAfter);
    }
}
