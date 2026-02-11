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

interface IMendiMarket {
    function repayBorrow(uint256 repayAmount) external returns (uint256);
    function repayBorrowBehalf(address borrower, uint256 repayAmount) external returns (uint256);
    function redeemUnderlying(uint256 redeemAmount) external returns (uint256);
    function redeem(uint256 amount) external returns (uint256);
    function underlying() external view returns (address);

    function balanceOf(address sender) external view returns (uint256);
    function balanceOfUnderlying(address sender) external returns (uint256);
    function borrowBalanceStored(address sender) external view returns (uint256);
}

interface IMendiComptroller {
    function getAssetsIn(address account) external view returns (IMendiMarket[] memory);
}
