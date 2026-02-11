// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;
pragma abicoder v1;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeCast.sol";
import "../Errors.sol";
import "../interfaces/MaverickV2.sol";
import "../Constants.sol";

abstract contract CowMaverickV2Executor is IMaverickV2SwapCallback {
    using SafeERC20 for IERC20;
    using SafeCast for uint256;

    IMaverickV2Factory private constant FACTORY = IMaverickV2Factory(MAVERICKV2_FACTORY);

    function maverickV2SwapCallback(
        IERC20 tokenIn,
        uint256 amountIn,
        uint256 amountOut,
        bytes calldata data
    ) external override {
        bool isBadPool = !FACTORY.isFactoryPool(msg.sender);

        if (isBadPool) {
            revert BadUniswapV3LikePool(UniswapV3LikeProtocol.MaverickV2);
        }

        uint256 minReturn;
        address cowSettlement;

        assembly {
            minReturn := calldataload(data.offset)
            cowSettlement := calldataload(add(data.offset, 0x20))
        }

        if (amountOut < minReturn) {
            revert MinReturnError(amountOut, minReturn);
        }

        tokenIn.safeTransferFrom(cowSettlement, msg.sender, amountIn);
    }
}
