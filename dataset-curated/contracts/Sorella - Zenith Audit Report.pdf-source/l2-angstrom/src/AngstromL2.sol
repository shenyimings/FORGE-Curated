// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.26;

import {UniConsumer} from "./modules/UniConsumer.sol";
import {Ownable} from "solady/src/auth/Ownable.sol";
import {IAngstromL2Hook} from "./interfaces/IAngstromL2Hook.sol";
import {IUniV4, IPoolManager, PoolId} from "./interfaces/IUniV4.sol";
import {TickIteratorLib, TickIteratorUp, TickIteratorDown} from "./libraries/TickIterator.sol";
import {
    PoolKey,
    IBeforeSwapHook,
    IAfterSwapHook,
    IAfterAddLiquidityHook,
    IAfterRemoveLiquidityHook,
    IBeforeInitializeHook
} from "./interfaces/IHooks.sol";
import {IFlashBlockNumber} from "./interfaces/IFlashBlockNumber.sol";
import {IFactory} from "./interfaces/IFactory.sol";
import {BeforeSwapDelta, toBeforeSwapDelta} from "v4-core/src/types/BeforeSwapDelta.sol";
import {BalanceDelta, toBalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {ModifyLiquidityParams, SwapParams} from "v4-core/src/types/PoolOperation.sol";
import {Hooks, IHooks} from "v4-core/src/libraries/Hooks.sol";
import {Slot0} from "v4-core/src/types/Slot0.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {Currency, CurrencyLibrary} from "v4-core/src/types/Currency.sol";
import {SqrtPriceMath} from "v4-core/src/libraries/SqrtPriceMath.sol";
import {LPFeeLibrary} from "v4-core/src/libraries/LPFeeLibrary.sol";
import {SafeCastLib} from "solady/src/utils/SafeCastLib.sol";
import {MixedSignLib} from "./libraries/MixedSignLib.sol";
import {FixedPointMathLib} from "solady/src/utils/FixedPointMathLib.sol";
import {Q96MathLib} from "./libraries/Q96MathLib.sol";
import {CompensationPriceFinder} from "./libraries/CompensationPriceFinder.sol";
import {PoolRewards, PoolRewardsLib} from "./types/PoolRewards.sol";
import {PoolKeyHelperLib} from "./libraries/PoolKeyHelperLib.sol";
import {getRequiredHookPermissions} from "src/hook-config.sol";
import {tuint256, tbytes32} from "transient-goodies/TransientPrimitives.sol";

/// @author philogy <https://github.com/philogy>
contract AngstromL2 is
    UniConsumer,
    Ownable,
    IBeforeInitializeHook,
    IBeforeSwapHook,
    IAfterSwapHook,
    IAfterAddLiquidityHook,
    IAfterRemoveLiquidityHook,
    IAngstromL2Hook
{
    using IUniV4 for IPoolManager;
    using PoolKeyHelperLib for PoolKey;
    using Hooks for IHooks;
    using MixedSignLib for *;
    using FixedPointMathLib for *;
    using Q96MathLib for uint256;
    using SafeCastLib for *;

    error NegationOverflow();
    error CreatorFeeExceedsMaximum();
    error AttemptingToWithdrawLPRewards();
    error IncompatiblePoolConfiguration();
    error PoolNotInitialized();
    error PoolAlreadyInitialized();

    /// @dev The `SWAP_TAXED_GAS` is the abstract estimated gas cost for a swap. We want it to be
    /// a constant so that competing searchers have a bid cost independent of how much gas swap
    /// actually uses, the overall tax just needs to scale proportional to `priority_fee * swap_fixed_cost`.
    uint256 internal constant SWAP_TAXED_GAS = 100_000;
    /// @dev MEV tax charged is `priority_fee * SWAP_MEV_TAX_FACTOR` meaning the tax rate is
    /// `SWAP_MEV_TAX_FACTOR / (SWAP_MEV_TAX_FACTOR + 1)`
    uint256 constant SWAP_MEV_TAX_FACTOR = 49;
    /// @dev Parameters for taxing just-in-time (JIT) liquidity
    uint256 internal constant JIT_TAXED_GAS = 100_000;
    uint256 internal constant JIT_MEV_TAX_FACTOR = SWAP_MEV_TAX_FACTOR * 4;

    uint256 internal constant NATIVE_CURRENCY_ID = 0;
    Currency internal constant NATIVE_CURRENCY = CurrencyLibrary.ADDRESS_ZERO;
    uint256 internal constant FACTOR_E6 = 1e6;
    uint256 internal constant MAX_CREATOR_SWAP_FEE_E6 = 0.2e6;
    uint256 internal constant MAX_CREATOR_TAX_FEE_E6 = 0.5e6; // 50%

    // TODO: Be able to set provider.
    address public immutable FACTORY;

    IFlashBlockNumber internal flashBlockNumberProvider;
    uint96 internal _blockOfLastTopOfBlock;
    mapping(PoolId id => PoolRewards) internal rewards;

    struct PoolFeeConfiguration {
        bool isInitialized;
        uint24 creatorTaxFeeE6;
        uint24 protocolTaxFeeE6;
        uint24 creatorSwapFeeE6;
        uint24 protocolSwapFeeE6;
    }

    mapping(PoolId id => PoolFeeConfiguration) internal _poolFeeConfiguration;

    tuint256 internal liquidityBeforeSwap;
    tbytes32 internal slot0BeforeSwapStore;

    // Ownable explicit constructor commented out because of weird foundry bug causing
    // "modifier-style base constructor call without arguments": https://github.com/foundry-rs/foundry/issues/11607.
    constructor(
        IPoolManager uniV4,
        IFlashBlockNumber initialFlashBlockNumberProvider,
        address owner
    ) UniConsumer(uniV4) /* Ownable() */ {
        _initializeOwner(owner);
        FACTORY = msg.sender;
        Hooks.validateHookPermissions(IHooks(address(this)), getRequiredHookPermissions());
        flashBlockNumberProvider = initialFlashBlockNumberProvider;
    }

    receive() external payable {}

    function syncFlashBlockNumberProvider() public {
        flashBlockNumberProvider = IFactory(FACTORY).flashBlockNumberProvider();
    }

    function withdrawCreatorRevenue(Currency currency, address to, uint256 amount) public {
        _checkOwner();
        currency.transfer(to, amount);
    }

    function setProtocolSwapFee(PoolKey calldata key, uint256 newFeeE6) public {
        _checkCallerIsFactory();
        PoolFeeConfiguration storage feeConfiguration = _poolFeeConfiguration[key.calldataToId()];
        if (!feeConfiguration.isInitialized) revert PoolNotInitialized();
        feeConfiguration.protocolSwapFeeE6 = newFeeE6.toUint24();
    }

    function setProtocolTaxFee(PoolKey calldata key, uint256 newFeeE6) public {
        _checkCallerIsFactory();
        PoolFeeConfiguration storage feeConfiguration = _poolFeeConfiguration[key.calldataToId()];
        if (!feeConfiguration.isInitialized) revert PoolNotInitialized();
        feeConfiguration.protocolTaxFeeE6 = newFeeE6.toUint24();
    }

    function getSwapTaxAmount(uint256 priorityFee) public pure returns (uint256) {
        return SWAP_MEV_TAX_FACTOR * SWAP_TAXED_GAS * priorityFee;
    }

    function getJitTaxAmount(uint256 priorityFee) public pure returns (uint256) {
        return JIT_MEV_TAX_FACTOR * JIT_TAXED_GAS * priorityFee;
    }

    function getPendingPositionRewards(
        PoolKey calldata key,
        address owner,
        int24 lowerTick,
        int24 upperTick,
        bytes32 salt
    ) public view returns (uint256 rewards0) {
        PoolId id = key.calldataToId();
        rewards0 =
            rewards[id].getPendingPositionRewards(UNI_V4, id, owner, lowerTick, upperTick, salt);
    }

    function getPoolFeeConfiguration(PoolKey calldata key)
        public
        view
        returns (PoolFeeConfiguration memory)
    {
        return _poolFeeConfiguration[key.calldataToId()];
    }

    function initializeNewPool(
        PoolKey calldata key,
        uint160 sqrtPriceX96,
        uint24 creatorSwapFeeE6,
        uint24 creatorTaxFeeE6
    ) public {
        if (!(msg.sender == owner() || msg.sender == FACTORY)) revert Unauthorized();
        PoolFeeConfiguration storage feeConfiguration = _poolFeeConfiguration[key.calldataToId()];
        if (feeConfiguration.isInitialized) revert PoolAlreadyInitialized();
        if (!(creatorSwapFeeE6 <= MAX_CREATOR_SWAP_FEE_E6)) revert CreatorFeeExceedsMaximum();
        if (!(creatorTaxFeeE6 <= MAX_CREATOR_TAX_FEE_E6)) revert CreatorFeeExceedsMaximum();
        feeConfiguration.isInitialized = true;
        UNI_V4.initialize(key, sqrtPriceX96);
        feeConfiguration.creatorSwapFeeE6 = creatorSwapFeeE6.toUint24();
        feeConfiguration.creatorTaxFeeE6 = creatorTaxFeeE6.toUint24();
        (feeConfiguration.protocolSwapFeeE6, feeConfiguration.protocolTaxFeeE6) = IFactory(FACTORY)
            .recordPoolCreationAndGetStartingProtocolFee(key, creatorSwapFeeE6, creatorTaxFeeE6);
    }

    function beforeInitialize(address sender, PoolKey calldata key, uint160)
        external
        view
        returns (bytes4)
    {
        _onlyUniV4();
        if (sender != address(this)) revert Unauthorized();
        if (key.currency0.toId() != NATIVE_CURRENCY_ID) revert IncompatiblePoolConfiguration();
        if (LPFeeLibrary.isDynamicFee(key.fee)) revert IncompatiblePoolConfiguration();
        return this.beforeInitialize.selector;
    }

    function afterAddLiquidity(
        address sender,
        PoolKey calldata key,
        ModifyLiquidityParams calldata params,
        BalanceDelta,
        BalanceDelta,
        bytes calldata
    ) external returns (bytes4, BalanceDelta) {
        _onlyUniV4();

        PoolId id = key.calldataToId();
        rewards[id].updateAfterLiquidityAdd(UNI_V4, id, key.tickSpacing, sender, params);
        uint256 taxAmountInEther = _getJitTaxAmount();
        if (taxAmountInEther > 0) {
            // Protocol collects 100% of the JIT MEV tax
            UNI_V4.take(CurrencyLibrary.fromId(NATIVE_CURRENCY_ID), FACTORY, taxAmountInEther);
        }
        return (this.afterAddLiquidity.selector, toBalanceDelta(taxAmountInEther.toInt128(), 0));
    }

    function afterRemoveLiquidity(
        address sender,
        PoolKey calldata key,
        ModifyLiquidityParams calldata params,
        BalanceDelta,
        BalanceDelta,
        bytes calldata
    ) external returns (bytes4, BalanceDelta) {
        _onlyUniV4();

        PoolId id = key.calldataToId();
        uint256 rewardAmount0 = rewards[id].updateAfterLiquidityRemove(UNI_V4, id, sender, params);
        uint256 taxAmountInEther = _getJitTaxAmount();
        if (taxAmountInEther > 0) {
            // Protocol collects 100% of the JIT MEV tax
            UNI_V4.take(CurrencyLibrary.fromId(NATIVE_CURRENCY_ID), FACTORY, taxAmountInEther);
        }
        if (rewardAmount0 > 0) {
            UNI_V4.burn(address(this), NATIVE_CURRENCY_ID, rewardAmount0);
        }
        return (
            this.afterRemoveLiquidity.selector,
            toBalanceDelta(taxAmountInEther.toInt128() - rewardAmount0.toInt128(), 0)
        );
    }

    function beforeSwap(address, PoolKey calldata key, SwapParams calldata params, bytes calldata)
        external
        override
        returns (bytes4, BeforeSwapDelta, uint24)
    {
        _onlyUniV4();

        PoolId id = key.calldataToId();
        slot0BeforeSwapStore.set(Slot0.unwrap(UNI_V4.getSlot0(id)));

        if (_getBlock() == _blockOfLastTopOfBlock) {
            return (this.beforeSwap.selector, toBeforeSwapDelta(0, 0), 0);
        }

        liquidityBeforeSwap.set(UNI_V4.getPoolLiquidity(id));
        int128 etherDelta = _getSwapTaxAmount().toInt128();

        bool etherWasSpecified = params.zeroForOne == params.amountSpecified < 0;
        return (
            this.beforeSwap.selector,
            etherWasSpecified ? toBeforeSwapDelta(etherDelta, 0) : toBeforeSwapDelta(0, etherDelta),
            0
        );
    }

    function afterSwap(
        address,
        PoolKey calldata key,
        SwapParams calldata params,
        BalanceDelta swapDelta,
        bytes calldata
    ) external override returns (bytes4, int128 hookDeltaUnspecified) {
        _onlyUniV4();

        PoolId id = key.calldataToId();
        uint96 blockNumber = _getBlock();
        bool isTopOfBlock = blockNumber != _blockOfLastTopOfBlock;
        (uint256 feeInUnspecified, uint256 lpCompensationAmount) = _computeAndCollectProtocolSwapFee(
            key, id, params, swapDelta, isTopOfBlock ? _getSwapTaxAmount() : 0
        );
        hookDeltaUnspecified = feeInUnspecified.toInt128();

        PoolKey calldata key_ = key;
        Slot0 slot0BeforeSwap = Slot0.wrap(slot0BeforeSwapStore.get());
        Slot0 slot0AfterSwap = UNI_V4.getSlot0(id);
        rewards[id].updateAfterTickMove(
            id, UNI_V4, slot0BeforeSwap.tick(), slot0AfterSwap.tick(), key_.tickSpacing
        );

        if (!isTopOfBlock || lpCompensationAmount == 0) {
            return (this.afterSwap.selector, hookDeltaUnspecified);
        }
        _blockOfLastTopOfBlock = blockNumber;

        params.zeroForOne
            ? _zeroForOneDistributeTax(
                id, key_.tickSpacing, slot0BeforeSwap, slot0AfterSwap, lpCompensationAmount
            )
            : _oneForZeroDistributeTax(
                id, key_.tickSpacing, slot0BeforeSwap, slot0AfterSwap, lpCompensationAmount
            );

        return (this.afterSwap.selector, hookDeltaUnspecified);
    }

    function _computeAndCollectProtocolSwapFee(
        PoolKey calldata key,
        PoolId id,
        SwapParams calldata params,
        BalanceDelta swapDelta,
        uint256 totalTaxInEther
    ) internal returns (uint256 fee, uint256 lpCompensationAmountInEther) {
        PoolFeeConfiguration storage feeConfiguration = _poolFeeConfiguration[id];
        uint256 totalSwapFeeRateE6 =
            feeConfiguration.protocolSwapFeeE6 + feeConfiguration.creatorSwapFeeE6;

        // Compute the total swap fee amount
        bool exactIn = params.amountSpecified < 0;
        uint256 creatorSwapFeeAmount = 0;
        uint256 protocolSwapFeeAmount = 0;
        if (totalSwapFeeRateE6 != 0) {
            int128 unspecifiedDelta =
                exactIn != params.zeroForOne ? swapDelta.amount0() : swapDelta.amount1();
            uint256 absTargetAmount = unspecifiedDelta.abs();
            fee = exactIn
                ? absTargetAmount * totalSwapFeeRateE6 / FACTOR_E6
                : absTargetAmount * FACTOR_E6 / (FACTOR_E6 - totalSwapFeeRateE6) - absTargetAmount;

            // Determine protocol/creator split
            creatorSwapFeeAmount = fee * feeConfiguration.creatorSwapFeeE6 / totalSwapFeeRateE6;
            protocolSwapFeeAmount = fee - creatorSwapFeeAmount;
        }
        Currency feeCurrency = exactIn != params.zeroForOne ? key.currency0 : key.currency1;

        if (totalTaxInEther == 0) {
            UNI_V4.take(feeCurrency, address(this), creatorSwapFeeAmount);
            UNI_V4.take(feeCurrency, FACTORY, protocolSwapFeeAmount);
            return (fee, 0);
        }

        uint256 creatorTaxShareInEther =
            totalTaxInEther * feeConfiguration.creatorTaxFeeE6 / FACTOR_E6;
        uint256 protocolTaxShareInEther =
            totalTaxInEther * feeConfiguration.protocolTaxFeeE6 / FACTOR_E6;
        lpCompensationAmountInEther =
            totalTaxInEther - creatorTaxShareInEther - protocolTaxShareInEther;
        UNI_V4.mint(address(this), NATIVE_CURRENCY_ID, lpCompensationAmountInEther);

        if (feeCurrency == NATIVE_CURRENCY) {
            UNI_V4.take(
                NATIVE_CURRENCY, address(this), creatorSwapFeeAmount + creatorTaxShareInEther
            );
            UNI_V4.take(NATIVE_CURRENCY, FACTORY, protocolSwapFeeAmount + protocolTaxShareInEther);
        } else {
            UNI_V4.take(NATIVE_CURRENCY, address(this), creatorTaxShareInEther);
            UNI_V4.take(NATIVE_CURRENCY, FACTORY, protocolTaxShareInEther);
            UNI_V4.take(feeCurrency, address(this), creatorSwapFeeAmount);
            UNI_V4.take(feeCurrency, FACTORY, protocolSwapFeeAmount);
        }
    }

    function _zeroForOneDistributeTax(
        PoolId id,
        int24 tickSpacing,
        Slot0 slot0BeforeSwap,
        Slot0 slot0AfterSwap,
        uint256 lpCompensationAmount
    ) internal {
        TickIteratorDown memory ticks = TickIteratorLib.initDown(
            UNI_V4, id, tickSpacing, slot0BeforeSwap.tick(), slot0AfterSwap.tick()
        );

        uint128 liquidity = liquidityBeforeSwap.get().toUint128();
        (int24 lastTick, uint160 pstarSqrtX96) = CompensationPriceFinder.getZeroForOne(
            ticks, liquidity, lpCompensationAmount, slot0BeforeSwap.sqrtPriceX96(), slot0AfterSwap
        );

        ticks.reset(slot0BeforeSwap.tick());
        _zeroForOneCreditRewards(
            ticks,
            liquidity,
            lpCompensationAmount,
            slot0BeforeSwap.sqrtPriceX96(),
            lastTick,
            pstarSqrtX96
        );
    }

    function _oneForZeroDistributeTax(
        PoolId id,
        int24 tickSpacing,
        Slot0 slot0BeforeSwap,
        Slot0 slot0AfterSwap,
        uint256 lpCompensationAmount
    ) internal {
        TickIteratorUp memory ticks = TickIteratorLib.initUp(
            UNI_V4, id, tickSpacing, slot0BeforeSwap.tick(), slot0AfterSwap.tick()
        );

        uint128 liquidity = liquidityBeforeSwap.get().toUint128();
        (int24 lastTick, uint160 pstarSqrtX96) = CompensationPriceFinder.getOneForZero(
            ticks, liquidity, lpCompensationAmount, slot0BeforeSwap, slot0AfterSwap
        );

        ticks.reset(slot0BeforeSwap.tick());
        _oneForZeroCreditRewards(
            ticks,
            liquidity,
            lpCompensationAmount,
            slot0BeforeSwap.sqrtPriceX96(),
            lastTick,
            pstarSqrtX96
        );
    }

    function _zeroForOneCreditRewards(
        TickIteratorDown memory ticks,
        uint128 liquidity,
        uint256 lpCompensationAmount,
        uint160 priceUpperSqrtX96,
        int24 lastTick,
        uint160 pstarSqrtX96
    ) internal {
        uint256 pstarX96 = uint256(pstarSqrtX96).mulX96(pstarSqrtX96);
        uint256 cumulativeGrowthX128 = 0;
        uint160 priceLowerSqrtX96;

        while (ticks.hasNext()) {
            int24 tickNext = ticks.getNext();

            priceLowerSqrtX96 = max(TickMath.getSqrtPriceAtTick(tickNext), pstarSqrtX96);

            uint256 rangeReward = 0;
            if (tickNext >= lastTick && liquidity != 0) {
                uint256 delta0 = SqrtPriceMath.getAmount0Delta(
                    priceLowerSqrtX96, priceUpperSqrtX96, liquidity, false
                );
                uint256 delta1 = SqrtPriceMath.getAmount1Delta(
                    priceLowerSqrtX96, priceUpperSqrtX96, liquidity, false
                );
                rangeReward = (delta1.divX96(pstarX96) - delta0).min(lpCompensationAmount);

                unchecked {
                    lpCompensationAmount -= rangeReward;
                    cumulativeGrowthX128 += PoolRewardsLib.getGrowthDelta(rangeReward, liquidity);
                }
            }

            unchecked {
                rewards[ticks.poolId].rewardGrowthOutsideX128[tickNext] += cumulativeGrowthX128;
            }

            (, int128 liquidityNet) = ticks.manager.getTickLiquidity(ticks.poolId, tickNext);
            liquidity = liquidity.sub(liquidityNet);

            priceUpperSqrtX96 = priceLowerSqrtX96;
        }

        // Distribute remainder to last range and update global accumulator.
        unchecked {
            cumulativeGrowthX128 += PoolRewardsLib.getGrowthDelta(lpCompensationAmount, liquidity);
            rewards[ticks.poolId].globalGrowthX128 += cumulativeGrowthX128;
        }
    }

    function _oneForZeroCreditRewards(
        TickIteratorUp memory ticks,
        uint128 liquidity,
        uint256 lpCompensationAmount,
        uint160 priceLowerSqrtX96,
        int24 lastTick,
        uint160 pstarSqrtX96
    ) internal {
        uint256 pstarX96 = uint256(pstarSqrtX96).mulX96(pstarSqrtX96);
        uint256 cumulativeGrowthX128 = 0;
        uint160 priceUpperSqrtX96;

        while (ticks.hasNext()) {
            int24 tickNext = ticks.getNext();

            priceUpperSqrtX96 = min(TickMath.getSqrtPriceAtTick(tickNext), pstarSqrtX96);

            uint256 rangeReward = 0;
            if (tickNext <= lastTick || liquidity == 0) {
                uint256 delta0 = SqrtPriceMath.getAmount0Delta(
                    priceLowerSqrtX96, priceUpperSqrtX96, liquidity, false
                );
                uint256 delta1 = SqrtPriceMath.getAmount1Delta(
                    priceLowerSqrtX96, priceUpperSqrtX96, liquidity, false
                );
                rangeReward = (delta0 - delta1.divX96(pstarX96)).min(lpCompensationAmount);

                unchecked {
                    lpCompensationAmount -= rangeReward;
                    cumulativeGrowthX128 += PoolRewardsLib.getGrowthDelta(rangeReward, liquidity);
                }
            }

            unchecked {
                rewards[ticks.poolId].rewardGrowthOutsideX128[tickNext] += cumulativeGrowthX128;
            }

            (, int128 liquidityNet) = ticks.manager.getTickLiquidity(ticks.poolId, tickNext);
            liquidity = liquidity.add(liquidityNet);

            priceLowerSqrtX96 = priceUpperSqrtX96;
        }

        // Distribute remainder to last range and update global accumulator.
        unchecked {
            cumulativeGrowthX128 += PoolRewardsLib.getGrowthDelta(lpCompensationAmount, liquidity);
            rewards[ticks.poolId].globalGrowthX128 += cumulativeGrowthX128;
        }
    }

    function min(uint160 x, uint160 y) internal pure returns (uint160) {
        return x < y ? x : y;
    }

    function max(uint160 x, uint160 y) internal pure returns (uint160) {
        return x > y ? x : y;
    }

    function _getBlock() internal view returns (uint96) {
        if (address(flashBlockNumberProvider) == address(0)) {
            return uint96(block.number);
        }
        return uint96(flashBlockNumberProvider.getFlashblockNumber());
    }

    function _getSwapTaxAmount() internal view returns (uint256) {
        uint256 priorityFee = tx.gasprice - block.basefee;
        return getSwapTaxAmount(priorityFee);
    }

    function _getJitTaxAmount() internal view returns (uint256) {
        if (_getBlock() == _blockOfLastTopOfBlock) {
            return 0;
        }
        uint256 priorityFee = tx.gasprice - block.basefee;
        return getJitTaxAmount(priorityFee);
    }

    function _checkCallerIsFactory() internal view {
        if (msg.sender != FACTORY) revert Unauthorized();
    }
}
