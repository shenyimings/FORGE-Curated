// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {PoolKey} from "v4-core/src/types/PoolKey.sol";

/// @author philogy <https://github.com/philogy>
interface IAngstromL2Hook {
    function setProtocolSwapFee(PoolKey calldata key, uint256 newFeeE6) external;
    function setProtocolTaxFee(PoolKey calldata key, uint256 newFeeE6) external;
    function initializeNewPool(
        PoolKey calldata key,
        uint160 sqrtPriceX96,
        uint24 creatorSwapFeeE6,
        uint24 creatorTaxFeeE6
    ) external;
}
