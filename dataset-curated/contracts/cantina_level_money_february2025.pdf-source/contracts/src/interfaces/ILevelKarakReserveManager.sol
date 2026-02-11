// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "./ILevelMinting.sol";

interface IKarakReserveManager {
    event DepositedToKarak(uint256 amount, address karakVault);
    event RedeemFromKarakStarted(
        uint256 shares,
        address karakVault,
        bytes32 withdrawalKey
    );
    event RedeemFromKarakFinished(address karakVault, bytes32 withdrawalKey);

    function depositToKarak(
        address vault,
        uint256 amount
    ) external returns (uint256 shares);

    function startRedeemFromKarak(
        address vault,
        uint256 shares
    ) external returns (bytes32 withdrawalKey);

    function finishRedeemFromKarak(
        address vault,
        bytes32 withdrawalKey
    ) external;
}
