// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.19;

import "./LevelBaseReserveManager.sol";
import "../interfaces/IKarakVault.sol" as IKarakVault;
import "../interfaces/ILevelKarakReserveManager.sol";

/**
 * @title Level Reserve Manager
 * @notice This contract stores and manages reserves from minted lvlUSD
 */
contract KarakReserveManager is LevelBaseReserveManager, IKarakReserveManager {
    using SafeERC20 for IERC20;

    /* --------------- CONSTRUCTOR --------------- */

    constructor(
        IlvlUSD _lvlusd,
        IStakedlvlUSD _stakedlvlUSD,
        address _admin,
        address _allowlister
    ) LevelBaseReserveManager(_lvlusd, _stakedlvlUSD, _admin, _allowlister) {}

    /* --------------- EXTERNAL --------------- */

    function depositToKarak(
        address vault,
        uint256 amount
    ) external onlyRole(MANAGER_AGENT_ROLE) returns (uint256 shares) {
        SafeERC20.forceApprove(
            IERC20(IKarakVault.IVault(vault).asset()),
            vault,
            amount
        );
        shares = IKarakVault.IVault(vault).deposit(amount, address(this));

        emit DepositedToKarak(amount, vault);
    }

    function startRedeemFromKarak(
        address vault,
        uint256 shares
    )
        external
        onlyRole(MANAGER_AGENT_ROLE)
        whenNotPaused
        returns (bytes32 withdrawalKey)
    {
        withdrawalKey = IKarakVault.IVault(vault).startRedeem(
            shares,
            address(this)
        );
        emit RedeemFromKarakStarted(shares, vault, withdrawalKey);
    }

    function finishRedeemFromKarak(
        address vault,
        bytes32 withdrawalKey
    ) external onlyRole(MANAGER_AGENT_ROLE) whenNotPaused {
        IKarakVault.IVault(vault).finishRedeem(withdrawalKey);
        emit RedeemFromKarakFinished(vault, withdrawalKey);
    }
}
