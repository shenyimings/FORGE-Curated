// SPDX-License-Identifier: GPL-3.0

/*
    This file is part of the Enzyme Protocol.

    (c) Enzyme Foundation <security@enzyme.finance>

    For the full license information, please view the LICENSE
    file that was distributed with this source code.
*/

pragma solidity >=0.6.0 <0.9.0;

import {IGMXV2Prices} from "./IGMXV2Prices.sol";

/// @title IGMXV2OrderHandler Interface
/// @author Enzyme Foundation <security@enzyme.finance>
interface IGMXV2OrderHandler {
    function orderVault() external view returns (address orderVault_);

    function executeOrder(bytes32 _orderKey, IGMXV2Prices.SetPricesParams calldata _oracleParams) external;
}
