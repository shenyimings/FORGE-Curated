// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IUniV4, IPoolManager} from "../../src/interfaces/IUniV4.sol";
import {ModifyLiquidityParams, SwapParams} from "v4-core/src/types/PoolOperation.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {IUnlockCallback} from "v4-core/src/interfaces/callback/IUnlockCallback.sol";
import {SafeTransferLib} from "solady/src/utils/SafeTransferLib.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";

import {console} from "forge-std/console.sol";
import {FormatLib} from "super-sol/libraries/FormatLib.sol";

/// @author philogy <https://github.com/philogy>
/// @notice Likely vulnerable, NOT FOR PRODUCTION USE.
contract RouterActor is IUnlockCallback {
    using FormatLib for *;
    using IUniV4 for IPoolManager;
    using SafeTransferLib for address;

    enum Action {
        Swap,
        SwapWithData,
        Liquidity
    }

    IPoolManager uniV4;

    constructor(IPoolManager uniV4_) {
        uniV4 = uniV4_;
    }

    receive() external payable {}

    function swap(PoolKey calldata key, bool zeroForOne, int256 amountSpecified)
        external
        returns (BalanceDelta)
    {
        return swap(
            key,
            zeroForOne,
            amountSpecified,
            zeroForOne ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1
        );
    }

    function swap(
        PoolKey calldata key,
        bool zeroForOne,
        int256 amountSpecified,
        uint160 sqrtPriceLimitX96
    ) public returns (BalanceDelta) {
        bytes memory ret = uniV4.unlock(
            bytes.concat(
                bytes1(uint8(Action.Swap)),
                abi.encode(key, SwapParams(zeroForOne, amountSpecified, sqrtPriceLimitX96))
            )
        );
        return abi.decode(ret, (BalanceDelta));
    }

    function swap(
        PoolKey calldata key,
        bool zeroForOne,
        int256 amountSpecified,
        uint160 sqrtPriceLimitX96,
        bytes calldata hookData
    ) external returns (BalanceDelta) {
        bytes memory ret = uniV4.unlock(
            bytes.concat(
                bytes1(uint8(Action.SwapWithData)),
                abi.encode(
                    key, SwapParams(zeroForOne, amountSpecified, sqrtPriceLimitX96), hookData
                )
            )
        );
        return abi.decode(ret, (BalanceDelta));
    }

    function modifyLiquidity(
        PoolKey calldata key,
        int24 lowerTick,
        int24 upperTick,
        int256 liquidityDelta,
        bytes32 salt
    ) external returns (BalanceDelta, BalanceDelta) {
        bytes memory ret = uniV4.unlock(
            bytes.concat(
                bytes1(uint8(Action.Liquidity)),
                abi.encode(key, ModifyLiquidityParams(lowerTick, upperTick, liquidityDelta, salt))
            )
        );
        return abi.decode(ret, (BalanceDelta, BalanceDelta));
    }

    function unlockCallback(bytes calldata payload) external returns (bytes memory) {
        require(address(uniV4) == msg.sender);

        Action action = Action(uint8(bytes1(payload[:1])));

        if (action == Action.Swap) {
            (PoolKey memory key, SwapParams memory params) =
                abi.decode(payload[1:], (PoolKey, SwapParams));
            return _swap(key, params, "");
        } else if (action == Action.SwapWithData) {
            (PoolKey memory key, SwapParams memory params, bytes memory hookData) =
                abi.decode(payload[1:], (PoolKey, SwapParams, bytes));
            return _swap(key, params, hookData);
        } else if (action == Action.Liquidity) {
            (PoolKey memory key, ModifyLiquidityParams memory params) =
                abi.decode(payload[1:], (PoolKey, ModifyLiquidityParams));
            return _modifyLiquidity(key, params);
        } else {
            revert("Unrecognized action");
        }
    }

    function recycle(address asset) external {
        Currency currency = Currency.wrap(asset);
        currency.transfer(msg.sender, currency.balanceOfSelf());
    }

    function transfer(address asset, address to, uint256 amount) external {
        Currency.wrap(asset).transfer(to, amount);
    }

    function _swap(PoolKey memory key, SwapParams memory params, bytes memory hookData)
        internal
        returns (bytes memory)
    {
        BalanceDelta delta = uniV4.swap(key, params, hookData);
        _settle(key, delta);

        int256 routerDelta0 = uniV4.getDelta(address(this), Currency.unwrap(key.currency0));
        int256 routerDelta1 = uniV4.getDelta(address(this), Currency.unwrap(key.currency1));
        if (routerDelta0 != 0 || routerDelta1 != 0) {
            console.log("router delta0: %s", routerDelta0.toStr());
            console.log("router delta1: %s", routerDelta1.toStr());
        }

        int256 hookDelta0 = uniV4.getDelta(address(key.hooks), Currency.unwrap(key.currency0));
        int256 hookDelta1 = uniV4.getDelta(address(key.hooks), Currency.unwrap(key.currency1));
        if (hookDelta0 != 0 || hookDelta1 != 0) {
            console.log("hook delta0: %s", hookDelta0.toStr());
            console.log("hook delta1: %s", hookDelta1.toStr());
        }

        return abi.encode(delta);
    }

    function _modifyLiquidity(PoolKey memory key, ModifyLiquidityParams memory params)
        internal
        returns (bytes memory)
    {
        (BalanceDelta callerDelta, BalanceDelta feesAccrued) =
            uniV4.modifyLiquidity(key, params, "");

        _settle(key, callerDelta + feesAccrued);
        if (params.liquidityDelta <= 0) {
            int128 rewardDelta =
                int128(uniV4.getDelta(address(this), Currency.unwrap(key.currency0)));
            _settle(key.currency0, rewardDelta);
        }
        return abi.encode(callerDelta, feesAccrued);
    }

    function _settle(PoolKey memory key, BalanceDelta delta) internal {
        _settle(key.currency0, delta.amount0());
        _settle(key.currency1, delta.amount1());
    }

    function _settle(Currency currency, int128 amount) internal {
        unchecked {
            if (amount < 0) {
                uniV4.sync(currency);
                if (currency.isAddressZero()) {
                    uniV4.settle{value: uint128(-amount)}();
                } else {
                    currency.transfer(address(uniV4), uint128(-amount));
                    uniV4.settle();
                }
            } else if (0 < amount) {
                uniV4.take(currency, address(this), uint128(amount));
            }
        }
    }
}
