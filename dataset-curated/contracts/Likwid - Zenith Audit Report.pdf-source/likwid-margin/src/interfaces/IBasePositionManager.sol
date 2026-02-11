// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {PoolId} from "../types/PoolId.sol";
import {IImmutableState} from "./IImmutableState.sol";

interface IBasePositionManager is IImmutableState {
    error NotOwner();

    error InvalidCallback();

    error PriceSlippageTooHigh();

    error MismatchedPoolKey();

    function poolIds(uint256 tokenId) external view returns (PoolId poolId);
}
