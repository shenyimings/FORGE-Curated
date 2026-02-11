// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";

import {LikwidVault} from "../src/LikwidVault.sol";
import {LikwidMarginPosition} from "../src/LikwidMarginPosition.sol";
import {LikwidPairPosition} from "../src/LikwidPairPosition.sol";
import {LikwidHelper} from "./utils/LikwidHelper.sol";
import {IMarginPositionManager} from "../src/interfaces/IMarginPositionManager.sol";
import {IVault} from "../src/interfaces/IVault.sol";
import {IUnlockCallback} from "../src/interfaces/callback/IUnlockCallback.sol";
import {PoolKey} from "../src/types/PoolKey.sol";
import {Currency, CurrencyLibrary} from "../src/types/Currency.sol";
import {PoolIdLibrary} from "../src/types/PoolId.sol";
import {MarginPosition} from "../src/libraries/MarginPosition.sol";
import {BalanceDelta} from "../src/types/BalanceDelta.sol";
import {MarginLevels, MarginLevelsLibrary} from "../src/types/MarginLevels.sol";

import {LikwidChecker} from "./utils/LikwidChecker.sol";

contract LikwidMarginPositionTest is Test, IUnlockCallback {
    using CurrencyLibrary for Currency;
    using PoolIdLibrary for PoolKey;
    using MarginLevelsLibrary for MarginLevels;

    event MarginLevelChanged(bytes32 oldMarginLevel, bytes32 newMarginLevel);
    event MarginFeeChanged(uint24 oldMarginFee, uint24 newMarginFee);

    LikwidVault vault;
    LikwidMarginPosition marginPositionManager;
    LikwidPairPosition pairPositionManager;
    LikwidHelper helper;
    PoolKey key;
    PoolKey keyNative;
    PoolKey keyLowFee;
    MockERC20 token0;
    MockERC20 token1;
    Currency currency0;
    Currency currency1;

    function setUp() public {
        // Deploy Vault and Position Manager
        vault = new LikwidVault(address(this));
        marginPositionManager = new LikwidMarginPosition(address(this), vault);
        pairPositionManager = new LikwidPairPosition(address(this), vault);
        helper = new LikwidHelper(address(this), vault);

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

        // The test contract is the vault's controller to settle balances
        vault.setMarginController(address(marginPositionManager));

        // Approve the vault to pull funds from this test contract
        token0.approve(address(vault), type(uint256).max);
        token1.approve(address(vault), type(uint256).max);
        token0.approve(address(marginPositionManager), type(uint256).max);
        token1.approve(address(marginPositionManager), type(uint256).max);
        token0.approve(address(pairPositionManager), type(uint256).max);
        token1.approve(address(pairPositionManager), type(uint256).max);

        uint24 fee = 3000; // 0.3%
        key = PoolKey({currency0: currency0, currency1: currency1, fee: fee});
        vault.initialize(key);

        keyLowFee = PoolKey({currency0: currency0, currency1: currency1, fee: 1000});
        vault.initialize(keyLowFee);

        keyNative = PoolKey({currency0: CurrencyLibrary.ADDRESS_ZERO, currency1: currency1, fee: fee});
        vault.initialize(keyNative);

        uint256 amount0ToAdd = 10e18;
        uint256 amount1ToAdd = 20e18;
        token0.mint(address(this), amount0ToAdd);
        token1.mint(address(this), amount1ToAdd);
        pairPositionManager.addLiquidity(key, amount0ToAdd, amount1ToAdd, 0, 0);

        token1.mint(address(this), amount1ToAdd);
        pairPositionManager.addLiquidity{value: amount0ToAdd}(keyNative, amount0ToAdd, amount1ToAdd, 0, 0);
    }

    function unlockCallback(bytes calldata data) external returns (bytes memory) {
        (bytes4 selector, bytes memory params) = abi.decode(data, (bytes4, bytes));

        if (selector == this.swap_callback.selector) {
            (PoolKey memory _key, IVault.SwapParams memory swapParams) =
                abi.decode(params, (PoolKey, IVault.SwapParams));

            (BalanceDelta delta,,) = vault.swap(_key, swapParams);

            // Settle the balances
            if (delta.amount0() < 0) {
                vault.sync(_key.currency0);
                token0.transfer(address(vault), uint256(-int256(delta.amount0())));
                vault.settle();
            } else if (delta.amount0() > 0) {
                vault.take(_key.currency0, address(this), uint256(int256(delta.amount0())));
            }

            if (delta.amount1() < 0) {
                vault.sync(_key.currency1);
                token1.transfer(address(vault), uint256(-int256(delta.amount1())));
                vault.settle();
            } else if (delta.amount1() > 0) {
                vault.take(_key.currency1, address(this), uint256(int256(delta.amount1())));
            }
        }
        return "";
    }

    fallback() external payable {}
    receive() external payable {}

    function swap_callback(PoolKey memory, IVault.SwapParams memory) external pure {}

    function testAddMargin() public {
        uint256 marginAmount = 0.1e18;
        token0.mint(address(this), marginAmount);

        IMarginPositionManager.CreateParams memory params = IMarginPositionManager.CreateParams({
            marginForOne: false, // margin with token0, borrow token1
            leverage: 2,
            marginAmount: uint128(marginAmount),
            borrowAmount: 0,
            borrowAmountMax: 0,
            recipient: address(this),
            deadline: block.timestamp
        });

        (uint256 tokenId, uint256 borrowAmount,) = marginPositionManager.addMargin(key, params);

        assertTrue(tokenId > 0);
        assertTrue(borrowAmount > 0);

        MarginPosition.State memory position = marginPositionManager.getPositionState(tokenId);

        assertEq(position.marginAmount, marginAmount, "position.marginAmount==marginAmount");
        assertEq(position.debtAmount, borrowAmount, "position.debtAmount==borrowAmount");
        LikwidChecker.checkPoolReserves(vault, key);
    }

    function testRepay() public {
        uint256 marginAmount = 0.1e18;
        token0.mint(address(this), marginAmount);

        IMarginPositionManager.CreateParams memory params = IMarginPositionManager.CreateParams({
            marginForOne: false, // margin with token0, borrow token1
            leverage: 2,
            marginAmount: uint128(marginAmount),
            borrowAmount: 0,
            borrowAmountMax: 0,
            recipient: address(this),
            deadline: block.timestamp
        });

        (uint256 tokenId, uint256 borrowAmount,) = marginPositionManager.addMargin(key, params);

        assertTrue(tokenId > 0);
        assertTrue(borrowAmount > 0);

        uint256 repayAmount = borrowAmount / 2;
        token1.mint(address(this), repayAmount);

        MarginPosition.State memory positionBefore = marginPositionManager.getPositionState(tokenId);

        marginPositionManager.repay(tokenId, repayAmount, block.timestamp);

        MarginPosition.State memory positionAfter = marginPositionManager.getPositionState(tokenId);

        assertTrue(
            positionAfter.debtAmount < positionBefore.debtAmount, "position.debtAmount should be less after repay"
        );
        LikwidChecker.checkPoolReserves(vault, key);
    }

    function testClose() public {
        uint256 marginAmount = 0.1e18;
        token0.mint(address(this), marginAmount);

        IMarginPositionManager.CreateParams memory params = IMarginPositionManager.CreateParams({
            marginForOne: false, // margin with token0, borrow token1
            leverage: 2,
            marginAmount: uint128(marginAmount),
            borrowAmount: 0,
            borrowAmountMax: 0,
            recipient: address(this),
            deadline: block.timestamp
        });

        (uint256 tokenId,,) = marginPositionManager.addMargin(key, params);

        marginPositionManager.close(tokenId, 1_000_000, 0, block.timestamp); // close 100%

        MarginPosition.State memory position = marginPositionManager.getPositionState(tokenId);

        assertEq(position.marginAmount, 0, "position.marginAmount should be 0 after close");
        assertEq(position.debtAmount, 0, "position.debtAmount should be 0 after close");
        LikwidChecker.checkPoolReserves(vault, key);
    }

    function testModify() public {
        uint256 marginAmount = 0.1e18;
        token0.mint(address(this), marginAmount);

        IMarginPositionManager.CreateParams memory params = IMarginPositionManager.CreateParams({
            marginForOne: false, // margin with token0, borrow token1
            leverage: 2,
            marginAmount: uint128(marginAmount),
            borrowAmount: 0,
            borrowAmountMax: 0,
            recipient: address(this),
            deadline: block.timestamp
        });

        (uint256 tokenId,,) = marginPositionManager.addMargin(key, params);

        MarginPosition.State memory positionBefore = marginPositionManager.getPositionState(tokenId);

        uint256 modifyAmount = 0.05e18;
        token0.mint(address(this), modifyAmount);
        marginPositionManager.modify(tokenId, int128(int256(modifyAmount)));

        MarginPosition.State memory positionAfter = marginPositionManager.getPositionState(tokenId);

        assertEq(
            positionAfter.marginAmount,
            positionBefore.marginAmount + modifyAmount,
            "position.marginAmount should be increased"
        );
        LikwidChecker.checkPoolReserves(vault, key);
    }

    function testLiquidateCall() public {
        uint256 marginAmount = 0.1e18;
        token0.mint(address(this), marginAmount);

        IMarginPositionManager.CreateParams memory params = IMarginPositionManager.CreateParams({
            marginForOne: false, // margin with token0, borrow token1
            leverage: 4,
            marginAmount: uint128(marginAmount),
            borrowAmount: 0,
            borrowAmountMax: 0,
            recipient: address(this),
            deadline: block.timestamp
        });

        (uint256 tokenId,,) = marginPositionManager.addMargin(key, params);

        // Manipulate price to make position liquidatable
        // Swap a large amount of token0 for token1 to drive the price of token0 down
        uint256 swapAmount = 5e18;
        token0.mint(address(this), swapAmount);

        // Perform swap on the vault
        IVault.SwapParams memory swapParams = IVault.SwapParams({
            zeroForOne: true,
            amountSpecified: -int256(swapAmount),
            useMirror: false,
            salt: bytes32(0)
        });
        bytes memory innerParamsSwap = abi.encode(key, swapParams);
        bytes memory dataSwap = abi.encode(this.swap_callback.selector, innerParamsSwap);
        vault.unlock(dataSwap);

        (bool liquidated,,,) = marginPositionManager.checkLiquidate(tokenId);
        assertTrue(liquidated, "Position should be liquidatable");

        // Liquidate
        address liquidator = makeAddr("liquidator");
        vm.startPrank(liquidator);
        token1.mint(liquidator, 100e18); // give liquidator funds to repay debt
        token1.approve(address(vault), 100e18);
        token1.approve(address(marginPositionManager), 100e18);

        (uint256 profit,) = marginPositionManager.liquidateCall(tokenId);
        vm.stopPrank();

        assertTrue(profit > 0, "Liquidator should make a profit");

        MarginPosition.State memory position = marginPositionManager.getPositionState(tokenId);
        assertEq(position.debtAmount, 0, "position.debtAmount should be 0 after liquidation");
        LikwidChecker.checkPoolReserves(vault, key);
    }

    function testLiquidateBurn() public {
        uint256 marginAmount = 0.1e18;
        token0.mint(address(this), marginAmount);

        IMarginPositionManager.CreateParams memory params = IMarginPositionManager.CreateParams({
            marginForOne: false, // margin with token0, borrow token1
            leverage: 4,
            marginAmount: uint128(marginAmount),
            borrowAmount: 0,
            borrowAmountMax: 0,
            recipient: address(this),
            deadline: block.timestamp
        });

        (uint256 tokenId,,) = marginPositionManager.addMargin(key, params);

        // Manipulate price to make position liquidatable
        // Swap a large amount of token0 for token1 to drive the price of token0 down
        uint256 swapAmount = 5e18;
        token0.mint(address(this), swapAmount);

        // Perform swap on the vault
        IVault.SwapParams memory swapParams = IVault.SwapParams({
            zeroForOne: true,
            amountSpecified: -int256(swapAmount),
            useMirror: false,
            salt: bytes32(0)
        });
        bytes memory innerParamsSwap = abi.encode(key, swapParams);
        bytes memory dataSwap = abi.encode(this.swap_callback.selector, innerParamsSwap);
        vault.unlock(dataSwap);

        (bool liquidated,,,) = marginPositionManager.checkLiquidate(tokenId);
        assertTrue(liquidated, "Position should be liquidatable");

        // Liquidate
        address liquidator = makeAddr("liquidator");
        vm.startPrank(liquidator);

        uint256 profit = marginPositionManager.liquidateBurn(tokenId);
        vm.stopPrank();

        assertTrue(profit > 0, "Liquidator should make a profit");

        MarginPosition.State memory position = marginPositionManager.getPositionState(tokenId);
        assertEq(position.debtAmount, 0, "position.debtAmount should be 0 after liquidation");
        assertEq(position.marginAmount, 0, "position.marginAmount should be 0 after liquidation");
        LikwidChecker.checkPoolReserves(vault, key);
    }

    function testAddMargin_MarginForOneTrue() public {
        uint256 marginAmount = 0.1e18;
        token1.mint(address(this), marginAmount);

        IMarginPositionManager.CreateParams memory params = IMarginPositionManager.CreateParams({
            marginForOne: true, // margin with token1, borrow token0
            leverage: 2,
            marginAmount: uint128(marginAmount),
            borrowAmount: 0,
            borrowAmountMax: 0,
            recipient: address(this),
            deadline: block.timestamp
        });

        (uint256 tokenId, uint256 borrowAmount,) = marginPositionManager.addMargin(key, params);

        assertTrue(tokenId > 0);
        assertTrue(borrowAmount > 0);

        MarginPosition.State memory position = marginPositionManager.getPositionState(tokenId);

        assertEq(position.marginAmount, marginAmount, "position.marginAmount==marginAmount");
        assertEq(position.debtAmount, borrowAmount, "position.debtAmount==borrowAmount");
        assertTrue(position.marginForOne, "position.marginForOne should be true");
        LikwidChecker.checkPoolReserves(vault, key);
    }

    function testAddMargin_NoLeverage() public {
        uint256 marginAmount = 0.1e18;
        token0.mint(address(this), marginAmount);

        IMarginPositionManager.CreateParams memory params = IMarginPositionManager.CreateParams({
            marginForOne: false,
            leverage: 0, // No leverage, just add collateral and borrow
            marginAmount: uint128(marginAmount),
            borrowAmount: 1000, // borrow a small amount
            borrowAmountMax: 1000,
            recipient: address(this),
            deadline: block.timestamp
        });

        (uint256 tokenId, uint256 borrowAmount,) = marginPositionManager.addMargin(key, params);
        assertTrue(tokenId > 0);
        assertEq(borrowAmount, 1000);
        LikwidChecker.checkPoolReserves(vault, key);
    }

    function testAddMargin_MaxLeverage() public {
        MarginLevels newMarginLevels;
        newMarginLevels = newMarginLevels.setMinMarginLevel(1100000);
        newMarginLevels = newMarginLevels.setMinBorrowLevel(1200000);
        newMarginLevels = newMarginLevels.setLiquidateLevel(1050000);
        newMarginLevels = newMarginLevels.setLiquidationRatio(950000);
        newMarginLevels = newMarginLevels.setCallerProfit(10000);
        newMarginLevels = newMarginLevels.setProtocolProfit(5000);
        marginPositionManager.setMarginLevel(MarginLevels.unwrap(newMarginLevels));

        uint256 marginAmount = 0.1e18;
        token0.mint(address(this), marginAmount);

        IMarginPositionManager.CreateParams memory params = IMarginPositionManager.CreateParams({
            marginForOne: false,
            leverage: 5, // MAX_LEVERAGE
            marginAmount: uint128(marginAmount),
            borrowAmount: 0,
            borrowAmountMax: 0,
            recipient: address(this),
            deadline: block.timestamp
        });

        (uint256 tokenId, uint256 borrowAmount,) = marginPositionManager.addMargin(key, params);

        assertTrue(tokenId > 0);
        assertTrue(borrowAmount > 0);
        LikwidChecker.checkPoolReserves(vault, key);
    }

    function testRepay_Full() public {
        uint256 marginAmount = 0.1e18;
        token0.mint(address(this), marginAmount);

        IMarginPositionManager.CreateParams memory params = IMarginPositionManager.CreateParams({
            marginForOne: false,
            leverage: 2,
            marginAmount: uint128(marginAmount),
            borrowAmount: 0,
            borrowAmountMax: 0,
            recipient: address(this),
            deadline: block.timestamp
        });

        (uint256 tokenId, uint256 borrowAmount,) = marginPositionManager.addMargin(key, params);

        token1.mint(address(this), borrowAmount);
        marginPositionManager.repay(tokenId, borrowAmount, block.timestamp);

        MarginPosition.State memory positionAfter = marginPositionManager.getPositionState(tokenId);

        assertTrue(positionAfter.debtAmount < 10, "position.debtAmount should be close to 0 after full repay");
        LikwidChecker.checkPoolReserves(vault, key);
    }

    function testClose_Partial() public {
        uint256 marginAmount = 0.1e18;
        token0.mint(address(this), marginAmount);

        IMarginPositionManager.CreateParams memory params = IMarginPositionManager.CreateParams({
            marginForOne: false,
            leverage: 2,
            marginAmount: uint128(marginAmount),
            borrowAmount: 0,
            borrowAmountMax: 0,
            recipient: address(this),
            deadline: block.timestamp
        });

        (uint256 tokenId,,) = marginPositionManager.addMargin(key, params);
        MarginPosition.State memory positionBefore = marginPositionManager.getPositionState(tokenId);

        marginPositionManager.close(tokenId, 500_000, 0, block.timestamp); // close 50%

        MarginPosition.State memory positionAfter = marginPositionManager.getPositionState(tokenId);

        assertApproxEqAbs(
            positionAfter.marginAmount, positionBefore.marginAmount / 2, 1, "marginAmount should be halved"
        );
        assertApproxEqAbs(positionAfter.debtAmount, positionBefore.debtAmount / 2, 1, "debtAmount should be halved");
        LikwidChecker.checkPoolReserves(vault, key);
    }

    function testModify_DecreaseCollateral() public {
        uint256 marginAmount = 0.2e18;
        token0.mint(address(this), marginAmount);

        IMarginPositionManager.CreateParams memory params = IMarginPositionManager.CreateParams({
            marginForOne: false,
            leverage: 2,
            marginAmount: uint128(marginAmount),
            borrowAmount: 0,
            borrowAmountMax: 0,
            recipient: address(this),
            deadline: block.timestamp
        });

        (uint256 tokenId,,) = marginPositionManager.addMargin(key, params);
        MarginPosition.State memory positionBefore = marginPositionManager.getPositionState(tokenId);

        int128 modifyAmount = -0.05e18;
        marginPositionManager.modify(tokenId, modifyAmount);

        MarginPosition.State memory positionAfter = marginPositionManager.getPositionState(tokenId);

        assertEq(
            int256(uint256(positionAfter.marginAmount)),
            int256(uint256(positionBefore.marginAmount)) + modifyAmount,
            "position.marginAmount should be decreased"
        );
        LikwidChecker.checkPoolReserves(vault, key);
    }

    function testModify_Fail_BelowMinBorrowLevel() public {
        uint256 marginAmount = 0.1e18;
        token0.mint(address(this), marginAmount);

        IMarginPositionManager.CreateParams memory params = IMarginPositionManager.CreateParams({
            marginForOne: false,
            leverage: 4,
            marginAmount: uint128(marginAmount),
            borrowAmount: 0,
            borrowAmountMax: 0,
            recipient: address(this),
            deadline: block.timestamp
        });

        (uint256 tokenId,,) = marginPositionManager.addMargin(key, params);

        int128 modifyAmount = -0.08e18; // Decrease collateral significantly
        vm.expectRevert(bytes4(keccak256("InvalidLevel()")));
        marginPositionManager.modify(tokenId, modifyAmount);
        LikwidChecker.checkPoolReserves(vault, key);
    }

    function testLiquidate_NotLiquidatable() public {
        uint256 marginAmount = 0.1e18;
        token0.mint(address(this), marginAmount);

        IMarginPositionManager.CreateParams memory params = IMarginPositionManager.CreateParams({
            marginForOne: false,
            leverage: 2,
            marginAmount: uint128(marginAmount),
            borrowAmount: 0,
            borrowAmountMax: 0,
            recipient: address(this),
            deadline: block.timestamp
        });

        (uint256 tokenId,,) = marginPositionManager.addMargin(key, params);

        (bool liquidated,,,) = marginPositionManager.checkLiquidate(tokenId);
        assertFalse(liquidated, "Position should not be liquidatable");

        vm.expectRevert(bytes4(keccak256("PositionNotLiquidated()")));
        marginPositionManager.liquidateCall(tokenId);

        vm.expectRevert(bytes4(keccak256("PositionNotLiquidated()")));
        marginPositionManager.liquidateBurn(tokenId);
        LikwidChecker.checkPoolReserves(vault, key);
    }

    function testSetMarginLevel() public {
        MarginLevels oldLevels = marginPositionManager.marginLevels();
        MarginLevels newMarginLevels;
        newMarginLevels = newMarginLevels.setMinMarginLevel(1200000);
        newMarginLevels = newMarginLevels.setMinBorrowLevel(1500000);
        newMarginLevels = newMarginLevels.setLiquidateLevel(1150000);
        newMarginLevels = newMarginLevels.setLiquidationRatio(900000);
        newMarginLevels = newMarginLevels.setCallerProfit(20000);
        newMarginLevels = newMarginLevels.setProtocolProfit(10000);

        vm.expectEmit(true, true, true, true);
        emit MarginLevelChanged(MarginLevels.unwrap(oldLevels), MarginLevels.unwrap(newMarginLevels));
        marginPositionManager.setMarginLevel(MarginLevels.unwrap(newMarginLevels));

        assertEq(
            MarginLevels.unwrap(marginPositionManager.marginLevels()),
            MarginLevels.unwrap(newMarginLevels),
            "Margin levels should be updated"
        );
        LikwidChecker.checkPoolReserves(vault, key);
    }

    function testSetMarginLevel_NotOwner() public {
        bytes32 newLevels = keccak256(
            abi.encodePacked(
                uint24(1200000), uint24(1500000), uint24(1150000), uint24(900000), uint24(20000), uint24(10000)
            )
        );
        address notOwner = makeAddr("notOwner");
        vm.startPrank(notOwner);
        vm.expectRevert(bytes("UNAUTHORIZED"));
        marginPositionManager.setMarginLevel(newLevels);
        vm.stopPrank();
        LikwidChecker.checkPoolReserves(vault, key);
    }

    function testSetDefaultMarginFee() public {
        uint24 oldFee = marginPositionManager.defaultMarginFee();
        uint24 newFee = 5000; // 0.5%

        vm.expectEmit(true, true, true, true);
        emit MarginFeeChanged(oldFee, newFee);
        marginPositionManager.setDefaultMarginFee(newFee);

        assertEq(marginPositionManager.defaultMarginFee(), newFee, "Default margin fee should be updated");
        LikwidChecker.checkPoolReserves(vault, key);
    }

    function testSetDefaultMarginFee_NotOwner() public {
        uint24 newFee = 5000;
        address notOwner = makeAddr("notOwner");
        vm.startPrank(notOwner);
        vm.expectRevert(bytes("UNAUTHORIZED"));
        marginPositionManager.setDefaultMarginFee(newFee);
        vm.stopPrank();
        LikwidChecker.checkPoolReserves(vault, key);
    }

    function testAddMarginNative() public {
        uint256 marginAmount = 0.1e18;

        IMarginPositionManager.CreateParams memory params = IMarginPositionManager.CreateParams({
            marginForOne: false, // margin with native, borrow token1
            leverage: 2,
            marginAmount: uint128(marginAmount),
            borrowAmount: 0,
            borrowAmountMax: 0,
            recipient: address(this),
            deadline: block.timestamp
        });

        (uint256 tokenId, uint256 borrowAmount,) =
            marginPositionManager.addMargin{value: marginAmount}(keyNative, params);

        assertTrue(tokenId > 0);
        assertTrue(borrowAmount > 0);

        MarginPosition.State memory position = marginPositionManager.getPositionState(tokenId);

        assertEq(position.marginAmount, marginAmount, "position.marginAmount==marginAmount");
        assertEq(position.debtAmount, borrowAmount, "position.debtAmount==borrowAmount");
        LikwidChecker.checkPoolReserves(vault, keyNative);
    }

    function testAddMarginNative_MarginForOneTrue() public {
        uint256 marginAmount = 0.1e18;
        token1.mint(address(this), marginAmount);

        IMarginPositionManager.CreateParams memory params = IMarginPositionManager.CreateParams({
            marginForOne: true, // margin with token1, borrow native
            leverage: 2,
            marginAmount: uint128(marginAmount),
            borrowAmount: 0,
            borrowAmountMax: 0,
            recipient: address(this),
            deadline: block.timestamp
        });

        (uint256 tokenId, uint256 borrowAmount,) = marginPositionManager.addMargin(keyNative, params);

        assertTrue(tokenId > 0);
        assertTrue(borrowAmount > 0);

        MarginPosition.State memory position = marginPositionManager.getPositionState(tokenId);

        assertEq(position.marginAmount, marginAmount, "position.marginAmount==marginAmount");
        assertEq(position.debtAmount, borrowAmount, "position.debtAmount==borrowAmount");
        assertTrue(position.marginForOne, "position.marginForOne should be true");
        LikwidChecker.checkPoolReserves(vault, keyNative);
    }

    function testRepayNative() public {
        uint256 marginAmount = 0.1e18;

        IMarginPositionManager.CreateParams memory params = IMarginPositionManager.CreateParams({
            marginForOne: false, // margin with native, borrow token1
            leverage: 2,
            marginAmount: uint128(marginAmount),
            borrowAmount: 0,
            borrowAmountMax: 0,
            recipient: address(this),
            deadline: block.timestamp
        });

        (uint256 tokenId, uint256 borrowAmount,) =
            marginPositionManager.addMargin{value: marginAmount}(keyNative, params);

        assertTrue(tokenId > 0);
        assertTrue(borrowAmount > 0);

        uint256 repayAmount = borrowAmount / 2;
        token1.mint(address(this), repayAmount);

        MarginPosition.State memory positionBefore = marginPositionManager.getPositionState(tokenId);

        marginPositionManager.repay(tokenId, repayAmount, block.timestamp);

        MarginPosition.State memory positionAfter = marginPositionManager.getPositionState(tokenId);

        assertTrue(
            positionAfter.debtAmount < positionBefore.debtAmount, "position.debtAmount should be less after repay"
        );
        LikwidChecker.checkPoolReserves(vault, keyNative);
    }

    function testRepayNative_RepayNative() public {
        uint256 marginAmount = 0.1e18;
        token1.mint(address(this), marginAmount);

        IMarginPositionManager.CreateParams memory params = IMarginPositionManager.CreateParams({
            marginForOne: true, // margin with token1, borrow native
            leverage: 2,
            marginAmount: uint128(marginAmount),
            borrowAmount: 0,
            borrowAmountMax: 0,
            recipient: address(this),
            deadline: block.timestamp
        });

        (uint256 tokenId, uint256 borrowAmount,) = marginPositionManager.addMargin(keyNative, params);

        assertTrue(tokenId > 0);
        assertTrue(borrowAmount > 0);

        uint256 repayAmount = borrowAmount / 2;

        MarginPosition.State memory positionBefore = marginPositionManager.getPositionState(tokenId);

        marginPositionManager.repay{value: repayAmount}(tokenId, repayAmount, block.timestamp);

        MarginPosition.State memory positionAfter = marginPositionManager.getPositionState(tokenId);

        assertTrue(
            positionAfter.debtAmount < positionBefore.debtAmount, "position.debtAmount should be less after repay"
        );
        LikwidChecker.checkPoolReserves(vault, keyNative);
    }

    function testCloseNative() public {
        uint256 marginAmount = 0.1e18;

        IMarginPositionManager.CreateParams memory params = IMarginPositionManager.CreateParams({
            marginForOne: false, // margin with native, borrow token1
            leverage: 2,
            marginAmount: uint128(marginAmount),
            borrowAmount: 0,
            borrowAmountMax: 0,
            recipient: address(this),
            deadline: block.timestamp
        });

        (uint256 tokenId,,) = marginPositionManager.addMargin{value: marginAmount}(keyNative, params);

        uint256 balanceBefore = address(this).balance;
        marginPositionManager.close(tokenId, 1_000_000, 0, block.timestamp); // close 100%
        uint256 balanceAfter = address(this).balance;

        assertTrue(balanceAfter > balanceBefore, "should receive native currency back");

        MarginPosition.State memory position = marginPositionManager.getPositionState(tokenId);

        assertEq(position.marginAmount, 0, "position.marginAmount should be 0 after close");
        assertEq(position.debtAmount, 0, "position.debtAmount should be 0 after close");
        LikwidChecker.checkPoolReserves(vault, keyNative);
    }

    function testModifyNative() public {
        uint256 marginAmount = 0.1e18;

        IMarginPositionManager.CreateParams memory params = IMarginPositionManager.CreateParams({
            marginForOne: false, // margin with native, borrow token1
            leverage: 2,
            marginAmount: uint128(marginAmount),
            borrowAmount: 0,
            borrowAmountMax: 0,
            recipient: address(this),
            deadline: block.timestamp
        });

        (uint256 tokenId,,) = marginPositionManager.addMargin{value: marginAmount}(keyNative, params);

        MarginPosition.State memory positionBefore = marginPositionManager.getPositionState(tokenId);

        uint256 modifyAmount = 0.05e18;
        marginPositionManager.modify{value: modifyAmount}(tokenId, int128(int256(modifyAmount)));

        MarginPosition.State memory positionAfter = marginPositionManager.getPositionState(tokenId);

        assertEq(
            positionAfter.marginAmount,
            positionBefore.marginAmount + modifyAmount,
            "position.marginAmount should be increased"
        );
        LikwidChecker.checkPoolReserves(vault, keyNative);
    }

    function testModifyNative_DecreaseCollateral() public {
        uint256 marginAmount = 0.2e18;

        IMarginPositionManager.CreateParams memory params = IMarginPositionManager.CreateParams({
            marginForOne: false, // margin with native, borrow token1
            leverage: 2,
            marginAmount: uint128(marginAmount),
            borrowAmount: 0,
            borrowAmountMax: 0,
            recipient: address(this),
            deadline: block.timestamp
        });

        (uint256 tokenId,,) = marginPositionManager.addMargin{value: marginAmount}(keyNative, params);
        MarginPosition.State memory positionBefore = marginPositionManager.getPositionState(tokenId);

        int128 modifyAmount = -0.05e18;

        uint256 balanceBefore = address(this).balance;
        marginPositionManager.modify(tokenId, modifyAmount);
        uint256 balanceAfter = address(this).balance;

        assertTrue(balanceAfter > balanceBefore, "should receive native currency back");

        MarginPosition.State memory positionAfter = marginPositionManager.getPositionState(tokenId);

        assertEq(
            int256(uint256(positionAfter.marginAmount)),
            int256(uint256(positionBefore.marginAmount)) + modifyAmount,
            "position.marginAmount should be decreased"
        );
        LikwidChecker.checkPoolReserves(vault, keyNative);
    }

    function testAddMargin_LowFeePoolMarginBanned() public {
        uint256 marginAmount = 0.1e18;
        token0.mint(address(this), marginAmount);

        IMarginPositionManager.CreateParams memory params = IMarginPositionManager.CreateParams({
            marginForOne: false, // margin with token0, borrow token1
            leverage: 2,
            marginAmount: uint128(marginAmount),
            borrowAmount: 0,
            borrowAmountMax: 0,
            recipient: address(this),
            deadline: block.timestamp
        });

        vm.expectRevert(IMarginPositionManager.LowFeePoolMarginBanned.selector);
        marginPositionManager.addMargin(keyLowFee, params);
    }

    function testAddMargin_Fail_ExpiredDeadline() public {
        uint256 marginAmount = 0.1e18;
        token0.mint(address(this), marginAmount);

        IMarginPositionManager.CreateParams memory params = IMarginPositionManager.CreateParams({
            marginForOne: false,
            leverage: 2,
            marginAmount: uint128(marginAmount),
            borrowAmount: 0,
            borrowAmountMax: 0,
            recipient: address(this),
            deadline: block.timestamp - 1
        });

        vm.expectRevert(bytes("EXPIRED"));
        marginPositionManager.addMargin(key, params);
    }

    function testAddMargin_Fail_ReservesNotEnough() public {
        uint256 marginAmount = 10000e18; // A very large amount
        token0.mint(address(this), marginAmount);

        IMarginPositionManager.CreateParams memory params = IMarginPositionManager.CreateParams({
            marginForOne: false,
            leverage: 5,
            marginAmount: uint128(marginAmount),
            borrowAmount: 0,
            borrowAmountMax: 0,
            recipient: address(this),
            deadline: block.timestamp
        });

        vm.expectRevert(IMarginPositionManager.ReservesNotEnough.selector);
        marginPositionManager.addMargin(key, params);
    }

    function testAddMargin_Fail_BorrowTooMuch() public {
        uint256 marginAmount = 0.1e18;
        token0.mint(address(this), marginAmount);

        IMarginPositionManager.CreateParams memory params = IMarginPositionManager.CreateParams({
            marginForOne: false,
            leverage: 0, // No leverage
            marginAmount: uint128(marginAmount),
            borrowAmount: 1e18, // Borrow a large amount
            borrowAmountMax: 1e18,
            recipient: address(this),
            deadline: block.timestamp
        });

        vm.expectRevert(IMarginPositionManager.BorrowTooMuch.selector);
        marginPositionManager.addMargin(key, params);
    }

    function testClose_Fail_InsufficientCloseReceived() public {
        uint256 marginAmount = 0.1e18;
        token0.mint(address(this), marginAmount);

        IMarginPositionManager.CreateParams memory params = IMarginPositionManager.CreateParams({
            marginForOne: false,
            leverage: 2,
            marginAmount: uint128(marginAmount),
            borrowAmount: 0,
            borrowAmountMax: 0,
            recipient: address(this),
            deadline: block.timestamp
        });

        (uint256 tokenId,,) = marginPositionManager.addMargin(key, params);

        // Try to close with a very high min amount to receive
        vm.expectRevert(IMarginPositionManager.InsufficientCloseReceived.selector);
        marginPositionManager.close(tokenId, 1_000_000, 1e18, block.timestamp);
    }

    function testSetMarginLevel_Fail_InvalidLevels() public {
        // An invalid level, e.g., liquidateLevel > minMarginLevel
        MarginLevels newMarginLevels;
        newMarginLevels = newMarginLevels.setMinMarginLevel(1100000);
        newMarginLevels = newMarginLevels.setLiquidateLevel(1200000); // Invalid

        vm.expectRevert(IMarginPositionManager.InvalidLevel.selector);
        marginPositionManager.setMarginLevel(MarginLevels.unwrap(newMarginLevels));
    }
}
