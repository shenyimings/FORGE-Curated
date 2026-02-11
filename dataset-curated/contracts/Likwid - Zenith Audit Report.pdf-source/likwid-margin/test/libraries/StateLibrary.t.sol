// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {LikwidVault} from "../../src/LikwidVault.sol";
import {IVault} from "../../src/interfaces/IVault.sol";
import {IUnlockCallback} from "../../src/interfaces/callback/IUnlockCallback.sol";
import {MarginState} from "../../src/types/MarginState.sol";
import {PoolKey} from "../../src/types/PoolKey.sol";
import {Currency, CurrencyLibrary} from "../../src/types/Currency.sol";
import {PoolId, PoolIdLibrary} from "../../src/types/PoolId.sol";
import {BalanceDelta} from "../../src/types/BalanceDelta.sol";
import {StateLibrary} from "../../src/libraries/StateLibrary.sol";
import {StageMath} from "../../src/libraries/StageMath.sol";
import {LendPosition} from "../../src/libraries/LendPosition.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";

contract StateLibraryTest is Test, IUnlockCallback {
    using CurrencyLibrary for Currency;
    using PoolIdLibrary for PoolKey;
    using StageMath for uint256;

    LikwidVault vault;
    MockERC20 token0;
    MockERC20 token1;
    Currency currency0;
    Currency currency1;
    PoolKey poolKey;
    PoolId poolId;
    uint256 initialLiquidity;

    function setUp() public {
        vault = new LikwidVault(address(this));
        token0 = new MockERC20("Token0", "TKN0", 18);
        token1 = new MockERC20("Token1", "TKN1", 18);

        // Approve vault to spend tokens
        token0.approve(address(vault), type(uint256).max);
        token1.approve(address(vault), type(uint256).max);

        currency0 = Currency.wrap(address(token0));
        currency1 = Currency.wrap(address(token1));

        // Ensure currency order
        if (Currency.unwrap(currency0) > Currency.unwrap(currency1)) {
            (currency0, currency1) = (currency1, currency0);
            (token0, token1) = (token1, token0);
        }

        poolKey = PoolKey({currency0: currency0, currency1: currency1, fee: 3000});
        poolId = poolKey.toId();
        vault.initialize(poolKey);
        vault.setMarginController(address(this));

        // Add initial liquidity
        initialLiquidity = 10 ether;
        token0.mint(address(this), initialLiquidity);
        token1.mint(address(this), initialLiquidity);

        IVault.ModifyLiquidityParams memory mlParams = IVault.ModifyLiquidityParams({
            amount0: initialLiquidity,
            amount1: initialLiquidity,
            liquidityDelta: 0,
            salt: bytes32(0)
        });

        bytes memory innerData = abi.encode(poolKey, mlParams);
        bytes memory data = abi.encode(this.modifyLiquidity_callback.selector, innerData);
        vault.unlock(data);
    }

    function unlockCallback(bytes calldata data) external returns (bytes memory) {
        (bytes4 selector, bytes memory params) = abi.decode(data, (bytes4, bytes));

        if (selector == this.modifyLiquidity_callback.selector) {
            (PoolKey memory key, IVault.ModifyLiquidityParams memory mlParams) =
                abi.decode(params, (PoolKey, IVault.ModifyLiquidityParams));
            (BalanceDelta delta,) = vault.modifyLiquidity(key, mlParams);
            settleDelta(delta);
        } else if (selector == this.lend_callback.selector) {
            (PoolKey memory key, IVault.LendParams memory lendParams) = abi.decode(params, (PoolKey, IVault.LendParams));
            BalanceDelta delta = vault.lend(key, lendParams);
            settleDelta(delta);
        }
        return "";
    }

    function modifyLiquidity_callback(PoolKey memory, IVault.ModifyLiquidityParams memory) external pure {}
    function lend_callback(PoolKey memory, IVault.LendParams memory) external pure {}

    function settleDelta(BalanceDelta delta) internal {
        if (delta.amount0() < 0) {
            vault.sync(currency0);
            token0.transfer(address(vault), uint256(-int256(delta.amount0())));
            vault.settle();
        } else if (delta.amount0() > 0) {
            vault.take(currency0, address(this), uint256(int256(delta.amount0())));
        }

        if (delta.amount1() < 0) {
            vault.sync(currency1);
            token1.transfer(address(vault), uint256(-int256(delta.amount1())));
            vault.settle();
        } else if (delta.amount1() > 0) {
            vault.take(currency1, address(this), uint256(int256(delta.amount1())));
        }
    }

    function testGetStageLiquidities() public view {
        uint256[] memory liquidities = StateLibrary.getRawStageLiquidities(vault, poolId);
        MarginState marginState = vault.marginState();
        (uint128 total, uint128 liquidity) = liquidities[0].decode();
        assertEq(liquidities.length, marginState.stageSize(), "liquidities.length==marginState.stageSize()");
        assertEq(total, initialLiquidity / marginState.stageSize(), "total0==initialLiquidity/marginState.stageSize()");
        assertEq(total, liquidity, "total==liquidity");
    }

    function testGetLendPositionStateForZero() public {
        // 1. Lend to the pool to create a lend position
        int128 amountToLend = -1 ether;
        bool lendForOne = false;
        bytes32 salt = keccak256("my_lend_position");

        token0.mint(address(this), uint256(-int256(amountToLend)));

        IVault.LendParams memory lendParams =
            IVault.LendParams({lendForOne: lendForOne, lendAmount: amountToLend, salt: salt});

        bytes memory innerData = abi.encode(poolKey, lendParams);
        bytes memory data = abi.encode(this.lend_callback.selector, innerData);
        vault.unlock(data);

        // 2. Get the position state using the library function
        LendPosition.State memory positionState =
            StateLibrary.getLendPositionState(vault, poolId, address(this), lendForOne, salt);

        // 3. Assert the state is correct
        assertEq(uint256(positionState.lendAmount), uint256(-int256(amountToLend)), "lendAmount should be correct");
        assertTrue(positionState.depositCumulativeLast != 0, "depositCumulativeLast should be set");
    }

    function testGetLendPositionStateForOne() public {
        // 1. Lend to the pool to create a lend position
        int128 amountToLend = -1 ether;
        bool lendForOne = true;
        bytes32 salt = keccak256("my_lend_position");

        token1.mint(address(this), uint256(-int256(amountToLend)));

        IVault.LendParams memory lendParams =
            IVault.LendParams({lendForOne: lendForOne, lendAmount: amountToLend, salt: salt});

        bytes memory innerData = abi.encode(poolKey, lendParams);
        bytes memory data = abi.encode(this.lend_callback.selector, innerData);
        vault.unlock(data);

        // 2. Get the position state using the library function
        LendPosition.State memory positionState =
            StateLibrary.getLendPositionState(vault, poolId, address(this), lendForOne, salt);

        // 3. Assert the state is correct
        assertEq(uint256(positionState.lendAmount), uint256(-int256(amountToLend)), "lendAmount should be correct");
        assertTrue(positionState.depositCumulativeLast != 0, "depositCumulativeLast should be set");
    }
}
