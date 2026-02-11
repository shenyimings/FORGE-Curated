// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {IFlashBlockNumber} from "./IFlashBlockNumber.sol";

/// @author philogy <https://github.com/philogy>
interface IFactory {
    function recordPoolCreationAndGetStartingProtocolFee(
        PoolKey calldata key,
        uint24 creatorSwapFeeE6,
        uint24 creatorTaxFeeE6
    ) external returns (uint24 protocolSwapFeeE6, uint24 protocolTaxFeeE6);
    function defaultProtocolSwapFeeAsMultipleE6() external view returns (uint24);
    function defaultProtocolTaxFeeE6() external view returns (uint24);
    function flashBlockNumberProvider() external view returns (IFlashBlockNumber);
}
