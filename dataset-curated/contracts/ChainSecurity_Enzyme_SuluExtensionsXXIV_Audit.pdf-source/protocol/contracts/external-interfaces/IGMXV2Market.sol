// SPDX-License-Identifier: GPL-3.0

/*
    This file is part of the Enzyme Protocol.

    (c) Enzyme Foundation <security@enzyme.finance>

    For the full license information, please view the LICENSE
    file that was distributed with this source code.
*/

pragma solidity >=0.6.0 <0.9.0;

import {IGMXV2Price} from "./IGMXV2Price.sol";

/// @title IGMXV2Market interface
/// @author Enzyme Foundation <security@enzyme.finance>
interface IGMXV2Market {
    struct Props {
        address marketToken;
        address indexToken;
        address longToken;
        address shortToken;
    }

    struct MarketPrices {
        IGMXV2Price.Price indexTokenPrice;
        IGMXV2Price.Price longTokenPrice;
        IGMXV2Price.Price shortTokenPrice;
    }
}
