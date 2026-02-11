// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;
pragma abicoder v1;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeCast.sol";
import "../interfaces/PancakeV3.sol";
import "../Errors.sol";

/**
 * @title PancakeV3Executor
 * @notice Base contract that contains PancakeV3 specific logic.
 * PancakeV3 requires specific interface to be implemented so we have to provide a compliant implementation
 */
abstract contract CowPancakeV3Executor is IPancakeV3SwapCallback {
    using SafeERC20 for IERC20;
    using SafeCast for uint256;

    bytes32 private constant SELECTORS = 0x0dfe1681d21220a7ddca3f430000000000000000000000000000000000000000;
    bytes32 private constant INIT_CODE_HASH = 0x6ce8eb472fa82df5469c6ab6d485f17c3ad13c8cd7af59b3d4a8026c5ce0f7e2;
    bytes32 private constant PREFIXED_DEPLOYER = 0xff41ff9AA7e16B8B1a8a8dc4f0eFacd93D02d071c90000000000000000000000;
    uint256 private constant ADDRESS_MASK = 0x000000000000000000000000ffffffffffffffffffffffffffffffffffffffff;

    function pancakeV3SwapCallback(
        int256 amount0Delta,
        int256 amount1Delta,
        bytes calldata data
    ) external override {
        bool isBadPool;
        uint256 amountIn;
        uint256 amountOut;
        IERC20 token;

        uint256 minReturn;
        address cowSettlement;

        assembly {
            function reRevert() {
                let ptr := mload(0x40)
                returndatacopy(ptr, 0, returndatasize())
                revert(ptr, returndatasize())
            }

            let workingAddress := mload(0x40) // EVM free memory pointer
            mstore(workingAddress, SELECTORS)

            // we need to write hash just after the address PREFIXED_FACTORY constant in place of its zeroes,
            // hence offset is 21 bytes
            let feeTokensAddress := add(workingAddress, 21)
            if iszero(staticcall(gas(), caller(), workingAddress, 0x4, feeTokensAddress, 0x20)) {
                reRevert()
            }
            if iszero(staticcall(gas(), caller(), add(workingAddress, 0x4), 0x4, add(feeTokensAddress, 32), 0x20)) {
                reRevert()
            }
            if iszero(staticcall(gas(), caller(), add(workingAddress, 0x8), 0x4, add(feeTokensAddress, 64), 0x20)) {
                reRevert()
            }

            switch sgt(amount0Delta, 0)
            case 1 {
                amountIn := amount0Delta
                amountOut := sub(0, amount1Delta) // negate
                token := mload(feeTokensAddress)
            }
            default {
                amountIn := amount1Delta
                amountOut := sub(0, amount0Delta) // negate
                token := mload(add(feeTokensAddress, 32))
            }

            mstore(workingAddress, PREFIXED_DEPLOYER)
            mstore(feeTokensAddress, keccak256(feeTokensAddress, 96))
            mstore(add(feeTokensAddress, 32), INIT_CODE_HASH)
            let pool := and(keccak256(workingAddress, 85), ADDRESS_MASK)
            isBadPool := xor(pool, caller())

            minReturn := calldataload(data.offset)
            cowSettlement := calldataload(add(data.offset, 32))
        }

        if (isBadPool) {
            revert BadUniswapV3LikePool(UniswapV3LikeProtocol.Pancake);
        }

        if (amountOut < minReturn) {
            revert MinReturnError(amountOut, minReturn);
        }

        token.safeTransferFrom(cowSettlement, msg.sender, amountIn);
    }
}
