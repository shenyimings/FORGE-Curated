// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IMaverickV2Pool {
    struct State {
        uint128 reserveA;
        uint128 reserveB;
        int64 lastTwaD8;
        int64 lastLogPriceD8;
        uint40 lastTimestamp;
        int32 activeTick;
        bool isLocked;
        uint32 binCounter;
        uint8 protocolFeeRatioD3;
    }
    struct TickState {
        uint128 reserveA;
        uint128 reserveB;
        uint128 totalSupply;
        uint32[4] binIdsByTick;
    }
    struct BinState {
        uint128 mergeBinBalance;
        uint128 tickBalance;
        uint128 totalSupply;
        uint8 kind;
        int32 tick;
        uint32 mergeId;
    }
    struct SwapParams {
        uint256 amount;
        bool tokenAIn;
        bool exactOutput;
        int32 tickLimit;
    }
    function getState() external view returns (State memory);

    function swap(address recipient, SwapParams memory params, bytes calldata data)
    external
    returns (uint256 amountIn, uint256 amountOut);
}

interface IMaverickV2SwapCallback {
    function maverickV2SwapCallback(
        IERC20 tokenIn,
        uint256 amountIn,
        uint256 amountOut,
        bytes calldata data
    ) external;
}

interface IMaverickV2Factory {
    function isFactoryPool(address pool) external view returns (bool);
}
