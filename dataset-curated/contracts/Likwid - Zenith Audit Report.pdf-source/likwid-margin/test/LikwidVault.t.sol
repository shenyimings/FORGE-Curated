// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {MarginBase} from "../src/base/MarginBase.sol";
import {LikwidVault} from "../src/LikwidVault.sol";
import {IVault} from "../src/interfaces/IVault.sol";
import {IUnlockCallback} from "../src/interfaces/callback/IUnlockCallback.sol";
import {FeeTypes} from "../src/types/FeeTypes.sol";
import {PoolKey} from "../src/types/PoolKey.sol";
import {Currency, CurrencyLibrary} from "../src/types/Currency.sol";
import {PoolId, PoolIdLibrary} from "../src/types/PoolId.sol";
import {Pool} from "../src/libraries/Pool.sol";
import {BalanceDelta} from "../src/types/BalanceDelta.sol";
import {MarginState} from "../src/types/MarginState.sol";
import {Reserves} from "../src/types/Reserves.sol";
import {StateLibrary} from "../src/libraries/StateLibrary.sol";
import {SwapMath} from "../src/libraries/SwapMath.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";

contract LikwidVaultTest is Test, IUnlockCallback {
    using CurrencyLibrary for Currency;
    using PoolIdLibrary for PoolKey;
    using SwapMath for *;

    LikwidVault vault;
    MockERC20 token0;
    MockERC20 token1;
    Currency currency0;
    Currency currency1;

    fallback() external payable {}
    receive() external payable {}

    function setUp() public {
        skip(1); // Skip the first block to ensure block.timestamp is not zero
        vault = new LikwidVault(address(this));
        vault.setMarginController(address(this));
        token0 = new MockERC20("Token0", "TKN0", 18);
        token1 = new MockERC20("Token1", "TKN1", 18);
        token0.approve(address(vault), type(uint256).max);
        token1.approve(address(vault), type(uint256).max);
        currency0 = Currency.wrap(address(token0));
        currency1 = Currency.wrap(address(token1));
    }

    function unlockCallback(bytes calldata data) external returns (bytes memory) {
        (bytes4 selector, bytes memory params) = abi.decode(data, (bytes4, bytes));
        uint256 value;
        if (selector == this.reentrant_unlock_test.selector) {
            vault.unlock(params);
        } else if (selector == this.unsettled_take_callback.selector) {
            (Currency currency, address to, uint256 amount) = abi.decode(params, (Currency, address, uint256));
            vault.take(currency, to, amount);
        } else if (selector == this.modifyLiquidity_callback.selector) {
            (PoolKey memory key, IVault.ModifyLiquidityParams memory mlParams) =
                abi.decode(params, (PoolKey, IVault.ModifyLiquidityParams));

            (BalanceDelta delta,) = vault.modifyLiquidity(key, mlParams);

            // Settle the balances

            if (delta.amount0() < 0) {
                vault.sync(key.currency0);
                if (key.currency0.isAddressZero()) value = uint256(-int256(delta.amount0()));
                else token0.transfer(address(vault), uint256(-int256(delta.amount0())));
                vault.settle{value: value}();
            } else if (delta.amount0() > 0) {
                vault.take(key.currency0, address(this), uint256(int256(delta.amount0())));
            }

            if (delta.amount1() < 0) {
                vault.sync(key.currency1);
                token1.transfer(address(vault), uint256(-int256(delta.amount1())));
                vault.settle();
            } else if (delta.amount1() > 0) {
                vault.take(key.currency1, address(this), uint256(int256(delta.amount1())));
            }
        } else if (selector == this.swap_callback.selector) {
            (PoolKey memory key, IVault.SwapParams memory swapParams) = abi.decode(params, (PoolKey, IVault.SwapParams));
            (BalanceDelta delta,,) = vault.swap(key, swapParams);
            bool takeOutput = !swapParams.useMirror;
            // Settle the balances
            if (delta.amount0() < 0) {
                vault.sync(key.currency0);
                if (key.currency0.isAddressZero()) value = uint256(-int256(delta.amount0()));
                else token0.transfer(address(vault), uint256(-int256(delta.amount0())));
                vault.settle{value: value}();
            } else if (delta.amount0() > 0) {
                if (takeOutput) vault.take(key.currency0, address(this), uint256(int256(delta.amount0())));
            }

            if (delta.amount1() < 0) {
                vault.sync(key.currency1);
                token1.transfer(address(vault), uint256(-int256(delta.amount1())));
                vault.settle();
            } else if (delta.amount1() > 0) {
                if (takeOutput) {
                    vault.take(key.currency1, address(this), uint256(int256(delta.amount1())));
                }
            }
        } else if (selector == this.lend_callback.selector) {
            (PoolKey memory key, IVault.LendParams memory lendParams) = abi.decode(params, (PoolKey, IVault.LendParams));

            BalanceDelta delta = vault.lend(key, lendParams);

            // Settle the balances
            if (delta.amount0() < 0) {
                vault.sync(key.currency0);
                if (key.currency0.isAddressZero()) value = uint256(-int256(delta.amount0()));
                else token0.transfer(address(vault), uint256(-int256(delta.amount0())));
                vault.settle{value: value}();
            } else if (delta.amount0() > 0) {
                vault.take(key.currency0, address(this), uint256(int256(delta.amount0())));
            }

            if (delta.amount1() < 0) {
                vault.sync(key.currency1);
                token1.transfer(address(vault), uint256(-int256(delta.amount1())));
                vault.settle();
            } else if (delta.amount1() > 0) {
                vault.take(key.currency1, address(this), uint256(int256(delta.amount1())));
            }
        }
        return "";
    }

    function modifyLiquidity_callback(PoolKey memory, IVault.ModifyLiquidityParams memory) external pure {}

    function swap_callback(PoolKey memory, IVault.SwapParams memory) external pure {}

    function lend_callback(PoolKey memory, IVault.LendParams memory) external pure {}

    function empty_callback(bytes calldata) external pure {}

    function reentrant_unlock_test(bytes calldata) external pure {}

    function unsettled_take_callback(Currency, address, uint256) external pure {}

    function _addLiquidity(PoolKey memory key, uint256 amount0, uint256 amount1) internal {
        if (!key.currency0.isAddressZero()) {
            token0.mint(address(this), amount0);
        }
        token1.mint(address(this), amount1);
        IVault.ModifyLiquidityParams memory mlParams =
            IVault.ModifyLiquidityParams({amount0: amount0, amount1: amount1, liquidityDelta: 0, salt: bytes32(0)});
        bytes memory innerParamsLiq = abi.encode(key, mlParams);
        bytes memory dataLiq = abi.encode(this.modifyLiquidity_callback.selector, innerParamsLiq);
        vault.unlock(dataLiq);
        _checkPoolReserves(key);
    }

    function _setupStandardPool()
        internal
        returns (PoolKey memory key, uint256 initialLiquidity0, uint256 initialLiquidity1)
    {
        initialLiquidity0 = 10e18;
        initialLiquidity1 = 10e18;
        uint24 fee = 3000; // 0.3%
        key = PoolKey({currency0: currency0, currency1: currency1, fee: fee});
        vault.initialize(key);

        // Add liquidity
        _addLiquidity(key, initialLiquidity0, initialLiquidity1);
    }

    function _setupStandardPoolNative()
        internal
        returns (PoolKey memory key, uint256 initialLiquidity0, uint256 initialLiquidity1)
    {
        initialLiquidity0 = 10e18;
        initialLiquidity1 = 10e18;
        uint24 fee = 3000; // 0.3%
        key = PoolKey({currency0: CurrencyLibrary.ADDRESS_ZERO, currency1: currency1, fee: fee});
        vault.initialize(key);

        // Add liquidity
        _addLiquidity(key, initialLiquidity0, initialLiquidity1);
    }

    function _checkPoolReserves(PoolKey memory key) internal view {
        PoolId poolId = key.toId();
        Reserves realReserves = StateLibrary.getRealReserves(vault, poolId);
        Reserves mirrorReserves = StateLibrary.getMirrorReserves(vault, poolId);
        Reserves pairReserves = StateLibrary.getPairReserves(vault, poolId);
        Reserves lendReserves = StateLibrary.getLendReserves(vault, poolId);
        (uint128 realReserve0, uint128 realReserve1) = realReserves.reserves();
        (uint128 mirrorReserve0, uint128 mirrorReserve1) = mirrorReserves.reserves();
        (uint128 pairReserve0, uint128 pairReserve1) = pairReserves.reserves();
        (uint128 lendReserve0, uint128 lendReserve1) = lendReserves.reserves();
        assertEq(realReserve0 + mirrorReserve0, pairReserve0 + lendReserve0, "reserve0 should equal pair + lend");
        assertEq(realReserve1 + mirrorReserve1, pairReserve1 + lendReserve1, "reserve1 should equal pair + lend");
    }

    function testUnlockReverts() public {
        bytes memory data = abi.encode(this.empty_callback.selector, bytes(""));
        vault.unlock(data);
    }

    function testSwapExactInputToken0ForToken1() public {
        // 1. Setup
        (PoolKey memory key, uint256 initialLiquidity0, uint256 initialLiquidity1) = _setupStandardPool();
        uint256 amountToSwap = 1e18;

        Reserves _pairReserves = StateLibrary.getPairReserves(vault, key.toId());
        assertEq(_pairReserves.reserve0(), initialLiquidity0, "Initial reserve0 should match");
        assertEq(_pairReserves.reserve1(), initialLiquidity1, "Initial reserve1 should match");

        // Mint tokens for swap
        token0.mint(address(this), amountToSwap);

        // 2. Action
        bool zeroForOne = true; // token0 for token1
        IVault.SwapParams memory swapParams = IVault.SwapParams({
            zeroForOne: zeroForOne,
            amountSpecified: -int256(amountToSwap),
            useMirror: false,
            salt: bytes32(0)
        });

        uint256 initialVaultBalance1 = token1.balanceOf(address(vault));

        bytes memory innerParamsSwap = abi.encode(key, swapParams);
        bytes memory dataSwap = abi.encode(this.swap_callback.selector, innerParamsSwap);

        vault.unlock(dataSwap);

        // 3. Assertions
        uint256 finalVaultBalance1 = token1.balanceOf(address(vault));
        uint256 actualAmountOut = initialVaultBalance1 - finalVaultBalance1;

        assertEq(token0.balanceOf(address(this)), 0, "User token0 balance should be 0");
        assertEq(token1.balanceOf(address(this)), actualAmountOut, "User token1 balance should be amount out");
        assertEq(token0.balanceOf(address(vault)), initialLiquidity0 + amountToSwap, "Vault token0 balance");
        assertEq(token1.balanceOf(address(vault)), initialLiquidity1 - actualAmountOut, "Vault token1 balance");

        assertEq(
            vault.protocolFeesAccrued(currency0), amountToSwap * 3 / 10000, "Protocol fee for token0 should be 0.03%"
        );
        assertEq(vault.protocolFeesAccrued(currency1), 0, "Protocol fee for token1 should be 0");
        _checkPoolReserves(key);
    }

    function testSwapExactInputNativeForToken1() public {
        // 1. Setup
        (PoolKey memory key, uint256 initialLiquidity0, uint256 initialLiquidity1) = _setupStandardPoolNative();
        uint256 amountToSwap = 1e18;

        Reserves _pairReserves = StateLibrary.getPairReserves(vault, key.toId());
        assertEq(_pairReserves.reserve0(), initialLiquidity0, "Initial reserve0 should match");
        assertEq(_pairReserves.reserve1(), initialLiquidity1, "Initial reserve1 should match");

        // 2. Action
        bool zeroForOne = true; // native for token0
        IVault.SwapParams memory swapParams = IVault.SwapParams({
            zeroForOne: zeroForOne,
            amountSpecified: -int256(amountToSwap),
            useMirror: false,
            salt: bytes32(0)
        });

        uint256 initialVaultBalance1 = token1.balanceOf(address(vault));

        bytes memory innerParamsSwap = abi.encode(key, swapParams);
        bytes memory dataSwap = abi.encode(this.swap_callback.selector, innerParamsSwap);

        vault.unlock(dataSwap);

        // 3. Assertions
        uint256 finalVaultBalance1 = token1.balanceOf(address(vault));
        uint256 actualAmountOut = initialVaultBalance1 - finalVaultBalance1;

        assertEq(token1.balanceOf(address(this)), actualAmountOut, "User token1 balance should be amount out");
        assertEq(token1.balanceOf(address(vault)), initialLiquidity1 - actualAmountOut, "Vault token1 balance");

        assertEq(
            vault.protocolFeesAccrued(CurrencyLibrary.ADDRESS_ZERO),
            amountToSwap * 3 / 10000,
            "Protocol fee for native should be 0.03%"
        );
        assertEq(vault.protocolFeesAccrued(currency1), 0, "Protocol fee for token1 should be 0");
        _checkPoolReserves(key);
    }

    function testSwapExactOutputToken1ForToken0() public {
        // 1. Setup
        (PoolKey memory key, uint256 initialLiquidity0, uint256 initialLiquidity1) = _setupStandardPool();
        uint256 amountToReceive = 5e17; // 0.5 token0

        Reserves _pairReserves = StateLibrary.getPairReserves(vault, key.toId());
        assertEq(_pairReserves.reserve0(), initialLiquidity0, "Initial reserve0 should match");
        assertEq(_pairReserves.reserve1(), initialLiquidity1, "Initial reserve1 should match");

        // Calculate expected amount in
        bool zeroForOne = false; // token1 for token0
        Reserves _truncatedReserves = StateLibrary.getTruncatedReserves(vault, key.toId());
        (uint256 expectedAmountIn,,) =
            SwapMath.getAmountIn(_pairReserves, _truncatedReserves, key.fee, zeroForOne, amountToReceive);

        // Mint tokens for swap
        token1.mint(address(this), expectedAmountIn);

        // 2. Action
        IVault.SwapParams memory swapParams = IVault.SwapParams({
            zeroForOne: false, // we want token0, so we swap token1 for token0
            amountSpecified: int256(amountToReceive),
            useMirror: false,
            salt: bytes32(0)
        });

        bytes memory innerParamsSwap = abi.encode(key, swapParams);
        bytes memory dataSwap = abi.encode(this.swap_callback.selector, innerParamsSwap);

        vault.unlock(dataSwap);

        // 3. Assertions
        assertEq(token1.balanceOf(address(this)), 0, "User token1 balance should be 0");
        assertEq(token0.balanceOf(address(this)), amountToReceive, "User token0 balance should be amount received");
        assertEq(token1.balanceOf(address(vault)), initialLiquidity1 + expectedAmountIn, "Vault token1 balance");
        assertEq(token0.balanceOf(address(vault)), initialLiquidity0 - amountToReceive, "Vault token0 balance");
        _checkPoolReserves(key);
    }

    function testSwapExactOutputToken1ForNative() public {
        // 1. Setup
        (PoolKey memory key, uint256 initialLiquidity0, uint256 initialLiquidity1) = _setupStandardPoolNative();
        uint256 amountToReceive = 5e17; // 0.5 token0

        Reserves _pairReserves = StateLibrary.getPairReserves(vault, key.toId());
        assertEq(_pairReserves.reserve0(), initialLiquidity0, "Initial reserve0 should match");
        assertEq(_pairReserves.reserve1(), initialLiquidity1, "Initial reserve1 should match");

        // Calculate expected amount in
        bool zeroForOne = false; // token1 for token0
        Reserves _truncatedReserves = StateLibrary.getTruncatedReserves(vault, key.toId());
        (uint256 expectedAmountIn,,) =
            SwapMath.getAmountIn(_pairReserves, _truncatedReserves, key.fee, zeroForOne, amountToReceive);

        // Mint tokens for swap
        token1.mint(address(this), expectedAmountIn);

        // 2. Action
        IVault.SwapParams memory swapParams = IVault.SwapParams({
            zeroForOne: false, // we want native, so we swap token1 for native
            amountSpecified: int256(amountToReceive),
            useMirror: false,
            salt: bytes32(0)
        });

        bytes memory innerParamsSwap = abi.encode(key, swapParams);
        bytes memory dataSwap = abi.encode(this.swap_callback.selector, innerParamsSwap);

        vault.unlock(dataSwap);

        // 3. Assertions
        assertEq(token1.balanceOf(address(this)), 0, "User token1 balance should be 0");
        assertEq(token1.balanceOf(address(vault)), initialLiquidity1 + expectedAmountIn, "Vault token1 balance");
        assertEq(address(vault).balance, initialLiquidity0 - amountToReceive, "Vault token0 balance");
        _checkPoolReserves(key);
    }

    function testSwapWithProtocolFee() public {
        // 1. Setup
        (PoolKey memory key, uint256 initialLiquidity0,) = _setupStandardPool();
        uint256 amountToSwap = 1e18;
        uint8 swapProtocolFee = 50; // Represents 25% of the LP fee (50/200)

        // Set protocol fee
        vault.setProtocolFeeController(address(this));
        vault.setProtocolFee(key, FeeTypes.SWAP, swapProtocolFee);

        Reserves _pairReserves = StateLibrary.getPairReserves(vault, key.toId());
        assertEq(_pairReserves.reserve0(), initialLiquidity0, "Initial reserve0 should match");

        // Mint tokens for swap
        token0.mint(address(this), amountToSwap);

        // 2. Action
        bool zeroForOne = true;
        IVault.SwapParams memory swapParams = IVault.SwapParams({
            zeroForOne: zeroForOne,
            amountSpecified: -int256(amountToSwap),
            useMirror: false,
            salt: bytes32(0)
        });

        bytes memory innerParamsSwap = abi.encode(key, swapParams);
        bytes memory dataSwap = abi.encode(this.swap_callback.selector, innerParamsSwap);

        vault.unlock(dataSwap);

        // 3. Assertions
        Reserves _truncatedReserves = StateLibrary.getTruncatedReserves(vault, key.toId());
        uint256 degree = _pairReserves.getPriceDegree(_truncatedReserves, key.fee, zeroForOne, amountToSwap, 0);
        uint24 fee = key.fee.dynamicFee(degree);
        console.log("Dynamic fee (in ppm): ", fee);
        uint256 totalFeeAmount = amountToSwap * fee / 1_000_000;
        uint256 expectedProtocolFee = totalFeeAmount * swapProtocolFee / 200;
        console.log("Total fee amount: ", totalFeeAmount);
        console.log("Expected protocol fee: ", expectedProtocolFee);
        assertEq(vault.protocolFeesAccrued(currency0), expectedProtocolFee, "Protocol fee accrued should be correct");
        assertEq(vault.protocolFeesAccrued(currency1), 0, "Protocol fee for token1 should be 0");
    }

    function testModifyLiquidityAddCallback() public {
        // 1. Setup
        uint256 amount0ToAdd = 1e18;
        uint256 amount1ToAdd = 4e18;
        PoolKey memory key = PoolKey({currency0: currency0, currency1: currency1, fee: 25});
        vault.initialize(key);
        token0.mint(address(this), amount0ToAdd);
        token1.mint(address(this), amount1ToAdd);

        IVault.ModifyLiquidityParams memory mlParams = IVault.ModifyLiquidityParams({
            amount0: amount0ToAdd,
            amount1: amount1ToAdd,
            liquidityDelta: 0,
            salt: bytes32(0)
        });

        // 2. Action
        bytes memory innerParams = abi.encode(key, mlParams);
        bytes memory data = abi.encode(this.modifyLiquidity_callback.selector, innerParams);
        vault.unlock(data);

        // 3. Assertions
        assertEq(token0.balanceOf(address(this)), 0, "User token0 balance should be 0");
        assertEq(token1.balanceOf(address(this)), 0, "User token1 balance should be 0");
        assertEq(token0.balanceOf(address(vault)), amount0ToAdd, "Vault token0 balance should be amount added");
        assertEq(token1.balanceOf(address(vault)), amount1ToAdd, "Vault token1 balance should be amount added");
        _checkPoolReserves(key);
    }

    function testInitializeRevertsIfCurrenciesOutOfOrder() public {
        PoolKey memory key = PoolKey({currency0: currency1, currency1: currency0, fee: 25});

        vm.expectRevert(
            abi.encodeWithSelector(
                IVault.CurrenciesOutOfOrderOrEqual.selector,
                Currency.unwrap(key.currency0),
                Currency.unwrap(key.currency1)
            )
        );
        vault.initialize(key);
    }

    function testInitializeRevertsIfCurrenciesEqual() public {
        PoolKey memory key = PoolKey({currency0: currency0, currency1: currency0, fee: 25});

        vm.expectRevert(
            abi.encodeWithSelector(
                IVault.CurrenciesOutOfOrderOrEqual.selector,
                Currency.unwrap(key.currency0),
                Currency.unwrap(key.currency1)
            )
        );
        vault.initialize(key);
    }

    function testInitializeRevertsIfPoolAlreadyInitialized() public {
        PoolKey memory key = PoolKey({currency0: currency0, currency1: currency1, fee: 25});
        vault.initialize(key);
        vm.expectRevert(abi.encodeWithSelector(Pool.PoolAlreadyInitialized.selector));
        vault.initialize(key);
    }

    function testLending() public {
        // 1. Setup
        (PoolKey memory key, uint256 initialLiquidity0,) = _setupStandardPool();

        int128 amountToLend = -1e18; // Deposit 1 token0
        token0.mint(address(this), uint256(int256(-amountToLend)));

        // 2. Action
        IVault.LendParams memory lendParams = IVault.LendParams({
            lendForOne: false, // lend token0
            lendAmount: amountToLend,
            salt: bytes32(0)
        });

        bytes memory innerParamsLend = abi.encode(key, lendParams);
        bytes memory dataLend = abi.encode(this.lend_callback.selector, innerParamsLend);

        vault.unlock(dataLend);

        // 3. Assertions
        assertEq(token0.balanceOf(address(this)), 0, "User token0 balance should be 0");
        assertEq(
            token0.balanceOf(address(vault)), initialLiquidity0 + uint256(int256(-amountToLend)), "Vault token0 balance"
        );
        _checkPoolReserves(key);
    }

    function testLendingWithdraw() public {
        // 1. Setup
        (PoolKey memory key, uint256 initialLiquidity0,) = _setupStandardPool();

        int128 amountToDeposit = -1e18; // Deposit 1 token0
        token0.mint(address(this), uint256(int256(-amountToDeposit)));

        // Deposit
        IVault.LendParams memory depositParams = IVault.LendParams({
            lendForOne: false, // lend token0
            lendAmount: amountToDeposit,
            salt: bytes32(0)
        });
        bytes memory innerParamsDeposit = abi.encode(key, depositParams);
        bytes memory dataDeposit = abi.encode(this.lend_callback.selector, innerParamsDeposit);
        vault.unlock(dataDeposit);

        assertEq(
            token0.balanceOf(address(vault)),
            initialLiquidity0 + uint256(int256(-amountToDeposit)),
            "Vault token0 balance after deposit"
        );

        // Withdraw
        int128 amountToWithdraw = 5e17; // Withdraw 0.5 token0
        IVault.LendParams memory withdrawParams = IVault.LendParams({
            lendForOne: false, // lend token0
            lendAmount: amountToWithdraw,
            salt: bytes32(0)
        });

        bytes memory innerParamsWithdraw = abi.encode(key, withdrawParams);
        bytes memory dataWithdraw = abi.encode(this.lend_callback.selector, innerParamsWithdraw);

        vault.unlock(dataWithdraw);

        // 3. Assertions
        assertEq(
            token0.balanceOf(address(this)),
            uint256(int256(amountToWithdraw)),
            "User token0 balance should be withdrawn amount"
        );
        assertEq(
            token0.balanceOf(address(vault)),
            initialLiquidity0 + uint256(int256(-amountToDeposit)) - uint256(int256(amountToWithdraw)),
            "Vault token0 balance after withdraw"
        );
        _checkPoolReserves(key);
    }

    // =============================================================
    // REVERT TESTS
    // =============================================================

    function testRevertIfUnlockCalledWhenAlreadyUnlocked() public {
        bytes memory emptyData = abi.encode(this.empty_callback.selector, bytes(""));
        bytes memory callbackParams = abi.encode(this.reentrant_unlock_test.selector, emptyData);

        vm.expectRevert(abi.encodeWithSelector(IVault.AlreadyUnlocked.selector));
        vault.unlock(callbackParams);
    }

    function testRevertIfCurrencyNotSettledAfterUnlock() public {
        (PoolKey memory key,,) = _setupStandardPool();
        uint256 amountToTake = 1e17;

        bytes memory innerParams = abi.encode(key.currency0, address(this), amountToTake);
        bytes memory data = abi.encode(this.unsettled_take_callback.selector, innerParams);

        vm.expectRevert(abi.encodeWithSelector(IVault.CurrencyNotSettled.selector));
        vault.unlock(data);
    }

    function testRevertIfSwapCalledWhenLocked() public {
        (PoolKey memory key,,) = _setupStandardPool();
        IVault.SwapParams memory swapParams =
            IVault.SwapParams({zeroForOne: true, amountSpecified: -1e18, useMirror: false, salt: bytes32(0)});

        vm.expectRevert(abi.encodeWithSelector(IVault.VaultLocked.selector));
        vault.swap(key, swapParams);
    }

    function testRevertIfModifyLiquidityCalledWhenLocked() public {
        (PoolKey memory key,,) = _setupStandardPool();
        IVault.ModifyLiquidityParams memory mlParams =
            IVault.ModifyLiquidityParams({amount0: 1e18, amount1: 1e18, liquidityDelta: 0, salt: bytes32(0)});

        vm.expectRevert(abi.encodeWithSelector(IVault.VaultLocked.selector));
        vault.modifyLiquidity(key, mlParams);
    }

    function testRevertIfLendCalledWhenLocked() public {
        (PoolKey memory key,,) = _setupStandardPool();
        IVault.LendParams memory lendParams =
            IVault.LendParams({lendForOne: false, lendAmount: -1e18, salt: bytes32(0)});

        vm.expectRevert(abi.encodeWithSelector(IVault.VaultLocked.selector));
        vault.lend(key, lendParams);
    }

    // function testRevertIfMarginCalledWhenLocked() public {
    //     (PoolKey memory key,,) = _setupStandardPool();
    //     IVault.MarginParams memory marginParams = IVault.MarginParams({
    //         marginForOne: true,
    //         amount: -1e18,
    //         marginTotal: 1e18,
    //         borrowAmount: 0,
    //         changeAmount: 0,
    //         minMarginLevel: 0,
    //         salt: bytes32(0)
    //     });

    //     vm.expectRevert(abi.encodeWithSelector(IVault.VaultLocked.selector));
    //     vault.margin(key, marginParams);
    // }

    // function testRevertIfCloseCalledWhenLocked() public {
    //     (PoolKey memory key,,) = _setupStandardPool();
    //     IVault.CloseParams memory closeParams =
    //         IVault.CloseParams({positionKey: bytes32(0), salt: bytes32(0), rewardAmount: 0, closeMillionth: 1_000_000});

    //     vm.expectRevert(abi.encodeWithSelector(IVault.VaultLocked.selector));
    //     vault.close(key, closeParams);
    // }

    function testRevertSwapIfAmountIsZero() public {
        (PoolKey memory key,,) = _setupStandardPool();
        IVault.SwapParams memory swapParams =
            IVault.SwapParams({zeroForOne: true, amountSpecified: 0, useMirror: false, salt: bytes32(0)});

        bytes memory innerParams = abi.encode(key, swapParams);
        bytes memory data = abi.encode(this.swap_callback.selector, innerParams);

        vm.expectRevert(abi.encodeWithSelector(IVault.AmountCannotBeZero.selector));
        vault.unlock(data);
    }

    function testRevertLendIfAmountIsZero() public {
        (PoolKey memory key,,) = _setupStandardPool();
        IVault.LendParams memory lendParams = IVault.LendParams({lendForOne: false, lendAmount: 0, salt: bytes32(0)});

        bytes memory innerParams = abi.encode(key, lendParams);
        bytes memory data = abi.encode(this.lend_callback.selector, innerParams);

        vm.expectRevert(abi.encodeWithSelector(IVault.AmountCannotBeZero.selector));
        vault.unlock(data);
    }

    // function testRevertMarginIfAmountIsZero() public {
    //     (PoolKey memory key,,) = _setupStandardPool();
    //     IVault.MarginParams memory marginParams = IVault.MarginParams({
    //         marginForOne: true,
    //         amount: 0,
    //         marginTotal: 1e18,
    //         borrowAmount: 0,
    //         changeAmount: 0,
    //         minMarginLevel: 0,
    //         salt: bytes32(0)
    //     });

    //     bytes memory innerParams = abi.encode(key, marginParams);
    //     bytes memory data = abi.encode(this.margin_callback.selector, innerParams);

    //     vm.expectRevert(abi.encodeWithSelector(IVault.AmountCannotBeZero.selector));
    //     vault.unlock(data);
    // }

    // function testRevertCloseIfAmountIsZero() public {
    //     (PoolKey memory key,,) = _setupStandardPool();
    //     IVault.CloseParams memory closeParams =
    //         IVault.CloseParams({positionKey: bytes32(0), salt: bytes32(0), rewardAmount: 0, closeMillionth: 0});

    //     bytes memory innerParams = abi.encode(key, closeParams);
    //     bytes memory data = abi.encode(this.close_callback.selector, innerParams);

    //     vm.expectRevert(abi.encodeWithSelector(IVault.AmountCannotBeZero.selector));
    //     vault.unlock(data);
    // }

    function testRevertMarginIfNotManager() public {
        // (PoolKey memory key,,) = _setupStandardPool();
        // vault.setMarginController(address(uint160(address(this)) + 1)); // Set a different manager

        // IVault.MarginParams memory marginParams = IVault.MarginParams({
        //     marginForOne: true,
        //     amount: -1e18,
        //     marginTotal: 1e18,
        //     borrowAmount: 0,
        //     changeAmount: 0,
        //     minMarginLevel: 0,
        //     salt: bytes32(0)
        // });

        // bytes memory innerParams = abi.encode(key, marginParams);
        // bytes memory data = abi.encode(this.margin_callback.selector, innerParams);

        // vm.expectRevert(abi.encodeWithSelector(LikwidVault.Unauthorized.selector));
        // vault.unlock(data);
    }

    function testRevertRemoveLiquidityIfLocked() public {
        // 1. Setup
        MarginState _state = vault.marginState();
        _state.setStageDuration(1 hours);
        _state.setStageSize(5);
        vault.setMarginState(_state);
        (PoolKey memory key,,) = _setupStandardPool();

        // From PoolTest, we know initial liquidity is sqrt(amount0 * amount1)
        uint256 liquidity = 10e18;

        // 2. Action: Try to remove more liquidity than is available
        // By default, only a part of the liquidity is available for withdrawal immediately.
        // Removing the full amount should fail.
        IVault.ModifyLiquidityParams memory mlParams =
            IVault.ModifyLiquidityParams({amount0: 0, amount1: 0, liquidityDelta: -int256(liquidity), salt: bytes32(0)});

        bytes memory innerParams = abi.encode(key, mlParams);
        bytes memory data = abi.encode(this.modifyLiquidity_callback.selector, innerParams);

        // 3. Assertions
        vm.expectRevert(abi.encodeWithSelector(MarginBase.LiquidityLocked.selector));
        vault.unlock(data);
    }
}
