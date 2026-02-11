// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "./ILevelMinting.sol";

interface ISymbioticReserveManager {
    event DepositedToSymbiotic(uint256 amount, address symbioticVault);
    event WithdrawnFromSymbiotic(uint256 amount, address symbioticVault);
    event ClaimedFromSymbiotic(
        uint256 epoch,
        uint256 amount,
        address symbioticVault
    );

    function depositToSymbiotic(
        address vault,
        uint256 amount
    ) external returns (uint256 depositedAmount, uint256 mintedShares);

    function withdrawFromSymbiotic(
        address vault,
        uint256 amount
    ) external returns (uint256 burnedShares, uint256 mintedShares);

    function claimFromSymbiotic(
        address vault,
        uint256 epoch
    ) external returns (uint256 amount);
}
