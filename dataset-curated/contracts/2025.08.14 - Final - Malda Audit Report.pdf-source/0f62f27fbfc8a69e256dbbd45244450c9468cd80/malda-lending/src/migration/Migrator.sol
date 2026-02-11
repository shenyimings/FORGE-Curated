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

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {Operator} from "src/Operator/Operator.sol";

import {ImToken} from "src/interfaces/ImToken.sol";
import {ImErc20Host} from "src/interfaces/ImErc20Host.sol";
import "./IMigrator.sol";

contract Migrator {
    using SafeERC20 for IERC20;

    struct MigrationParams {
        address mendiComptroller;
        address maldaOperator;
        // @dev ignored for `migrateAllPositions`
        address userV1;
        address userV2;
    }

    struct Position {
        address mendiMarket;
        address maldaMarket;
        uint256 collateralUnderlyingAmount;
        uint256 borrowAmount;
    }

    /**
     * @notice Get all markets where `params.userV1` has collateral in on Mendi
     * @param params Migration parameters containing protocol addresses
     */
    function getAllCollateralMarkets(MigrationParams calldata params)
        external
        view
        returns (address[] memory markets)
    {
        IMendiMarket[] memory mendiMarkets = IMendiComptroller(params.mendiComptroller).getAssetsIn(params.userV1);

        uint256 marketsLength = mendiMarkets.length;
        markets = new address[](marketsLength);
        for (uint256 i = 0; i < marketsLength; i++) {
            markets[i] = address(0);
            IMendiMarket mendiMarket = mendiMarkets[i];
            uint256 balanceOfCTokens = mendiMarket.balanceOf(params.userV1);
            if (balanceOfCTokens > 0) {
                markets[i] = address(mendiMarket);
            }
        }
    }

    /**
     * @notice Get all `migratable` positions from Mendi to Malda
     * @param params Migration parameters containing protocol addresses
     */
    function getAllPositions(MigrationParams calldata params) external returns (Position[] memory positions) {
        positions = _collectMendiPositions(params);
    }

    /**
     * @notice Migrates all positions from Mendi to Malda
     * @param params Migration parameters containing protocol addresses
     */
    function migrateAllPositions(MigrationParams calldata params) external {
        // 1. Collect all positions from Mendi
        Position[] memory positions = _collectMendiPositions(params);

        uint256 posLength = positions.length;
        require(posLength > 0, "[Migrator] No Mendi positions");

        // 2. Mint mTokens in all v2 markets
        for (uint256 i; i < posLength; ++i) {
            Position memory position = positions[i];
            if (position.collateralUnderlyingAmount > 0) {
                uint256 minCollateral =
                    position.collateralUnderlyingAmount - (position.collateralUnderlyingAmount * 1e4 / 1e5);
                ImErc20Host(position.maldaMarket).mintMigration(
                    position.collateralUnderlyingAmount, minCollateral, params.userV2
                );
            }
        }

        // 3. Borrow from all necessary v2 markets
        for (uint256 i; i < posLength; ++i) {
            Position memory position = positions[i];
            if (position.borrowAmount > 0) {
                ImErc20Host(position.maldaMarket).borrowMigration(position.borrowAmount, params.userV2, address(this));
            }
        }

        // 4. Repay all debts in v1 markets
        for (uint256 i; i < posLength; ++i) {
            Position memory position = positions[i];
            if (position.borrowAmount > 0) {
                IERC20 underlying = IERC20(IMendiMarket(position.mendiMarket).underlying());
                underlying.approve(position.mendiMarket, position.borrowAmount);
                require(
                    IMendiMarket(position.mendiMarket).repayBorrowBehalf(msg.sender, position.borrowAmount) == 0,
                    "[Migrator] Mendi repay failed"
                );
            }
        }

        // 5. Withdraw and transfer all collateral from v1 to v2
        for (uint256 i; i < posLength; ++i) {
            Position memory position = positions[i];
            if (position.collateralUnderlyingAmount > 0) {
                uint256 v1CTokenBalance = IMendiMarket(position.mendiMarket).balanceOf(msg.sender);
                IERC20(position.mendiMarket).safeTransferFrom(msg.sender, address(this), v1CTokenBalance);

                IERC20 underlying = IERC20(IMendiMarket(position.mendiMarket).underlying());

                uint256 underlyingBalanceBefore = underlying.balanceOf(address(this));

                // Withdraw from v1
                // we use address(this) here as cTokens were transferred above
                uint256 v1Balance = IMendiMarket(position.mendiMarket).balanceOfUnderlying(address(this));
                require(
                    IMendiMarket(position.mendiMarket).redeemUnderlying(v1Balance) == 0,
                    "[Migrator] Mendi withdraw failed"
                );

                uint256 underlyingBalanceAfter = underlying.balanceOf(address(this));
                require(
                    underlyingBalanceAfter - underlyingBalanceBefore >= v1Balance, "[Migrator] Redeem amount not valid"
                );

                // Transfer to v2
                underlying.safeTransfer(position.maldaMarket, position.collateralUnderlyingAmount);
            }
        }
    }

    /**
     * @notice Collects all user positions from Mendi
     */
    function _collectMendiPositions(MigrationParams memory params) private returns (Position[] memory) {
        IMendiMarket[] memory mendiMarkets = IMendiComptroller(params.mendiComptroller).getAssetsIn(msg.sender);
        uint256 marketsLength = mendiMarkets.length;

        Position[] memory positions = new Position[](marketsLength);
        uint256 positionCount;

        for (uint256 i = 0; i < marketsLength; i++) {
            IMendiMarket mendiMarket = mendiMarkets[i];
            uint256 collateralUnderlyingAmount = mendiMarket.balanceOfUnderlying(msg.sender);
            uint256 borrowAmount = mendiMarket.borrowBalanceStored(msg.sender);

            if (collateralUnderlyingAmount > 0 || borrowAmount > 0) {
                address maldaMarket =
                    _getMaldaMarket(params.maldaOperator, IMendiMarket(address(mendiMarket)).underlying());
                if (maldaMarket != address(0)) {
                    positions[positionCount++] = Position({
                        mendiMarket: address(mendiMarket),
                        maldaMarket: maldaMarket,
                        collateralUnderlyingAmount: collateralUnderlyingAmount,
                        borrowAmount: borrowAmount
                    });
                }
            }
        }

        // Resize array to actual position count
        assembly {
            mstore(positions, positionCount)
        }
        return positions;
    }

    /**
     * @notice Gets corresponding Malda market for a given underlying
     */
    function _getMaldaMarket(address maldaOperator, address underlying) private view returns (address) {
        address[] memory maldaMarkets = Operator(maldaOperator).getAllMarkets();

        for (uint256 i = 0; i < maldaMarkets.length; i++) {
            if (ImToken(maldaMarkets[i]).underlying() == underlying) {
                return maldaMarkets[i];
            }
        }

        return address(0);
    }
}
