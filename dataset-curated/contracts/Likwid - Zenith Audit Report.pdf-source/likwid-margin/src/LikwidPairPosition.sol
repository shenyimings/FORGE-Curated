// SPDX-License-Identifier: BUSL-1.1
// Likwid Contracts
pragma solidity ^0.8.26;

// Local
import {BasePositionManager} from "./base/BasePositionManager.sol";
import {PoolKey} from "./types/PoolKey.sol";
import {PoolId} from "./types/PoolId.sol";
import {Currency} from "./types/Currency.sol";
import {BalanceDelta} from "./types/BalanceDelta.sol";
import {IVault} from "./interfaces/IVault.sol";
import {IPairPositionManager} from "./interfaces/IPairPositionManager.sol";
import {PairPosition} from "./libraries/PairPosition.sol";
import {StateLibrary} from "./libraries/StateLibrary.sol";
import {CustomRevert} from "./libraries/CustomRevert.sol";
import {CurrencyPoolLibrary} from "./libraries/CurrencyPoolLibrary.sol";

contract LikwidPairPosition is IPairPositionManager, BasePositionManager {
    using CurrencyPoolLibrary for Currency;
    using CustomRevert for bytes4;

    constructor(address initialOwner, IVault _vault)
        BasePositionManager("LIKWIDPairPositionManager", "LPPM", initialOwner, _vault)
    {}

    enum Actions {
        MODIFY_LIQUIDITY,
        SWAP
    }

    function unlockCallback(bytes calldata data) external override returns (bytes memory) {
        (Actions action, bytes memory params) = abi.decode(data, (Actions, bytes));

        if (action == Actions.MODIFY_LIQUIDITY) {
            return handleModifyLiquidity(params);
        } else if (action == Actions.SWAP) {
            return handleSwap(params);
        } else {
            InvalidCallback.selector.revertWith();
        }
    }

    /// @inheritdoc IPairPositionManager
    function getPositionState(uint256 tokenId) external view returns (PairPosition.State memory) {
        bytes32 salt = bytes32(tokenId);
        PoolId poolId = poolIds[tokenId];
        return StateLibrary.getPairPositionState(vault, poolId, address(this), salt);
    }

    /// @inheritdoc IPairPositionManager
    function addLiquidity(PoolKey memory key, uint256 amount0, uint256 amount1, uint256 amount0Min, uint256 amount1Min)
        external
        payable
        returns (uint256 tokenId, uint128 liquidity)
    {
        tokenId = _mintPosition(key, msg.sender);
        liquidity = _increaseLiquidity(msg.sender, msg.sender, tokenId, amount0, amount1, amount0Min, amount1Min);
    }

    function _increaseLiquidity(
        address sender,
        address tokenOwner,
        uint256 tokenId,
        uint256 amount0,
        uint256 amount1,
        uint256 amount0Min,
        uint256 amount1Min
    ) internal returns (uint128 liquidity) {
        _requireAuth(tokenOwner, tokenId);
        PoolId poolId = poolIds[tokenId];
        if (PoolId.unwrap(poolId) == 0) {
            revert("Invalid tokenId");
        }
        PoolKey memory key = poolKeys[poolId];

        IVault.ModifyLiquidityParams memory params = IVault.ModifyLiquidityParams({
            amount0: amount0,
            amount1: amount1,
            liquidityDelta: 0,
            salt: bytes32(tokenId)
        });

        bytes memory callbackData = abi.encode(sender, key, params, amount0Min, amount1Min);
        bytes memory data = abi.encode(Actions.MODIFY_LIQUIDITY, callbackData);

        bytes memory result = vault.unlock(data);
        (liquidity, amount0, amount1) = abi.decode(result, (uint128, uint256, uint256));
    }

    /// @inheritdoc IPairPositionManager
    function increaseLiquidity(
        uint256 tokenId,
        uint256 amount0,
        uint256 amount1,
        uint256 amount0Min,
        uint256 amount1Min
    ) external payable returns (uint128 liquidity) {
        liquidity = _increaseLiquidity(msg.sender, msg.sender, tokenId, amount0, amount1, amount0Min, amount1Min);
    }

    /// @inheritdoc IPairPositionManager
    function removeLiquidity(uint256 tokenId, uint128 liquidity, uint256 amount0Min, uint256 amount1Min)
        external
        returns (uint256 amount0, uint256 amount1)
    {
        _requireAuth(msg.sender, tokenId);
        PoolId poolId = poolIds[tokenId];
        if (PoolId.unwrap(poolId) == 0) {
            revert("Invalid tokenId");
        }
        PoolKey memory key = poolKeys[poolId];

        IVault.ModifyLiquidityParams memory params = IVault.ModifyLiquidityParams({
            amount0: 0,
            amount1: 0,
            liquidityDelta: -int128(liquidity),
            salt: bytes32(tokenId)
        });

        bytes memory callbackData = abi.encode(msg.sender, key, params, amount0Min, amount1Min);
        bytes memory data = abi.encode(Actions.MODIFY_LIQUIDITY, callbackData);

        bytes memory result = vault.unlock(data);
        (, amount0, amount1) = abi.decode(result, (int128, uint256, uint256));
    }

    function handleModifyLiquidity(bytes memory _data) internal returns (bytes memory) {
        (
            address sender,
            PoolKey memory key,
            IVault.ModifyLiquidityParams memory params,
            uint256 amount0Min,
            uint256 amount1Min
        ) = abi.decode(_data, (address, PoolKey, IVault.ModifyLiquidityParams, uint256, uint256));

        (BalanceDelta delta, int128 finalLiquidityDelta) = vault.modifyLiquidity(key, params);

        (uint256 amount0, uint256 amount1) =
            _processDelta(sender, key, delta, amount0Min, amount1Min, params.amount0, params.amount1);

        emit ModifyLiquidity(key.toId(), uint256(params.salt), sender, finalLiquidityDelta, amount0, amount1);
        return abi.encode(finalLiquidityDelta, amount0, amount1);
    }

    /// @inheritdoc IPairPositionManager
    function exactInput(SwapInputParams calldata params)
        external
        payable
        ensure(params.deadline)
        returns (uint24 swapFee, uint256 feeAmount, uint256 amountOut)
    {
        PoolKey memory key = poolKeys[params.poolId];
        int256 amountSpecified = -int256(params.amountIn);
        IVault.SwapParams memory swapParams = IVault.SwapParams({
            zeroForOne: params.zeroForOne,
            amountSpecified: amountSpecified,
            useMirror: false,
            salt: bytes32(0)
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

    /// @inheritdoc IPairPositionManager
    function exactOutput(SwapOutputParams calldata params)
        external
        payable
        ensure(params.deadline)
        returns (uint24 swapFee, uint256 feeAmount, uint256 amountIn)
    {
        PoolKey memory key = poolKeys[params.poolId];
        int256 amountSpecified = int256(params.amountOut);
        IVault.SwapParams memory swapParams = IVault.SwapParams({
            zeroForOne: params.zeroForOne,
            amountSpecified: amountSpecified,
            useMirror: false,
            salt: bytes32(0)
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

        (uint256 amount0, uint256 amount1) =
            _processDelta(sender, key, delta, amount0Min, amount1Min, amount0Max, amount1Max);

        return abi.encode(swapFee, feeAmount, amount0, amount1);
    }
}
