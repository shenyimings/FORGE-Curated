// SPDX-License-Identifier: GPL-3.0

/*
    This file is part of the Enzyme Protocol.

    (c) Enzyme Foundation <security@enzyme.finance>

    For the full license information, please view the LICENSE
    file that was distributed with this source code.
*/

pragma solidity 0.8.19;

/// @title AlicePositionLibBase1 Contract
/// @author Enzyme Foundation <security@enzyme.finance>
/// @notice A persistent contract containing all required storage variables and
/// required functions for a AlicePositionLib implementation
/// @dev DO NOT EDIT CONTRACT. If new events or storage are necessary, they should be added to
/// a numbered AlicePositionLibBaseXXX that inherits the previous base.
/// e.g., `AlicePositionLibBase2 is AlicePositionLibBase1`
abstract contract AlicePositionLibBase1 {
    struct OrderDetails {
        address outgoingAssetAddress;
        address incomingAssetAddress;
        uint256 outgoingAmount;
    }

    event OrderIdAdded(uint256 indexed orderId, OrderDetails orderDetails);

    event OrderIdRemoved(uint256 indexed orderId);

    uint256[] internal orderIds;

    mapping(uint256 orderId => OrderDetails) orderIdToOrderDetails;
}
