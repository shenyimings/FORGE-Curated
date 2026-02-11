/*
    This file is part of the Enzyme Protocol.

    (c) Enzyme Foundation <security@enzyme.finance>

    For the full license information, please view the LICENSE
    file that was distributed with this source code.
*/

// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.6.0 <0.9.0;

/// @title IAliceOrderManager Interface
/// @author Enzyme Foundation <security@enzyme.finance>
interface IAliceOrderManager {
    struct Instrument {
        uint16 id;
        bool enabled;
        address base;
        address quote;
    }

    function getInstrument(uint16 _instrumentId, bool _mustBeActive)
        external
        view
        returns (Instrument memory instrument_);

    function getMostRecentOrderId() external view returns (uint256 orderId_);

    function getOrderHash(uint256 _orderId) external view returns (bytes32 orderHash_);

    function placeOrder(uint16 _instrumentId, bool _isBuyOrder, uint256 _quantityToSell, uint256 _limitAmountToGet)
        external
        payable;

    function refundOrder(
        uint256 _orderId,
        address _user,
        uint16 _instrumentId,
        bool _isBuyOrder,
        uint256 _quantityToSell,
        uint256 _limitAmountToGet,
        uint256 _timestamp
    ) external;
}
