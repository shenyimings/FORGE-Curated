// SPDX-License-Identifier: GPL-3.0

/*
    This file is part of the Enzyme Protocol.
    (c) Enzyme Foundation <security@enzyme.finance>
    For the full license information, please view the LICENSE
    file that was distributed with this source code.
*/

import {IExternalPosition} from "../../IExternalPosition.sol";

pragma solidity >=0.6.0 <0.9.0;

/// @title IMorphoBluePosition Interface
/// @author Enzyme Foundation <security@enzyme.finance>
interface IMorphoBluePosition is IExternalPosition {
    enum Actions {
        Lend,
        Redeem,
        AddCollateral,
        RemoveCollateral,
        Borrow,
        Repay
    }

    function getMarketIds() external view returns (bytes32[] memory marketIds_);
}
