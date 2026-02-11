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

    mapping(address => bool) public allowedMarkets;

    address public constant MENDI_COMPTROLLER = 0x1b4d3b0421dDc1eB216D230Bc01527422Fb93103;
    address public immutable MALDA_OPERATOR;

    struct Position {
        address mendiMarket;
        address maldaMarket;
        uint256 collateralUnderlyingAmount;
        uint256 borrowAmount;
    }

    constructor(address _operator) {
        MALDA_OPERATOR = _operator;
        allowedMarkets[0x269C36A173D881720544Fb303E681370158FF1FD] = true;
        allowedMarkets[0xC7Bc6bD45Eb84D594f51cED3c5497E6812C7732f] = true;
        allowedMarkets[0xDF0635c1eCfdF08146150691a97e2Ff6a8Aa1a90] = true;
        allowedMarkets[0xcb4d153604a6F21Ff7625e5044E89C3b903599Bc] = true;
        allowedMarkets[0x1D8e8cEFEb085f3211Ab6a443Ad9051b54D1cd1a] = true;
        allowedMarkets[0x0B3c6645F4F2442AD4bbee2e2273A250461cA6f8] = true;
        allowedMarkets[0x8BaD0c523516262a439197736fFf982F5E0987cC] = true;
        allowedMarkets[0x4DF3DD62DB219C47F6a7CB1bE02C511AFceAdf5E] = true;
    }

    /**
     * @notice Get all markets where `user` has collateral in on Mendi
     */
    function getAllCollateralMarkets(address user) external view returns (address[] memory markets) {
        IMendiMarket[] memory mendiMarkets = IMendiComptroller(MENDI_COMPTROLLER).getAssetsIn(user);

        uint256 marketsLength = mendiMarkets.length;
        markets = new address[](marketsLength);
        for (uint256 i = 0; i < marketsLength; i++) {
            markets[i] = address(0);
            IMendiMarket mendiMarket = mendiMarkets[i];
            uint256 balanceOfCTokens = mendiMarket.balanceOf(user);
            if (balanceOfCTokens > 0) {
                markets[i] = address(mendiMarket);
            }
        }
    }

    /**
     * @notice Get all `migratable` positions from Mendi to Malda for `user`
     */
    function getAllPositions(address user) external returns (Position[] memory positions) {
        positions = _collectMendiPositions(user);
    }

    /**
     * @notice Migrates all positions from Mendi to Malda
     */
    function migrateAllPositions() external {
        // 1. Collect all positions from Mendi
        Position[] memory positions = _collectMendiPositions(msg.sender);

        uint256 posLength = positions.length;
        require(posLength > 0, "[Migrator] No Mendi positions");

        // 2. Mint mTokens in all v2 markets
        for (uint256 i; i < posLength; ++i) {
            Position memory position = positions[i];
            if (position.collateralUnderlyingAmount > 0) {
                uint256 minCollateral =
                    position.collateralUnderlyingAmount - (position.collateralUnderlyingAmount * 1e4 / 1e5);
                ImErc20Host(position.maldaMarket).mintOrBorrowMigration(
                    true, position.collateralUnderlyingAmount, msg.sender, address(0), minCollateral
                );
            }
        }

        // 3. Borrow from all necessary v2 markets
        for (uint256 i; i < posLength; ++i) {
            Position memory position = positions[i];
            if (position.borrowAmount > 0) {
                ImErc20Host(position.maldaMarket).mintOrBorrowMigration(
                    false, position.borrowAmount, address(this), msg.sender, 0
                );
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
    function _collectMendiPositions(address user) private returns (Position[] memory) {
        IMendiMarket[] memory mendiMarkets = IMendiComptroller(MENDI_COMPTROLLER).getAssetsIn(user);
        uint256 marketsLength = mendiMarkets.length;

        Position[] memory positions = new Position[](marketsLength);
        uint256 positionCount;

        for (uint256 i = 0; i < marketsLength; i++) {
            IMendiMarket mendiMarket = mendiMarkets[i];
            uint256 collateralUnderlyingAmount = mendiMarket.balanceOfUnderlying(user);
            uint256 borrowAmount = mendiMarket.borrowBalanceStored(user);

            if (collateralUnderlyingAmount > 0 || borrowAmount > 0) {
                address maldaMarket = _getMaldaMarket(IMendiMarket(address(mendiMarket)).underlying());
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
    function _getMaldaMarket(address underlying) private view returns (address) {
        address[] memory maldaMarkets = Operator(MALDA_OPERATOR).getAllMarkets();

        for (uint256 i = 0; i < maldaMarkets.length; i++) {
            address _market = maldaMarkets[i];
            if (ImToken(_market).underlying() == underlying) {
                if (allowedMarkets[_market]) {
                    return maldaMarkets[i];
                }
            }
        }

        return address(0);
    }
}
