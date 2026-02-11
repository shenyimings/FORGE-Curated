// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";

import {LikwidVault} from "../src/LikwidVault.sol";
import {LikwidLendPosition} from "../src/LikwidLendPosition.sol";
import {LikwidPairPosition} from "../src/LikwidPairPosition.sol";
import {LikwidMarginPosition} from "../src/LikwidMarginPosition.sol";
import {IBasePositionManager} from "../src/interfaces/IBasePositionManager.sol";
import {ILendPositionManager} from "../src/interfaces/ILendPositionManager.sol";
import {IMarginPositionManager} from "../src/interfaces/IMarginPositionManager.sol";


import {PoolKey} from "../src/types/PoolKey.sol";
import {Currency, CurrencyLibrary} from "../src/types/Currency.sol";
import {PoolIdLibrary} from "../src/types/PoolId.sol";

import {ReservesLibrary} from "../src/types/Reserves.sol";
import {LendPosition} from "../src/libraries/LendPosition.sol";


contract LikwidLendPositionTest is Test {
    using CurrencyLibrary for Currency;
    using PoolIdLibrary for PoolKey;

    LikwidVault vault;
    LikwidLendPosition lendPositionManager;
    LikwidPairPosition pairPositionManager;
    LikwidMarginPosition marginPositionManager;
    PoolKey key;
    PoolKey keyNative;
    MockERC20 token0;
    MockERC20 token1;
    Currency currency0;
    Currency currency1;

    receive() external payable {}

    function setUp() public {
        // Deploy Vault and Position Manager
        vault = new LikwidVault(address(this));
        lendPositionManager = new LikwidLendPosition(address(this), vault);
        pairPositionManager = new LikwidPairPosition(address(this), vault);
        marginPositionManager = new LikwidMarginPosition(address(this), vault);

        // The test contract is the vault's controller to settle balances
        vault.setMarginController(address(marginPositionManager));

        // Deploy mock tokens
        address tokenA = address(new MockERC20("TokenA", "TKNA", 18));
        address tokenB = address(new MockERC20("TokenB", "TKNB", 18));

        // Ensure currency order
        if (tokenA < tokenB) {
            token0 = MockERC20(tokenA);
            token1 = MockERC20(tokenB);
        } else {
            token0 = MockERC20(tokenB);
            token1 = MockERC20(tokenA);
        }

        // Wrap tokens into Currency type
        currency0 = Currency.wrap(address(token0));
        currency1 = Currency.wrap(address(token1));

        // Approve the vault to pull funds from this test contract
        token0.approve(address(vault), type(uint256).max);
        token1.approve(address(vault), type(uint256).max);
        token0.approve(address(lendPositionManager), type(uint256).max);
        token1.approve(address(lendPositionManager), type(uint256).max);
        token0.approve(address(pairPositionManager), type(uint256).max);
        token1.approve(address(pairPositionManager), type(uint256).max);
        token0.approve(address(marginPositionManager), type(uint256).max);
        token1.approve(address(marginPositionManager), type(uint256).max);

        uint24 fee = 3000; // 0.3%
        key = PoolKey({currency0: currency0, currency1: currency1, fee: fee});
        vault.initialize(key);

        uint256 amount0ToAdd = 1000e18;
        uint256 amount1ToAdd = 2000e18;
        token0.mint(address(this), amount0ToAdd);
        token1.mint(address(this), amount1ToAdd);
        pairPositionManager.addLiquidity(key, amount0ToAdd, amount1ToAdd, 0, 0);

        keyNative = PoolKey({currency0: CurrencyLibrary.ADDRESS_ZERO, currency1: currency1, fee: fee});
        vault.initialize(keyNative);
        token1.mint(address(this), amount1ToAdd);
        pairPositionManager.addLiquidity{value: amount0ToAdd}(keyNative, amount0ToAdd, amount1ToAdd, 0, 0);
    }

    function testAddLendingForZero() public {
        uint256 amount = 1e18;
        token0.mint(address(this), amount);

        uint256 tokenId = lendPositionManager.addLending(key, false, address(this), amount);

        assertTrue(tokenId > 0);

        LendPosition.State memory position = lendPositionManager.getPositionState(tokenId);
        assertTrue(position.lendAmount > 0);
        assertEq(position.lendAmount, amount, "position.lendAmount==amount");
    }

    function testDepositForZero() public {
        uint256 amount = 1e18;
        token0.mint(address(this), amount);

        uint256 tokenId = lendPositionManager.addLending(key, false, address(this), 0);

        lendPositionManager.deposit(tokenId, amount);

        LendPosition.State memory position = lendPositionManager.getPositionState(tokenId);
        assertTrue(position.lendAmount > 0);
        assertEq(position.lendAmount, amount, "position.lendAmount==amount");
    }

    function testWithdrawForZero() public {
        uint256 amount = 1e18;
        token0.mint(address(this), amount);

        uint256 tokenId = lendPositionManager.addLending(key, false, address(this), amount);

        LendPosition.State memory positionBefore = lendPositionManager.getPositionState(tokenId);

        lendPositionManager.withdraw(tokenId, amount / 2);

        LendPosition.State memory positionAfter = lendPositionManager.getPositionState(tokenId);
        console.log("positionAfter.lendAmount:", positionAfter.lendAmount);

        assertTrue(
            positionAfter.lendAmount < positionBefore.lendAmount, "position.lendAmount should be less after withdraw"
        );
        address liquidator = makeAddr("liquidator");
        vm.startPrank(liquidator);
        token0.mint(liquidator, amount);
        token0.approve(address(lendPositionManager), amount);
        uint256 tokenId02 = lendPositionManager.addLending(key, false, liquidator, amount);
        assertNotEq(tokenId, tokenId02);
        LendPosition.State memory position02 = lendPositionManager.getPositionState(tokenId02);
        assertTrue(position02.lendAmount == amount);
        vm.stopPrank();
        vm.expectRevert(LendPosition.WithdrawOverflow.selector);
        lendPositionManager.withdraw(tokenId, amount);
    }

    function testGetPositionStateForZero() public {
        uint256 amount = 1e18;
        token0.mint(address(this), amount);

        uint256 tokenId = lendPositionManager.addLending(key, false, address(this), amount);

        LendPosition.State memory position = lendPositionManager.getPositionState(tokenId);

        assertEq(position.lendAmount, amount, "position.lendAmount==amount");
    }

    function testMirrorExactInputToken10() public {
        uint256 marginAmount = 1e18;
        token1.mint(address(this), marginAmount);

        IMarginPositionManager.CreateParams memory marginParams = IMarginPositionManager.CreateParams({
            marginForOne: true, // margin with token1, borrow token0
            leverage: 2,
            marginAmount: uint128(marginAmount),
            borrowAmount: 0,
            borrowAmountMax: 0,
            recipient: address(this),
            deadline: block.timestamp
        });

        (uint256 marginTokenId, uint256 borrowAmount,) = marginPositionManager.addMargin(key, marginParams);
        assertTrue(marginTokenId > 0, "marginTokenId should be greater than 0");
        assertTrue(borrowAmount > 0, "borrowAmount should be greater than 0");

        uint256 amountIn = 0.1e18;
        token1.mint(address(this), amountIn);

        uint256 tokenId = lendPositionManager.addLending(key, false, address(this), 0);

        LendPosition.State memory positionBefore = lendPositionManager.getPositionState(tokenId);
        assertEq(positionBefore.lendAmount, 0, "lendAmount should be zero");
        // swap mirror token0
        ILendPositionManager.SwapInputParams memory params = ILendPositionManager.SwapInputParams({
            poolId: key.toId(),
            zeroForOne: false,
            tokenId: tokenId,
            amountIn: amountIn,
            amountOutMin: 0,
            deadline: block.timestamp
        });

        (,, uint256 amountOut) = lendPositionManager.exactInput(params);

        assertTrue(amountOut > 0, "amountOut should be greater than 0");

        LendPosition.State memory positionAfter = lendPositionManager.getPositionState(tokenId);

        assertEq(positionAfter.lendAmount, amountOut, "lendAmount should be amountOut");
    }

    function testMirrorExactOutputToken10() public {
        uint256 marginAmount = 1e18;
        token1.mint(address(this), marginAmount);

        IMarginPositionManager.CreateParams memory marginParams = IMarginPositionManager.CreateParams({
            marginForOne: true, // margin with token1, borrow token0
            leverage: 2,
            marginAmount: uint128(marginAmount),
            borrowAmount: 0,
            borrowAmountMax: 0,
            recipient: address(this),
            deadline: block.timestamp
        });

        (uint256 marginTokenId, uint256 borrowAmount,) = marginPositionManager.addMargin(key, marginParams);
        assertTrue(marginTokenId > 0, "marginTokenId should be greater than 0");
        assertTrue(borrowAmount > 0, "borrowAmount should be greater than 0");

        uint256 amountOut = 1e18;
        token1.mint(address(this), amountOut * 10);

        uint256 tokenId = lendPositionManager.addLending(key, false, address(this), 0);

        LendPosition.State memory positionBefore = lendPositionManager.getPositionState(tokenId);
        assertEq(positionBefore.lendAmount, 0, "positionBefore.lendAmount should be zero");
        // swap mirror token0
        ILendPositionManager.SwapOutputParams memory params = ILendPositionManager.SwapOutputParams({
            poolId: key.toId(),
            zeroForOne: false,
            tokenId: tokenId,
            amountInMax: 0,
            amountOut: amountOut,
            deadline: block.timestamp
        });

        (,, uint256 amountInResult) = lendPositionManager.exactOutput(params);

        assertTrue(amountInResult > 0, "amountIn should be greater than 0");

        LendPosition.State memory positionAfter = lendPositionManager.getPositionState(tokenId);

        assertEq(positionAfter.lendAmount, amountOut, "lendAmount should be amountOut");
    }

    function testMirrorExactInputToken01() public {
        uint256 marginAmount = 1e18;
        token0.mint(address(this), marginAmount);

        bool marginForOne = false; // margin with token0, borrow token1
        IMarginPositionManager.CreateParams memory marginParams = IMarginPositionManager.CreateParams({
            marginForOne: marginForOne,
            leverage: 2,
            marginAmount: uint128(marginAmount),
            borrowAmount: 0,
            borrowAmountMax: 0,
            recipient: address(this),
            deadline: block.timestamp
        });

        (uint256 marginTokenId, uint256 borrowAmount,) = marginPositionManager.addMargin(key, marginParams);
        assertTrue(marginTokenId > 0, "marginTokenId should be greater than 0");
        assertTrue(borrowAmount > 0, "borrowAmount should be greater than 0");

        uint256 amountIn = 0.1e18;
        token0.mint(address(this), amountIn);

        uint256 tokenId = lendPositionManager.addLending(key, true, address(this), 0);

        LendPosition.State memory positionBefore = lendPositionManager.getPositionState(tokenId);
        assertEq(positionBefore.lendAmount, 0, "lendAmount should be zero");

        bool zeroForOne = true; // swap mirror token1
        ILendPositionManager.SwapInputParams memory params = ILendPositionManager.SwapInputParams({
            poolId: key.toId(),
            zeroForOne: zeroForOne,
            tokenId: tokenId,
            amountIn: amountIn,
            amountOutMin: 0,
            deadline: block.timestamp
        });

        (,, uint256 amountOut) = lendPositionManager.exactInput(params);

        assertTrue(amountOut > 0, "amountOut should be greater than 0");

        LendPosition.State memory positionAfter = lendPositionManager.getPositionState(tokenId);

        assertEq(positionAfter.lendAmount, amountOut, "lendAmount should be amountOut");
    }

    function testMirrorExactOutputToken01() public {
        uint256 marginAmount = 1e18;
        token0.mint(address(this), marginAmount);

        bool marginForOne = false; // margin with token0, borrow token1
        IMarginPositionManager.CreateParams memory marginParams = IMarginPositionManager.CreateParams({
            marginForOne: marginForOne,
            leverage: 2,
            marginAmount: uint128(marginAmount),
            borrowAmount: 0,
            borrowAmountMax: 0,
            recipient: address(this),
            deadline: block.timestamp
        });

        (uint256 marginTokenId, uint256 borrowAmount,) = marginPositionManager.addMargin(key, marginParams);
        assertTrue(marginTokenId > 0, "marginTokenId should be greater than 0");
        assertTrue(borrowAmount > 0, "borrowAmount should be greater than 0");

        uint256 amountOut = 1e18;
        token0.mint(address(this), amountOut * 10);

        uint256 tokenId = lendPositionManager.addLending(key, true, address(this), 0);

        LendPosition.State memory positionBefore = lendPositionManager.getPositionState(tokenId);
        assertEq(positionBefore.lendAmount, 0, "positionBefore.lendAmount should be zero");

        bool zeroForOne = true; // swap mirror token1
        ILendPositionManager.SwapOutputParams memory params = ILendPositionManager.SwapOutputParams({
            poolId: key.toId(),
            zeroForOne: zeroForOne,
            tokenId: tokenId,
            amountInMax: 0,
            amountOut: amountOut,
            deadline: block.timestamp
        });

        (,, uint256 amountInResult) = lendPositionManager.exactOutput(params);

        assertTrue(amountInResult > 0, "amountIn should be greater than 0");

        LendPosition.State memory positionAfter = lendPositionManager.getPositionState(tokenId);

        assertEq(positionAfter.lendAmount, amountOut, "lendAmount should be amountOut");
    }

    function testAddLendingForOne() public {
        uint256 amount = 1e18;
        token1.mint(address(this), amount);

        uint256 tokenId = lendPositionManager.addLending(key, true, address(this), amount);

        assertTrue(tokenId > 0);

        LendPosition.State memory position = lendPositionManager.getPositionState(tokenId);
        assertTrue(position.lendAmount > 0);
        assertEq(position.lendAmount, amount, "position.lendAmount==amount");
    }

    function testDepositForOne() public {
        uint256 amount = 1e18;
        token1.mint(address(this), amount);

        uint256 tokenId = lendPositionManager.addLending(key, true, address(this), 0);

        lendPositionManager.deposit(tokenId, amount);

        LendPosition.State memory position = lendPositionManager.getPositionState(tokenId);
        assertTrue(position.lendAmount > 0);
        assertEq(position.lendAmount, amount, "position.lendAmount==amount");
    }

    function testWithdrawForOne() public {
        uint256 amount = 1e18;
        token1.mint(address(this), amount);

        uint256 tokenId = lendPositionManager.addLending(key, true, address(this), amount);

        LendPosition.State memory positionBefore = lendPositionManager.getPositionState(tokenId);

        lendPositionManager.withdraw(tokenId, amount / 2);

        LendPosition.State memory positionAfter = lendPositionManager.getPositionState(tokenId);
        console.log("positionAfter.lendAmount:", positionAfter.lendAmount);

        assertTrue(
            positionAfter.lendAmount < positionBefore.lendAmount, "position.lendAmount should be less after withdraw"
        );
        address liquidator = makeAddr("liquidator");
        vm.startPrank(liquidator);
        token1.mint(liquidator, amount);
        token1.approve(address(lendPositionManager), amount);
        uint256 tokenId02 = lendPositionManager.addLending(key, true, liquidator, amount);
        assertNotEq(tokenId, tokenId02);
        LendPosition.State memory position02 = lendPositionManager.getPositionState(tokenId02);
        assertTrue(position02.lendAmount == amount);
        vm.stopPrank();
        vm.expectRevert(LendPosition.WithdrawOverflow.selector);
        lendPositionManager.withdraw(tokenId, amount);
    }

    function testGetPositionStateForOne() public {
        uint256 amount = 1e18;
        token1.mint(address(this), amount);

        uint256 tokenId = lendPositionManager.addLending(key, true, address(this), amount);

        LendPosition.State memory position = lendPositionManager.getPositionState(tokenId);

        assertEq(position.lendAmount, amount, "position.lendAmount==amount");
    }

    function testAddLendingForNative() public {
        uint256 amount = 1e18;
        uint256 tokenId = lendPositionManager.addLending{value: amount}(keyNative, false, address(this), amount);

        assertTrue(tokenId > 0);

        LendPosition.State memory position = lendPositionManager.getPositionState(tokenId);
        assertTrue(position.lendAmount > 0);
        assertEq(position.lendAmount, amount, "position.lendAmount==amount");
    }

    function testAddLendingForOneNative() public {
        uint256 amount = 1e18;
        token1.mint(address(this), amount);

        uint256 tokenId = lendPositionManager.addLending(keyNative, true, address(this), amount);

        assertTrue(tokenId > 0);

        LendPosition.State memory position = lendPositionManager.getPositionState(tokenId);
        assertTrue(position.lendAmount > 0);
        assertEq(position.lendAmount, amount, "position.lendAmount==amount");
    }

    function testDepositForNative() public {
        uint256 amount = 1e18;

        uint256 tokenId = lendPositionManager.addLending(keyNative, false, address(this), 0);

        lendPositionManager.deposit{value: amount}(tokenId, amount);

        LendPosition.State memory position = lendPositionManager.getPositionState(tokenId);
        assertTrue(position.lendAmount > 0);
        assertEq(position.lendAmount, amount, "position.lendAmount==amount");
    }

    function testDepositForOneNative() public {
        uint256 amount = 1e18;
        token1.mint(address(this), amount);

        uint256 tokenId = lendPositionManager.addLending(keyNative, true, address(this), 0);

        lendPositionManager.deposit(tokenId, amount);

        LendPosition.State memory position = lendPositionManager.getPositionState(tokenId);
        assertTrue(position.lendAmount > 0);
        assertEq(position.lendAmount, amount, "position.lendAmount==amount");
    }

    function testWithdrawForNative() public {
        uint256 amount = 1e18;

        uint256 tokenId = lendPositionManager.addLending{value: amount}(keyNative, false, address(this), amount);

        lendPositionManager.withdraw(tokenId, amount / 2);

        vm.expectRevert(ReservesLibrary.NotEnoughReserves.selector);
        lendPositionManager.withdraw(tokenId, amount);

        lendPositionManager.addLending{value: amount}(keyNative, false, address(this), amount);

        vm.expectRevert(LendPosition.WithdrawOverflow.selector);
        lendPositionManager.withdraw(tokenId, amount);
    }

    function testWithdrawForOneNative() public {
        uint256 amount = 1e18;
        token1.mint(address(this), amount);

        uint256 tokenId = lendPositionManager.addLending(keyNative, true, address(this), amount);

        LendPosition.State memory positionBefore = lendPositionManager.getPositionState(tokenId);

        lendPositionManager.withdraw(tokenId, amount / 2);

        LendPosition.State memory positionAfter = lendPositionManager.getPositionState(tokenId);
        console.log("positionAfter.lendAmount:", positionAfter.lendAmount);

        assertTrue(
            positionAfter.lendAmount < positionBefore.lendAmount, "position.lendAmount should be less after withdraw"
        );
        address liquidator = makeAddr("liquidator");
        vm.startPrank(liquidator);
        token1.mint(liquidator, amount);
        token1.approve(address(lendPositionManager), amount);
        uint256 tokenId02 = lendPositionManager.addLending(keyNative, true, liquidator, amount);
        assertNotEq(tokenId, tokenId02);
        LendPosition.State memory position02 = lendPositionManager.getPositionState(tokenId02);
        assertTrue(position02.lendAmount == amount);
        vm.stopPrank();
        vm.expectRevert(LendPosition.WithdrawOverflow.selector);
        lendPositionManager.withdraw(tokenId, amount);
    }

    function testGetPositionStateForNative() public {
        uint256 amount = 1e18;
        uint256 tokenId = lendPositionManager.addLending{value: amount}(keyNative, false, address(this), amount);

        LendPosition.State memory position = lendPositionManager.getPositionState(tokenId);

        assertEq(position.lendAmount, amount, "position.lendAmount==amount");
    }

    function testGetPositionStateForOneNative() public {
        uint256 amount = 1e18;
        token1.mint(address(this), amount);

        uint256 tokenId = lendPositionManager.addLending(keyNative, true, address(this), amount);

        LendPosition.State memory position = lendPositionManager.getPositionState(tokenId);

        assertEq(position.lendAmount, amount, "position.lendAmount==amount");
    }

    function test_RevertIf_UnauthorizedAccess() public {
        uint256 amount = 1e18;
        token0.mint(address(this), amount);
        uint256 tokenId = lendPositionManager.addLending(key, false, address(this), amount);

        address unauthorizedUser = makeAddr("unauthorizedUser");
        vm.startPrank(unauthorizedUser);

        bytes4 expectedError = IBasePositionManager.NotOwner.selector;

        vm.expectRevert(expectedError);
        lendPositionManager.deposit(tokenId, amount);

        vm.expectRevert(expectedError);
        lendPositionManager.withdraw(tokenId, amount);

        ILendPositionManager.SwapInputParams memory swapParams = ILendPositionManager.SwapInputParams({
            poolId: key.toId(),
            zeroForOne: false,
            tokenId: tokenId,
            amountIn: amount,
            amountOutMin: 0,
            deadline: block.timestamp
        });
        vm.expectRevert(expectedError);
        lendPositionManager.exactInput(swapParams);

        ILendPositionManager.SwapOutputParams memory outputParams = ILendPositionManager.SwapOutputParams({
            poolId: key.toId(),
            zeroForOne: false,
            tokenId: tokenId,
            amountOut: amount,
            amountInMax: type(uint256).max,
            deadline: block.timestamp
        });
        vm.expectRevert(expectedError);
        lendPositionManager.exactOutput(outputParams);

        vm.stopPrank();
    }
}
