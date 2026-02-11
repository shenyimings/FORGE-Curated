// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {BaseTest} from "../BaseTest.sol";
import {Executor} from "../../contracts/Executor.sol";
import {IExecutor} from "../../contracts/interfaces/IExecutor.sol";
import {Call} from "../../contracts/types/Intent.sol";

contract ExecutorTest is BaseTest {
    Executor internal executor;
    address internal unauthorizedUser;
    address internal eoaTarget;
    MockContract internal mockContract;

    function setUp() public override {
        super.setUp();
        unauthorizedUser = makeAddr("unauthorizedUser");
        eoaTarget = makeAddr("eoaTarget");

        mockContract = new MockContract();

        vm.prank(address(portal));
        executor = new Executor();
    }

    function test_constructor_setsPortalCorrectly() public {
        Call[] memory calls = new Call[](1);
        calls[0] = Call({
            target: address(mockContract),
            value: 0,
            data: abi.encodeWithSignature("succeed()")
        });

        address testPortal = makeAddr("testPortal");
        vm.prank(testPortal);
        Executor testExecutor = new Executor();

        vm.prank(testPortal);
        testExecutor.execute(calls);
    }

    function test_execute_revertUnauthorized() public {
        Call[] memory calls = new Call[](1);
        calls[0] = Call({
            target: address(tokenA),
            value: 0,
            data: abi.encodeWithSignature(
                "transfer(address,uint256)",
                otherPerson,
                100
            )
        });

        vm.prank(unauthorizedUser);
        vm.expectRevert(
            abi.encodeWithSelector(
                IExecutor.NonPortalCaller.selector,
                unauthorizedUser
            )
        );
        executor.execute(calls);
    }

    function test_execute_success_authorizedCaller() public {
        tokenA.mint(address(executor), 1000);

        Call[] memory calls = new Call[](1);
        calls[0] = Call({
            target: address(tokenA),
            value: 0,
            data: abi.encodeWithSignature(
                "transfer(address,uint256)",
                otherPerson,
                100
            )
        });

        uint256 balanceBefore = tokenA.balanceOf(otherPerson);

        vm.prank(address(portal));
        bytes[] memory results = executor.execute(calls);

        uint256 balanceAfter = tokenA.balanceOf(otherPerson);

        assertEq(balanceAfter, balanceBefore + 100);
        assertTrue(abi.decode(results[0], (bool)));
    }

    function test_execute_success_withValue() public {
        vm.deal(address(portal), 10 ether);

        Call[] memory calls = new Call[](1);
        calls[0] = Call({
            target: address(mockContract),
            value: 1 ether,
            data: abi.encodeWithSignature("receiveEther()")
        });

        uint256 contractBalanceBefore = address(mockContract).balance;

        vm.prank(address(portal));
        executor.execute{value: 1 ether}(calls);

        uint256 contractBalanceAfter = address(mockContract).balance;
        assertEq(contractBalanceAfter, contractBalanceBefore + 1 ether);
    }

    function test_execute_success_returnsData() public {
        Call[] memory calls = new Call[](1);
        calls[0] = Call({
            target: address(mockContract),
            value: 0,
            data: abi.encodeWithSignature("returnData()")
        });

        vm.prank(address(portal));
        bytes[] memory results = executor.execute(calls);

        assertEq(results[0], abi.encode(uint256(42), "test"));
    }

    function test_execute_revertCallToEOA_withCalldata() public {
        Call[] memory calls = new Call[](1);
        calls[0] = Call({
            target: eoaTarget,
            value: 0,
            data: abi.encodeWithSignature("someFunction()")
        });

        vm.prank(address(portal));
        vm.expectRevert(
            abi.encodeWithSelector(IExecutor.CallToEOA.selector, eoaTarget)
        );
        executor.execute(calls);
    }

    function test_execute_success_EOAWithoutCalldata() public {
        vm.deal(address(portal), 10 ether);

        Call[] memory calls = new Call[](1);
        calls[0] = Call({target: eoaTarget, value: 1 ether, data: ""});

        uint256 balanceBefore = eoaTarget.balance;

        vm.prank(address(portal));
        executor.execute{value: 1 ether}(calls);

        uint256 balanceAfter = eoaTarget.balance;
        assertEq(balanceAfter, balanceBefore + 1 ether);
    }

    function test_execute_success_contractWithEmptyCalldata() public {
        Call[] memory calls = new Call[](1);
        calls[0] = Call({target: address(mockContract), value: 0, data: ""});

        vm.prank(address(portal));
        bytes[] memory results = executor.execute(calls);

        assertEq(results[0].length, 0);
    }

    function test_execute_revertCallFailed() public {
        Call[] memory calls = new Call[](1);
        calls[0] = Call({
            target: address(mockContract),
            value: 0,
            data: abi.encodeWithSignature("fail()")
        });

        vm.prank(address(portal));
        vm.expectRevert();
        executor.execute(calls);
    }

    function test_execute_revertCallFailed_insufficientValue() public {
        Call[] memory calls = new Call[](1);
        calls[0] = Call({
            target: address(mockContract),
            value: 1 ether,
            data: abi.encodeWithSignature("receiveEther()")
        });

        vm.prank(address(portal));
        vm.expectRevert();
        executor.execute(calls);
    }

    function test_execute_revertCallFailed_invalidFunction() public {
        Call[] memory calls = new Call[](1);
        calls[0] = Call({
            target: address(tokenA),
            value: 0,
            data: abi.encodeWithSignature("nonExistentFunction()")
        });

        vm.prank(address(portal));
        vm.expectRevert();
        executor.execute(calls);
    }

    function test_execute_success_emptyDataToContract() public {
        Call[] memory calls = new Call[](1);
        calls[0] = Call({target: address(mockContract), value: 0, data: ""});

        vm.prank(address(portal));
        bytes[] memory results = executor.execute(calls);

        assertEq(results[0].length, 0);
    }

    function test_execute_success_batchCalls() public {
        tokenA.mint(address(executor), 1000);

        Call[] memory calls = new Call[](3);
        calls[0] = Call({
            target: address(tokenA),
            value: 0,
            data: abi.encodeWithSignature(
                "transfer(address,uint256)",
                otherPerson,
                100
            )
        });
        calls[1] = Call({
            target: address(mockContract),
            value: 0,
            data: abi.encodeWithSignature("succeed()")
        });
        calls[2] = Call({
            target: address(mockContract),
            value: 0,
            data: abi.encodeWithSignature("returnData()")
        });

        uint256 balanceBefore = tokenA.balanceOf(otherPerson);

        vm.prank(address(portal));
        bytes[] memory results = executor.execute(calls);

        uint256 balanceAfter = tokenA.balanceOf(otherPerson);

        assertEq(balanceAfter, balanceBefore + 100);
        assertTrue(abi.decode(results[0], (bool)));
        assertTrue(abi.decode(results[1], (bool)));
        assertEq(results[2], abi.encode(uint256(42), "test"));
    }
}

contract MockContract {
    receive() external payable {}

    function fail() external pure {
        revert("Contract failed");
    }

    function succeed() external pure returns (bool) {
        return true;
    }

    function receiveEther() external payable {
        require(msg.value > 0, "No value sent");
    }

    function returnData() external pure returns (uint256, string memory) {
        return (42, "test");
    }
}
