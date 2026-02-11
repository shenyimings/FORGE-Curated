// SPDX-License-Identifier: BUSL-1.1
// Likwid Contracts
pragma solidity ^0.8.26;

// Local
import {Math} from "./libraries/Math.sol";
import {BasePositionManager} from "./base/BasePositionManager.sol";
import {PoolKey} from "./types/PoolKey.sol";
import {PoolId} from "./types/PoolId.sol";
import {Currency} from "./types/Currency.sol";
import {BalanceDelta} from "./types/BalanceDelta.sol";
import {IVault} from "./interfaces/IVault.sol";
import {ILendPositionManager} from "./interfaces/ILendPositionManager.sol";
import {LendPosition} from "./libraries/LendPosition.sol";
import {StateLibrary} from "./libraries/StateLibrary.sol";
import {CustomRevert} from "./libraries/CustomRevert.sol";
import {CurrencyPoolLibrary} from "./libraries/CurrencyPoolLibrary.sol";
import {SafeCast} from "./libraries/SafeCast.sol";

contract LikwidLendPosition is ILendPositionManager, BasePositionManager {
    using CurrencyPoolLibrary for Currency;
    using CustomRevert for bytes4;
    using SafeCast for *;

    mapping(uint256 tokenId => bool lendForOne) public lendDirections;

    constructor(address initialOwner, IVault _vault)
        BasePositionManager("LIKWIDLendPositionManager", "LLPM", initialOwner, _vault)
    {}

    enum Actions {
        DEPOSIT,
        WITHDRAW,
        SWAP
    }

    function unlockCallback(bytes calldata data) external override returns (bytes memory) {
        (Actions action, bytes memory params) = abi.decode(data, (Actions, bytes));

        if (action == Actions.DEPOSIT) {
            return handleLend(params);
        } else if (action == Actions.WITHDRAW) {
            return handleLend(params);
        } else if (action == Actions.SWAP) {
            return handleSwap(params);
        } else {
            InvalidCallback.selector.revertWith();
        }
    }

    /// @inheritdoc ILendPositionManager
    function getPositionState(uint256 tokenId) external view returns (LendPosition.State memory position) {
        bytes32 salt = bytes32(tokenId);
        PoolId poolId = poolIds[tokenId];
        bool lendForOne = lendDirections[tokenId];
        (,, uint256 deposit0CumulativeLast, uint256 deposit1CumulativeLast) =
            StateLibrary.getBorrowDepositCumulative(vault, poolId);
        uint256 depositCumulativeLast = lendForOne ? deposit1CumulativeLast : deposit0CumulativeLast;
        position = StateLibrary.getLendPositionState(vault, poolId, address(this), lendForOne, salt);
        position.lendAmount = Math.mulDiv(
            position.lendAmount,
            depositCumulativeLast,
            position.depositCumulativeLast == 0 ? depositCumulativeLast : position.depositCumulativeLast
        ).toUint128();
        position.depositCumulativeLast = depositCumulativeLast;
    }

    /// @inheritdoc ILendPositionManager
    function addLending(PoolKey memory key, bool lendForOne, address recipient, uint256 amount)
        external
        payable
        returns (uint256 tokenId)
    {
        tokenId = _mintPosition(key, recipient);
        lendDirections[tokenId] = lendForOne;
        if (amount > 0) {
            _deposit(msg.sender, recipient, tokenId, amount);
        }
    }

    function _deposit(address sender, address tokenOwner, uint256 tokenId, uint256 amount) internal {
        _requireAuth(tokenOwner, tokenId);
        PoolId poolId = poolIds[tokenId];
        bool lendForOne = lendDirections[tokenId];
        PoolKey memory key = poolKeys[poolId];

        IVault.LendParams memory params =
            IVault.LendParams({lendForOne: lendForOne, lendAmount: -amount.toInt128(), salt: bytes32(tokenId)});

        bytes memory callbackData = abi.encode(sender, key, params);
        bytes memory data = abi.encode(Actions.DEPOSIT, callbackData);

        vault.unlock(data);
        Currency currency = lendForOne ? key.currency1 : key.currency0;
        emit Deposit(poolId, currency, sender, tokenId, tokenOwner, amount);
    }

    /// @inheritdoc ILendPositionManager
    function deposit(uint256 tokenId, uint256 amount) external payable {
        _deposit(msg.sender, msg.sender, tokenId, amount);
    }

    /// @inheritdoc ILendPositionManager
    function withdraw(uint256 tokenId, uint256 amount) external {
        _requireAuth(msg.sender, tokenId);
        PoolId poolId = poolIds[tokenId];
        bool lendForOne = lendDirections[tokenId];
        PoolKey memory key = poolKeys[poolId];

        IVault.LendParams memory params =
            IVault.LendParams({lendForOne: lendForOne, lendAmount: amount.toInt128(), salt: bytes32(tokenId)});

        bytes memory callbackData = abi.encode(msg.sender, key, params);
        bytes memory data = abi.encode(Actions.WITHDRAW, callbackData);

        vault.unlock(data);
        Currency currency = lendForOne ? key.currency1 : key.currency0;
        emit Withdraw(poolId, currency, msg.sender, tokenId, msg.sender, amount);
    }

    function handleLend(bytes memory _data) internal returns (bytes memory) {
        (address sender, PoolKey memory key, IVault.LendParams memory params) =
            abi.decode(_data, (address, PoolKey, IVault.LendParams));

        BalanceDelta delta = vault.lend(key, params);

        (uint256 amount0, uint256 amount1) = _processDelta(sender, key, delta, 0, 0, 0, 0);

        return abi.encode(amount0, amount1);
    }

    /// @inheritdoc ILendPositionManager
    function exactInput(SwapInputParams calldata params)
        external
        payable
        ensure(params.deadline)
        returns (uint24 swapFee, uint256 feeAmount, uint256 amountOut)
    {
        _requireAuth(msg.sender, params.tokenId);
        PoolKey memory key = poolKeys[params.poolId];
        if (params.zeroForOne != lendDirections[params.tokenId]) {
            InvalidCurrency.selector.revertWith();
        }
        int256 amountSpecified = -int256(params.amountIn);
        IVault.SwapParams memory swapParams = IVault.SwapParams({
            zeroForOne: params.zeroForOne,
            amountSpecified: amountSpecified,
            useMirror: true,
            salt: bytes32(params.tokenId)
        });
        uint256 amount0Min = params.zeroForOne ? 0 : params.amountOutMin;
        uint256 amount1Min = params.zeroForOne ? params.amountOutMin : 0;
        bytes memory callbackData = abi.encode(msg.sender, key, swapParams, amount0Min, amount1Min, 0, 0);
        bytes memory data = abi.encode(Actions.SWAP, callbackData);

        bytes memory result = vault.unlock(data);
        uint256 amount0;
        uint256 amount1;
        (swapFee, feeAmount, amount0, amount1) = abi.decode(result, (uint24, uint256, uint256, uint256));
        amountOut = params.zeroForOne ? amount1 : amount0;
    }

    /// @inheritdoc ILendPositionManager
    function exactOutput(SwapOutputParams calldata params)
        external
        payable
        ensure(params.deadline)
        returns (uint24 swapFee, uint256 feeAmount, uint256 amountIn)
    {
        _requireAuth(msg.sender, params.tokenId);
        PoolKey memory key = poolKeys[params.poolId];
        if (params.zeroForOne != lendDirections[params.tokenId]) {
            InvalidCurrency.selector.revertWith();
        }
        int256 amountSpecified = int256(params.amountOut);
        IVault.SwapParams memory swapParams = IVault.SwapParams({
            zeroForOne: params.zeroForOne,
            amountSpecified: amountSpecified,
            useMirror: true,
            salt: bytes32(params.tokenId)
        });
        uint256 amount0Max = params.zeroForOne ? params.amountInMax : 0;
        uint256 amount1Max = params.zeroForOne ? 0 : params.amountInMax;
        bytes memory callbackData = abi.encode(msg.sender, key, swapParams, 0, 0, amount0Max, amount1Max);
        bytes memory data = abi.encode(Actions.SWAP, callbackData);

        bytes memory result = vault.unlock(data);
        uint256 amount0;
        uint256 amount1;
        (swapFee, feeAmount, amount0, amount1) = abi.decode(result, (uint24, uint256, uint256, uint256));
        amountIn = params.zeroForOne ? amount0 : amount1;
    }

    function handleSwap(bytes memory _data) internal returns (bytes memory) {
        (
            address sender,
            PoolKey memory key,
            IVault.SwapParams memory params,
            uint256 amount0Min,
            uint256 amount1Min,
            uint256 amount0Max,
            uint256 amount1Max
        ) = abi.decode(_data, (address, PoolKey, IVault.SwapParams, uint256, uint256, uint256, uint256));

        (BalanceDelta delta, uint24 swapFee, uint256 feeAmount) = vault.swap(key, params);

        uint256 amount0;
        uint256 amount1;

        if (params.zeroForOne) {
            if (delta.amount0() < 0) {
                amount0 = uint256(-int256(delta.amount0()));
                if ((amount0Min > 0 && amount0 < amount0Min) || (amount0Max > 0 && amount0 > amount0Max)) {
                    PriceSlippageTooHigh.selector.revertWith();
                }
                key.currency0.settle(vault, sender, amount0, false);
            } else if (delta.amount0() > 0) {
                amount0 = uint256(int256(delta.amount0()));
                if ((amount0Min > 0 && amount0 < amount0Min) || (amount0Max > 0 && amount0 > amount0Max)) {
                    PriceSlippageTooHigh.selector.revertWith();
                }
                key.currency0.take(vault, sender, amount0, false);
            }
            if (delta.amount1() < 0) {
                amount1 = uint256(-int256(delta.amount1()));
                if ((amount1Min > 0 && amount1 < amount1Min) || (amount1Max > 0 && amount1 > amount1Max)) {
                    PriceSlippageTooHigh.selector.revertWith();
                }
            } else if (delta.amount1() > 0) {
                amount1 = uint256(int256(delta.amount1()));
                if ((amount1Min > 0 && amount1 < amount1Min) || (amount1Max > 0 && amount1 > amount1Max)) {
                    PriceSlippageTooHigh.selector.revertWith();
                }
            }
        } else {
            if (delta.amount0() < 0) {
                amount0 = uint256(-int256(delta.amount0()));
                if ((amount0Min > 0 && amount0 < amount0Min) || (amount0Max > 0 && amount0 > amount0Max)) {
                    PriceSlippageTooHigh.selector.revertWith();
                }
            } else if (delta.amount0() > 0) {
                amount0 = uint256(int256(delta.amount0()));
                if ((amount0Min > 0 && amount0 < amount0Min) || (amount0Max > 0 && amount0 > amount0Max)) {
                    PriceSlippageTooHigh.selector.revertWith();
                }
            }
            if (delta.amount1() < 0) {
                amount1 = uint256(-int256(delta.amount1()));
                if ((amount1Min > 0 && amount1 < amount1Min) || (amount1Max > 0 && amount1 > amount1Max)) {
                    PriceSlippageTooHigh.selector.revertWith();
                }
                key.currency1.settle(vault, sender, amount1, false);
            } else if (delta.amount1() > 0) {
                amount1 = uint256(int256(delta.amount1()));
                if ((amount1Min > 0 && amount1 < amount1Min) || (amount1Max > 0 && amount1 > amount1Max)) {
                    PriceSlippageTooHigh.selector.revertWith();
                }
                key.currency1.take(vault, sender, amount1, false);
            }
        }
        _clearNative(sender);

        return abi.encode(swapFee, feeAmount, amount0, amount1);
    }
}
