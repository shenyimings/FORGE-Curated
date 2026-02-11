// Copyright (c) 2025 Merge Layers Inc.
//
// This source code is licensed under the Business Source License 1.1
// (the "License"); you may not use this file except in compliance with the
// License. You may obtain a copy of the License at
//
//     https://github.com/malda-protocol/malda-lending/blob/main/LICENSE-BSL
//
// See the License for the specific language governing permissions and
// limitations under the License.
//
// This file contains code derived from or inspired by Compound V2,
// originally licensed under the BSD 3-Clause License. See LICENSE-COMPOUND-V2
// for original license terms and attributions.

// SPDX-License-Identifier: BSL-1.1
pragma solidity =0.8.28;

/*
 _____ _____ __    ____  _____ 
|     |  _  |  |  |    \|  _  |
| | | |     |  |__|  |  |     |
|_|_|_|__|__|_____|____/|__|__|   
*/

// interfaces
import {IRoles} from "src/interfaces/IRoles.sol";
import {IOperator} from "src/interfaces/IOperator.sol";
import {IInterestRateModel} from "src/interfaces/IInterestRateModel.sol";

import {mTokenStorage} from "./mTokenStorage.sol";

abstract contract mTokenConfiguration is mTokenStorage {
    // ----------- MODIFIERS ------------
    modifier onlyAdmin() {
        require(msg.sender == admin, mt_OnlyAdmin());
        _;
    }

    // ----------- OWNER ------------
    /**
     * @notice Sets a new Operator for the market
     * @dev Admin function to set a new operator
     */
    function setOperator(address _operator) external onlyAdmin {
        _setOperator(_operator);
    }

    /**
     * @notice Sets a new Operator for the market
     * @dev Admin function to set a new operator
     */
    function setRolesOperator(address _roles) external onlyAdmin {
        require(_roles != address(0), mt_InvalidInput());

        emit NewRolesOperator(address(rolesOperator), _roles);

        rolesOperator = IRoles(_roles);
    }

    /**
     * @notice accrues interest and updates the interest rate model using _setInterestRateModelFresh
     * @dev Admin function to accrue interest and update the interest rate model
     * @param newInterestRateModel the new interest rate model to use
     */
    function setInterestRateModel(address newInterestRateModel) external onlyAdmin {
        _accrueInterest();
        // emits interest-rate-model-update-specific logs on errors, so we don't need to.
        return _setInterestRateModel(newInterestRateModel);
    }

    function setBorrowRateMaxMantissa(uint256 maxMantissa) external onlyAdmin {
        uint256 _oldVal = borrowRateMaxMantissa;
        borrowRateMaxMantissa = maxMantissa;

        // validate new mantissa
        if (totalSupply > 0) {
            _accrueInterest();
        }

        emit NewBorrowRateMaxMantissa(_oldVal, maxMantissa);
    }

    /**
     * @notice accrues interest and sets a new reserve factor for the protocol using _setReserveFactorFresh
     * @dev Admin function to accrue interest and set a new reserve factor
     */
    function setReserveFactor(uint256 newReserveFactorMantissa) external onlyAdmin {
        _accrueInterest();

        require(newReserveFactorMantissa <= RESERVE_FACTOR_MAX_MANTISSA, mt_ReserveFactorTooHigh());

        emit NewReserveFactor(reserveFactorMantissa, newReserveFactorMantissa);
        reserveFactorMantissa = newReserveFactorMantissa;
    }

    /**
     * @notice Begins transfer of admin rights. The newPendingAdmin must call `_acceptAdmin` to finalize the transfer.
     * @dev Admin function to begin change of admin. The newPendingAdmin must call `_acceptAdmin` to finalize the transfer.
     * @param newPendingAdmin New pending admin.
     */
    function setPendingAdmin(address payable newPendingAdmin) external onlyAdmin {
        pendingAdmin = newPendingAdmin;
    }

    /**
     * @notice Accepts transfer of admin rights. msg.sender must be pendingAdmin
     * @dev Admin function for pending admin to accept role and update admin
     */
    function acceptAdmin() external {
        // Check caller is pendingAdmin
        require(msg.sender == pendingAdmin, mt_OnlyAdmin());

        // Store admin with value pendingAdmin
        admin = pendingAdmin;

        // Clear the pending value
        pendingAdmin = payable(address(0));
    }

    // ----------- INTERNAL ------------
    /**
     * @notice updates the interest rate model (*requires fresh interest accrual)
     * @dev Admin function to update the interest rate model
     * @param newInterestRateModel the new interest rate model to use
     */
    function _setInterestRateModel(address newInterestRateModel) internal {
        // Ensure invoke newInterestRateModel.isInterestRateModel() returns true
        require(IInterestRateModel(newInterestRateModel).isInterestRateModel(), mt_MarketMethodNotValid());

        emit NewMarketInterestRateModel(interestRateModel, newInterestRateModel);
        interestRateModel = newInterestRateModel;
    }

    function _setOperator(address _operator) internal {
        require(IOperator(_operator).isOperator(), mt_MarketMethodNotValid());

        emit NewOperator(operator, _operator);

        operator = _operator;
    }
}
