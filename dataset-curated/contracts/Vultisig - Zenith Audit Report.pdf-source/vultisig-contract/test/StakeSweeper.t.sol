// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {StakeSweeper} from "../contracts/StakeSweeper.sol";
import {MockERC1363} from "./mocks/MockERC1363.sol";
import {MockUniswapRouter} from "./mocks/MockUniswapRouter.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract StakeSweeperTest is Test {
    StakeSweeper public sweeper;
    MockERC1363 public rewardToken;
    MockERC1363 public tokenToSweep;
    MockUniswapRouter public router;

    address public owner = makeAddr("owner");
    address public user = makeAddr("user");
    uint256 public constant INITIAL_SUPPLY = 1_000_000 ether;

    event RouterSet(address indexed router);
    event MinOutPercentageSet(uint8 percentage);
    event TokenSwept(address indexed token, uint256 amountIn, uint256 amountOut);

    function setUp() public {
        vm.startPrank(owner);

        // Deploy tokens
        rewardToken = new MockERC1363(INITIAL_SUPPLY);
        tokenToSweep = new MockERC1363(INITIAL_SUPPLY);

        // Deploy mock router
        router = new MockUniswapRouter();

        // Deploy sweeper
        sweeper = new StakeSweeper(address(rewardToken), address(router));

        // Fund the router with reward tokens so it can perform swaps
        rewardToken.transfer(address(router), 10000 ether);

        vm.stopPrank();
    }

    function test_Deployment() public view {
        assertEq(address(sweeper.rewardToken()), address(rewardToken));
        assertEq(address(sweeper.defaultRouter()), address(router));
        assertEq(sweeper.minOutPercentage(), 90);
    }

    function test_RevertDeploymentWithZeroAddress() public {
        vm.startPrank(owner);

        vm.expectRevert("StakeSweeper: reward token is zero address");
        new StakeSweeper(address(0), address(router));

        vm.expectRevert("StakeSweeper: router is zero address");
        new StakeSweeper(address(rewardToken), address(0));

        vm.stopPrank();
    }

    function test_SetRouter() public {
        address newRouter = makeAddr("newRouter");

        vm.startPrank(owner);

        vm.expectEmit(true, false, false, false);
        emit RouterSet(newRouter);
        sweeper.setRouter(newRouter);

        assertEq(sweeper.defaultRouter(), newRouter);
        vm.stopPrank();
    }

    function test_RevertSetRouterNonOwner() public {
        address newRouter = makeAddr("newRouter");

        vm.startPrank(user);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user));
        sweeper.setRouter(newRouter);
        vm.stopPrank();
    }

    function test_SetMinOutPercentage() public {
        uint8 newPercentage = 95;

        vm.startPrank(owner);

        vm.expectEmit(false, false, false, true);
        emit MinOutPercentageSet(newPercentage);
        sweeper.setMinOutPercentage(newPercentage);

        assertEq(sweeper.minOutPercentage(), newPercentage);
        vm.stopPrank();
    }

    function test_RevertSetMinOutPercentageInvalid() public {
        vm.startPrank(owner);

        vm.expectRevert("StakeSweeper: percentage must be between 1-100");
        sweeper.setMinOutPercentage(0);

        vm.expectRevert("StakeSweeper: percentage must be between 1-100");
        sweeper.setMinOutPercentage(101);

        vm.stopPrank();
    }

    function test_Sweep() public {
        uint256 amountToSweep = 100 ether;
        address recipient = makeAddr("recipient");

        vm.startPrank(owner);
        // Transfer tokens to sweeper
        tokenToSweep.transfer(address(sweeper), amountToSweep);
        vm.stopPrank();

        vm.startPrank(user);

        uint256 amountOut = sweeper.sweep(address(tokenToSweep), recipient);

        assertEq(amountOut, amountToSweep * router.exchangeRate());
        assertEq(rewardToken.balanceOf(recipient), amountToSweep * router.exchangeRate());
        assertEq(tokenToSweep.balanceOf(address(sweeper)), 0);

        vm.stopPrank();
    }

    function test_RevertSweepRewardToken() public {
        vm.startPrank(user);

        vm.expectRevert("StakeSweeper: cannot sweep reward token");
        sweeper.sweep(address(rewardToken), user);

        vm.stopPrank();
    }

    function test_RevertSweepZeroRecipient() public {
        vm.startPrank(user);

        vm.expectRevert("StakeSweeper: recipient is zero address");
        sweeper.sweep(address(tokenToSweep), address(0));

        vm.stopPrank();
    }

    function test_RevertSweepNoBalance() public {
        address emptyToken = address(new MockERC1363(0));

        vm.startPrank(user);

        vm.expectRevert("StakeSweeper: no tokens to sweep");
        sweeper.sweep(emptyToken, user);

        vm.stopPrank();
    }

    function test_SweepWithSlippage() public {
        uint256 amountToSweep = 100 ether;
        uint256 expectedOutput = router.exchangeRate() * amountToSweep;
        address recipient = makeAddr("recipient");

        vm.startPrank(owner);
        tokenToSweep.transfer(address(sweeper), amountToSweep);
        vm.stopPrank();

        vm.startPrank(user);

        uint256 amountOut = sweeper.sweep(address(tokenToSweep), recipient);

        assertEq(amountOut, expectedOutput);
        assertEq(rewardToken.balanceOf(recipient), expectedOutput);

        vm.stopPrank();
    }

    function test_ReinvestZeroBalance() public {
        vm.startPrank(user);

        // Try to reinvest when there are no reward tokens in the contract
        vm.expectRevert("StakeSweeper: amount to swap must be greater than 0");
        sweeper.reinvest(address(tokenToSweep), user);

        vm.stopPrank();
    }

    function test_SwapWithFailedQuote() public {
        uint256 amountToSweep = 100 ether;
        address recipient = makeAddr("recipient");

        // Setup router to fail quote
        router.setFailQuote(true);

        vm.startPrank(owner);
        tokenToSweep.transfer(address(sweeper), amountToSweep);
        vm.stopPrank();

        vm.startPrank(user);
        // Should still succeed with minimum amount out of 1
        uint256 amountOut = sweeper.sweep(address(tokenToSweep), recipient);
        assertGt(amountOut, 0);
        vm.stopPrank();
    }

    function test_SwapWithInvalidQuoteLength() public {
        uint256 amountToSweep = 100 ether;
        address recipient = makeAddr("recipient");

        // Setup router to return invalid quote length
        router.setInvalidQuoteLength(true);

        vm.startPrank(owner);
        tokenToSweep.transfer(address(sweeper), amountToSweep);
        vm.stopPrank();

        vm.startPrank(user);
        // Should still succeed with minimum amount out of 1
        uint256 amountOut = sweeper.sweep(address(tokenToSweep), recipient);
        assertGt(amountOut, 0);
        vm.stopPrank();
    }

    function test_RevertSetRouterZeroAddress() public {
        vm.startPrank(owner);
        vm.expectRevert("StakeSweeper: router is zero address");
        sweeper.setRouter(address(0));
        vm.stopPrank();
    }

    function test_SwapWithDifferentMinOutPercentages() public {
        uint256 amountToSweep = 100 ether;
        address recipient = makeAddr("recipient");

        vm.startPrank(owner);
        tokenToSweep.transfer(address(sweeper), amountToSweep);

        // Test with different min out percentages
        sweeper.setMinOutPercentage(95); // Higher percentage
        vm.stopPrank();

        vm.startPrank(user);
        uint256 amountOut = sweeper.sweep(address(tokenToSweep), recipient);
        assertEq(amountOut, amountToSweep * router.exchangeRate());
        vm.stopPrank();

        // Setup for next test
        vm.startPrank(owner);
        tokenToSweep.transfer(address(sweeper), amountToSweep);
        sweeper.setMinOutPercentage(1); // Minimum percentage
        vm.stopPrank();

        vm.startPrank(user);
        amountOut = sweeper.sweep(address(tokenToSweep), recipient);
        assertEq(amountOut, amountToSweep * router.exchangeRate());
        vm.stopPrank();
    }

    function test_RevertSetMinOutPercentageNonOwner() public {
        vm.startPrank(user);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user));
        sweeper.setMinOutPercentage(95);
        vm.stopPrank();
    }
}
