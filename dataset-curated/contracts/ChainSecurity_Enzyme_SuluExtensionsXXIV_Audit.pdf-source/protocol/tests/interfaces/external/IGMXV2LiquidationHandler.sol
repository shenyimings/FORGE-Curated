// SPDX-License-Identifier: GPL-3.0

/*
    This file is part of the Enzyme Protocol.

    (c) Enzyme Foundation <security@enzyme.finance>

    For the full license information, please view the LICENSE
    file that was distributed with this source code.
*/

pragma solidity >=0.6.0 <0.9.0;

import {IGMXV2Prices} from "./IGMXV2Prices.sol";

/// @title IGMXV2LiquidationHandler Interface
/// @author Enzyme Foundation <security@enzyme.finance>
interface IGMXV2LiquidationHandler {
    function executeLiquidation(
        address _account,
        address _market,
        address _collateralToken,
        bool _isLong,
        IGMXV2Prices.SetPricesParams calldata _oracleParams
    ) external;
}
