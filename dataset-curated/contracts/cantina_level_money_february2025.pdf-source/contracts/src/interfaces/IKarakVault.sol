// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.25;

import {IKarakBaseVault} from "./IKarakBaseVault.sol";

interface IVault is IKarakBaseVault {
    /* ========== MUTATIVE FUNCTIONS ========== */
    function deposit(
        uint256 assets,
        address to
    ) external returns (uint256 shares);

    function deposit(
        uint256 assets,
        address to,
        uint256 minSharesOut
    ) external returns (uint256 shares);

    function mint(uint256 shares, address to) external returns (uint256 assets);

    function startRedeem(
        uint256 shares,
        address withdrawer
    ) external returns (bytes32 withdrawalKey);

    function finishRedeem(bytes32 withdrawalKey) external;

    /* ======================================== */

    /* ============ VIEW FUNCTIONS ============ */
    function owner() external view returns (address);

    function getNextWithdrawNonce(
        address staker
    ) external view returns (uint256);

    function isWithdrawalPending(
        address staker,
        uint256 _withdrawNonce
    ) external view returns (bool);

    function extSloads(
        bytes32[] calldata slots
    ) external view returns (bytes32[] memory res);
    /* ======================================== */
}
