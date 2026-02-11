// SPDX-License-Identifier: GPL-3.0

/*
    This file is part of the Enzyme Protocol.

    (c) Enzyme Foundation <security@enzyme.finance>

    For the full license information, please view the LICENSE
    file that was distributed with this source code.
*/

pragma solidity 0.6.12;

import {PeggedDerivativesPriceFeedBase} from "./utils/PeggedDerivativesPriceFeedBase.sol";

/// @title PeggedDerivativesPriceFeed Contract
/// @author Enzyme Foundation <security@enzyme.finance>
/// @notice Price feed for multiple derivatives that are pegged 1:1 to their underlyings,
/// and have the same decimals as their underlying
contract PeggedDerivativesPriceFeed is PeggedDerivativesPriceFeedBase {
    constructor(address _fundDeployer) public PeggedDerivativesPriceFeedBase(_fundDeployer) {}
}
