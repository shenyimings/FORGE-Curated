// SPDX-License-Identifier: BUSL-1.1
// Likwid Contracts
pragma solidity 0.8.28;

import {Currency, CurrencyLibrary} from "./types/Currency.sol";
import {PoolKey} from "./types/PoolKey.sol";
import {MarginBalanceDelta} from "./types/MarginBalanceDelta.sol";
import {BalanceDelta, toBalanceDelta, BalanceDeltaLibrary} from "./types/BalanceDelta.sol";
import {PoolId} from "./types/PoolId.sol";
import {FeeTypes} from "./types/FeeTypes.sol";
import {MarginActions} from "./types/MarginActions.sol";
import {IVault} from "./interfaces/IVault.sol";
import {IUnlockCallback} from "./interfaces/callback/IUnlockCallback.sol";
import {SafeCast} from "./libraries/SafeCast.sol";
import {CurrencyGuard} from "./libraries/CurrencyGuard.sol";
import {Pool} from "./libraries/Pool.sol";
import {ERC6909Claims} from "./base/ERC6909Claims.sol";
import {NoDelegateCall} from "./base/NoDelegateCall.sol";
import {ProtocolFees} from "./base/ProtocolFees.sol";
import {Extsload} from "./base/Extsload.sol";
import {Exttload} from "./base/Exttload.sol";
import {CustomRevert} from "./libraries/CustomRevert.sol";

/// @title Likwid vault
/// @notice Holds the property for all likwid pools
contract LikwidVault is IVault, ProtocolFees, NoDelegateCall, ERC6909Claims, Extsload, Exttload {
    using CustomRevert for bytes4;
    using SafeCast for *;
    using CurrencyGuard for Currency;
    using BalanceDeltaLibrary for BalanceDelta;
    using Pool for Pool.State;

    mapping(PoolId id => Pool.State) private _pools;

    /// transient storage
    bool transient unlocked;
    uint256 transient nonzeroDeltaCount;

    /// @notice This will revert if the contract is locked
    modifier onlyWhenUnlocked() {
        if (!unlocked) VaultLocked.selector.revertWith();
        _;
    }

    constructor(address initialOwner) ProtocolFees(initialOwner) {
        protocolFeeController = initialOwner;
    }

    /// @inheritdoc IVault
    function unlock(bytes calldata data) external override returns (bytes memory result) {
        if (unlocked) revert AlreadyUnlocked();

        unlocked = true;

        // the caller does everything in this callback, including paying what they owe via calls to settle
        result = IUnlockCallback(msg.sender).unlockCallback(data);

        if (nonzeroDeltaCount != 0) revert CurrencyNotSettled();
        unlocked = false;
    }

    /// @inheritdoc IVault
    function initialize(PoolKey memory key) external noDelegateCall {
        if (key.currency0 >= key.currency1) {
            CurrenciesOutOfOrderOrEqual.selector.revertWith(
                Currency.unwrap(key.currency0), Currency.unwrap(key.currency1)
            );
        }

        PoolId id = key.toId();
        _pools[id].initialize(key.fee);
        emit Initialize(id, key.currency0, key.currency1, key.fee);
    }

    /// @inheritdoc IVault
    function modifyLiquidity(PoolKey memory key, IVault.ModifyLiquidityParams memory params)
        external
        onlyWhenUnlocked
        noDelegateCall
        returns (BalanceDelta callerDelta, int128 finalLiquidityDelta)
    {
        Pool.State storage pool = _getAndUpdatePool(key);
        pool.checkPoolInitialized();
        PoolId id = key.toId();

        uint256 liquidityBefore = pool.slot0.totalSupply();

        (callerDelta, finalLiquidityDelta) = pool.modifyLiquidity(
            Pool.ModifyLiquidityParams({
                owner: msg.sender,
                amount0: params.amount0,
                amount1: params.amount1,
                liquidityDelta: params.liquidityDelta.toInt128(),
                salt: params.salt
            })
        );

        uint256 liquidityAfter = pool.slot0.totalSupply();

        if (liquidityAfter > liquidityBefore) {
            _handleAddLiquidity(id, liquidityAfter - liquidityBefore);
        } else if (liquidityAfter < liquidityBefore) {
            _handleRemoveLiquidity(id, liquidityBefore - liquidityAfter);
        }
        int256 liquidityDelta = liquidityAfter.toInt256() - liquidityBefore.toInt256();
        emit ModifyLiquidity(id, msg.sender, BalanceDelta.unwrap(callerDelta), liquidityDelta, params.salt);
        _appendPoolBalanceDelta(key, msg.sender, callerDelta);
    }

    /// @inheritdoc IVault
    function swap(PoolKey memory key, IVault.SwapParams memory params)
        external
        onlyWhenUnlocked
        noDelegateCall
        returns (BalanceDelta swapDelta, uint24 swapFee, uint256 feeAmount)
    {
        if (params.amountSpecified == 0) AmountCannotBeZero.selector.revertWith();

        PoolId id = key.toId();
        Pool.State storage pool = _getAndUpdatePool(key);
        pool.checkPoolInitialized();
        uint256 amountToProtocol;
        (swapDelta, amountToProtocol, swapFee, feeAmount) = pool.swap(
            Pool.SwapParams({
                sender: msg.sender,
                zeroForOne: params.zeroForOne,
                amountSpecified: params.amountSpecified,
                useMirror: params.useMirror,
                salt: params.salt
            }),
            defaultProtocolFee
        );
        if (params.useMirror) {
            BalanceDelta realDelta;
            int128 lendAmount;
            if (params.zeroForOne) {
                realDelta = toBalanceDelta(swapDelta.amount0(), 0);
                lendAmount = -swapDelta.amount1();
            } else {
                realDelta = toBalanceDelta(0, swapDelta.amount1());
                lendAmount = -swapDelta.amount0();
            }
            _appendPoolBalanceDelta(key, msg.sender, realDelta);
            uint256 depositCumulativeLast =
                params.zeroForOne ? pool.deposit1CumulativeLast : pool.deposit0CumulativeLast;
            emit Lend(id, msg.sender, params.zeroForOne, lendAmount, depositCumulativeLast, params.salt);
        } else {
            _appendPoolBalanceDelta(key, msg.sender, swapDelta);
        }

        if (feeAmount > 0) {
            Currency feeCurrency = params.zeroForOne ? key.currency0 : key.currency1;
            if (amountToProtocol > 0) {
                _updateProtocolFees(feeCurrency, amountToProtocol);
            }
            emit Fees(id, feeCurrency, msg.sender, uint8(FeeTypes.SWAP), feeAmount);
        }

        emit Swap(id, msg.sender, swapDelta.amount0(), swapDelta.amount1(), swapFee);
    }

    /// @inheritdoc IVault
    function lend(PoolKey memory key, IVault.LendParams memory params)
        external
        onlyWhenUnlocked
        noDelegateCall
        returns (BalanceDelta lendDelta)
    {
        if (params.lendAmount == 0) AmountCannotBeZero.selector.revertWith();

        PoolId id = key.toId();
        Pool.State storage pool = _getAndUpdatePool(key);
        pool.checkPoolInitialized();
        uint256 depositCumulativeLast;
        (lendDelta, depositCumulativeLast) = pool.lend(
            Pool.LendParams({
                sender: msg.sender,
                lendForOne: params.lendForOne,
                lendAmount: params.lendAmount,
                salt: params.salt
            })
        );

        _appendPoolBalanceDelta(key, msg.sender, lendDelta);
        emit Lend(id, msg.sender, params.lendForOne, params.lendAmount, depositCumulativeLast, params.salt);
    }

    /// @inheritdoc IVault
    function marginBalance(PoolKey memory key, MarginBalanceDelta memory params)
        external
        onlyWhenUnlocked
        onlyManager
        noDelegateCall
        returns (BalanceDelta marginDelta, uint256 feeAmount)
    {
        PoolId id = key.toId();
        Pool.State storage pool = _getAndUpdatePool(key);
        pool.checkPoolInitialized();
        uint256 amountToProtocol;
        (marginDelta, amountToProtocol, feeAmount) = pool.margin(params, defaultProtocolFee);

        (Currency marginCurrency, Currency borrowCurrency) =
            params.marginForOne ? (key.currency1, key.currency0) : (key.currency0, key.currency1);
        if (feeAmount > 0) {
            if (amountToProtocol > 0) {
                _updateProtocolFees(marginCurrency, amountToProtocol);
            }
            emit Fees(id, marginCurrency, msg.sender, uint8(FeeTypes.MARGIN), feeAmount);
        }
        if (params.swapFeeAmount > 0) {
            if (params.action == MarginActions.MARGIN) {
                emit Fees(id, borrowCurrency, msg.sender, uint8(FeeTypes.MARGIN_SWAP), params.swapFeeAmount);
            } else {
                emit Fees(id, marginCurrency, msg.sender, uint8(FeeTypes.MARGIN_CLOSE_SWAP), params.swapFeeAmount);
            }
        }

        _appendPoolBalanceDelta(key, msg.sender, marginDelta);
    }

    /// @inheritdoc IVault
    function sync(Currency currency) external {
        // address(0) is used for the native currency
        if (currency.isAddressZero()) {
            syncedCurrency = CurrencyLibrary.ADDRESS_ZERO;
        } else {
            uint256 balance = currency.balanceOfSelf();
            syncedCurrency = currency;
            syncedReserves = balance;
        }
    }

    /// @inheritdoc IVault
    function take(Currency currency, address to, uint256 amount) external onlyWhenUnlocked {
        unchecked {
            // negation must be safe as amount is not negative
            _appendDelta(currency, msg.sender, -amount.toInt256());
            currency.transfer(to, amount);
        }
    }

    /// @inheritdoc IVault
    function settle() external payable onlyWhenUnlocked returns (uint256) {
        return _settle(msg.sender);
    }

    /// @inheritdoc IVault
    function settleFor(address recipient) external payable onlyWhenUnlocked returns (uint256) {
        return _settle(recipient);
    }

    /// @inheritdoc IVault
    function clear(Currency currency, uint256 amount) external onlyWhenUnlocked {
        int256 current = currency.currentDelta(msg.sender);
        int256 amountDelta = amount.toInt256();
        if (amountDelta != current) revert MustClearExactPositiveDelta();
        // negation must be safe as amountDelta is positive
        unchecked {
            _appendDelta(currency, msg.sender, -(amountDelta));
        }
    }

    /// @inheritdoc IVault
    function mint(address to, uint256 id, uint256 amount) external onlyWhenUnlocked {
        unchecked {
            Currency currency = CurrencyLibrary.fromId(id);
            // negation must be safe as amount is not negative
            _appendDelta(currency, msg.sender, -amount.toInt256());
            _mint(to, currency.toId(), amount);
        }
    }

    /// @inheritdoc IVault
    function burn(address from, uint256 id, uint256 amount) external onlyWhenUnlocked {
        Currency currency = CurrencyLibrary.fromId(id);
        _appendDelta(currency, msg.sender, amount.toInt256());
        _burnFrom(from, currency.toId(), amount);
    }

    /// @notice Settles a user's balance for a specific currency.
    /// @dev Internal function to handle the logic of settling a user's balance.
    /// @param recipient The address of the user to settle the balance for.
    /// @return paid The amount paid to the user.
    function _settle(address recipient) internal returns (uint256 paid) {
        Currency currency = syncedCurrency;

        if (currency.isAddressZero()) {
            paid = msg.value;
        } else {
            if (msg.value > 0) revert NonzeroNativeValue();
            uint256 reservesBefore = syncedReserves;
            uint256 reservesNow = currency.balanceOfSelf();
            paid = reservesNow - reservesBefore;
            syncedCurrency = CurrencyLibrary.ADDRESS_ZERO; // reset synced currency
        }

        _appendDelta(currency, recipient, paid.toInt256());
    }

    /// @notice Appends a balance delta in a currency for a target address
    /// @param currency The currency to update the balance for.
    /// @param target The address whose balance is to be updated.
    /// @param delta The change in balance.
    function _appendDelta(Currency currency, address target, int256 delta) internal {
        if (delta == 0) return;

        (int256 previous, int256 current) = currency.appendDelta(target, delta.toInt128());

        if (current == 0) {
            nonzeroDeltaCount -= 1;
        } else if (previous == 0) {
            nonzeroDeltaCount += 1;
        }
    }

    /// @notice Appends the deltas of 2 currencies to a target address
    /// @param key The key of the pool.
    /// @param target The address whose balance is to be updated.
    /// @param delta The change in balance for both currencies.
    function _appendPoolBalanceDelta(PoolKey memory key, address target, BalanceDelta delta) internal {
        _appendDelta(key.currency0, target, delta.amount0());
        _appendDelta(key.currency1, target, delta.amount1());
    }

    /// @notice Implementation of the _getAndUpdatePool function defined in ProtocolFees
    /// @param key The key of the pool to retrieve.
    /// @return _pool The state of the pool.
    function _getAndUpdatePool(PoolKey memory key) internal override returns (Pool.State storage _pool) {
        PoolId id = key.toId();
        _pool = _pools[id];
        (uint256 pairInterest0, uint256 pairInterest1) = _pool.updateInterests(marginState, defaultProtocolFee);
        if (pairInterest0 > 0) {
            emit Fees(id, key.currency0, address(this), uint8(FeeTypes.INTERESTS), pairInterest0);
        }
        if (pairInterest1 > 0) {
            emit Fees(id, key.currency1, address(this), uint8(FeeTypes.INTERESTS), pairInterest1);
        }
    }

    /// @notice Implementation of the _isUnlocked function defined in ProtocolFees
    /// @return A boolean indicating whether the contract is unlocked.
    function _isUnlocked() internal view override returns (bool) {
        return unlocked;
    }
}
