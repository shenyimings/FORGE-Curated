// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.0 <0.9.0;

import {Multicall} from "openzeppelin-contracts/contracts/utils/Multicall.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {IPositionManager} from "../../interfaces/IPositionManager.sol";
import {IHandler} from "../../interfaces/IHandler.sol";
import {IV3Pool} from "../../interfaces/handlers/V3/IV3Pool.sol";
import {ERC6909} from "../../libraries/tokens/ERC6909.sol";
import {IWETH} from "../../interfaces/IWETH.sol";

contract AddLiquidityRouter is Multicall {
    using SafeERC20 for IERC20;

    IPositionManager public immutable positionManager;

    error InvalidDeadline();
    error InvalidTick();
    error InvalidSqrtPriceX96();

    struct RangeCheckData {
        int24 minTickLower;
        int24 maxTickUpper;
        uint160 minSqrtPriceX96;
        uint160 maxSqrtPriceX96;
        uint256 deadline;
    }

    struct PoolData {
        uint160 sqrtPriceX96;
        int24 tick;
    }

    constructor(address _positionManager) {
        positionManager = IPositionManager(_positionManager);
    }

    function addLiquidity(IHandler _handler, bytes calldata _mintPositionData, RangeCheckData calldata _rangeCheckData)
        external
        returns (uint256 sharesMinted)
    {
        if (block.timestamp > _rangeCheckData.deadline) {
            revert InvalidDeadline();
        }

        PoolData memory poolData;
        (, bytes memory result) =
            address(abi.decode(_mintPositionData, (address))).staticcall(abi.encodeWithSignature("slot0()"));
        (poolData.sqrtPriceX96, poolData.tick) = abi.decode(result, (uint160, int24));

        if (poolData.tick < _rangeCheckData.minTickLower || poolData.tick > _rangeCheckData.maxTickUpper) {
            revert InvalidTick();
        }

        if (
            poolData.sqrtPriceX96 < _rangeCheckData.minSqrtPriceX96
                || poolData.sqrtPriceX96 > _rangeCheckData.maxSqrtPriceX96
        ) {
            revert InvalidSqrtPriceX96();
        }

        (address[] memory tokens, uint256[] memory amounts) = _handler.tokensToPullForMint(_mintPositionData);

        uint256 amount;
        for (uint256 i; i < tokens.length; i++) {
            amount = amounts[i];
            if (amount != 0) {
                IERC20(tokens[i]).safeTransferFrom(msg.sender, address(this), amount);
                IERC20(tokens[i]).safeIncreaseAllowance(address(positionManager), amount);
            }
        }

        sharesMinted = positionManager.mintPosition(_handler, _mintPositionData);

        uint256 tokenId = _handler.getHandlerIdentifier(_mintPositionData);

        ERC6909(address(_handler)).transferFrom(
            address(this), msg.sender, tokenId, ERC6909(address(_handler)).balanceOf(address(this), tokenId)
        );
    }

    function wrap(address weth, uint256 amount) external payable {
        IWETH(weth).deposit{value: amount}();
        IERC20(weth).safeTransfer(msg.sender, amount);
    }

    function sweep(address _token) external {
        uint256 balance = IERC20(_token).balanceOf(address(this));
        if (balance > 0) {
            IERC20(_token).safeTransfer(msg.sender, balance);
        }
    }
}
