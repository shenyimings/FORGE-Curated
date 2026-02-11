// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {FeeTypes} from "../types/FeeTypes.sol";
import {Currency} from "../types/Currency.sol";
import {IProtocolFees} from "../interfaces/IProtocolFees.sol";
import {PoolKey} from "../types/PoolKey.sol";
import {ProtocolFeeLibrary} from "../libraries/ProtocolFeeLibrary.sol";
import {MarginBase} from "./MarginBase.sol";
import {Pool} from "../libraries/Pool.sol";
import {CustomRevert} from "../libraries/CustomRevert.sol";

/// @notice Contract handling the setting and accrual of protocol fees
abstract contract ProtocolFees is IProtocolFees, MarginBase {
    using ProtocolFeeLibrary for uint24;
    using Pool for Pool.State;
    using CustomRevert for bytes4;

    Currency transient syncedCurrency;
    uint256 transient syncedReserves;

    /// @inheritdoc IProtocolFees
    mapping(Currency currency => uint256 amount) public protocolFeesAccrued;

    /// @inheritdoc IProtocolFees
    address public protocolFeeController;

    uint24 public defaultProtocolFee;

    constructor(address initialOwner) MarginBase(initialOwner) {
        defaultProtocolFee = defaultProtocolFee.setProtocolFee(FeeTypes.SWAP, 20).setProtocolFee(FeeTypes.MARGIN, 40)
            .setProtocolFee(FeeTypes.INTERESTS, 10); // 10% SWAP,20% MARGIN,5% INTERESTS
    }

    /// @inheritdoc IProtocolFees
    function setProtocolFeeController(address controller) external onlyOwner {
        protocolFeeController = controller;
        emit ProtocolFeeControllerUpdated(controller);
    }

    /// @inheritdoc IProtocolFees
    function setDefaultProtocolFee(FeeTypes feeType, uint8 newFee) external onlyOwner {
        uint24 newProtocolFee = defaultProtocolFee.setProtocolFee(feeType, newFee);
        if (!newProtocolFee.isValidProtocolFee()) ProtocolFeeTooLarge.selector.revertWith(newProtocolFee);
        emit DefaultProtocolFeeUpdated(uint8(feeType), newFee);
    }

    /// @inheritdoc IProtocolFees
    function setProtocolFee(PoolKey memory key, FeeTypes feeType, uint8 newFee) external {
        if (msg.sender != protocolFeeController) InvalidCaller.selector.revertWith();
        Pool.State storage pool = _getAndUpdatePool(key);
        uint24 newProtocolFee = pool.slot0.protocolFee(defaultProtocolFee).setProtocolFee(feeType, newFee);
        if (!newProtocolFee.isValidProtocolFee()) ProtocolFeeTooLarge.selector.revertWith(newProtocolFee);
        pool.setProtocolFee(newProtocolFee);
        emit ProtocolFeeUpdated(key.toId(), newProtocolFee);
    }

    /// @inheritdoc IProtocolFees
    function collectProtocolFees(address recipient, Currency currency, uint256 amount)
        external
        returns (uint256 amountCollected)
    {
        if (msg.sender != protocolFeeController) InvalidCaller.selector.revertWith();
        if (!currency.isAddressZero() && syncedCurrency == currency) {
            // prevent transfer between the sync and settle balanceOfs (native settle uses msg.value)
            ProtocolFeeCurrencySynced.selector.revertWith();
        }

        amountCollected = (amount == 0) ? protocolFeesAccrued[currency] : amount;
        protocolFeesAccrued[currency] -= amountCollected;
        currency.transfer(recipient, amountCollected);
    }

    /// @dev abstract internal function to allow the ProtocolFees contract to access the lock
    function _isUnlocked() internal virtual returns (bool);

    /// @dev abstract internal function to allow the ProtocolFees contract to access pool state
    function _getAndUpdatePool(PoolKey memory key) internal virtual returns (Pool.State storage);

    function _updateProtocolFees(Currency currency, uint256 amount) internal {
        unchecked {
            protocolFeesAccrued[currency] += amount;
        }
    }
}
