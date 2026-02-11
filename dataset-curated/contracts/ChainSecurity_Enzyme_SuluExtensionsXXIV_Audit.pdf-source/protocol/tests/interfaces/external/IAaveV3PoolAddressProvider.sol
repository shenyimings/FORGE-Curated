// SPDX-License-Identifier: GPL-3.0

/*
    This file is part of the Enzyme Protocol.

    (c) Enzyme Foundation <security@enzyme.finance>

    For the full license information, please view the LICENSE
    file that was distributed with this source code.
*/

pragma solidity >=0.6.0 <0.9.0;

import {IAaveV3Pool} from "./IAaveV3Pool.sol";
/// @title IAaveV3PoolAddressProvider interface
/// @author Enzyme Foundation <security@enzyme.finance>

interface IAaveV3PoolAddressProvider {
    function getPool() external view returns (IAaveV3Pool pool_);

    function getPriceOracle() external view returns (address priceOracleAddress_);
}
