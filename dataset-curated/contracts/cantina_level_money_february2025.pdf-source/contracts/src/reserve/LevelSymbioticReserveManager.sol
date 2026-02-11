// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.19;

import "./LevelBaseReserveManager.sol";
import "../interfaces/ISymbioticVault.sol" as ISymbioticVault;
import "../interfaces/ILevelSymbioticReserveManager.sol";

/**
 * @title Symbiotic Reserve Manager
 * @notice This contract stores and manages reserves to be deployed to Symbiotic.
 */
contract SymbioticReserveManager is
    LevelBaseReserveManager,
    ISymbioticReserveManager
{
    using SafeERC20 for IERC20;

    /* --------------- CONSTRUCTOR --------------- */

    constructor(
        IlvlUSD _lvlusd,
        IStakedlvlUSD _stakedlvlUSD,
        address _admin,
        address _allowlister
    ) LevelBaseReserveManager(_lvlusd, _stakedlvlUSD, _admin, _allowlister) {}

    /* --------------- EXTERNAL --------------- */

    function depositToSymbiotic(
        address vault,
        uint256 amount
    )
        external
        onlyRole(MANAGER_AGENT_ROLE)
        whenNotPaused
        returns (uint256 depositedAmount, uint256 mintedShares)
    {
        address collateral = ISymbioticVault.IVault(vault).collateral();
        IERC20(collateral).forceApprove(vault, amount);
        (depositedAmount, mintedShares) = ISymbioticVault.IVault(vault).deposit(
            address(this),
            amount
        );
        emit DepositedToSymbiotic(amount, vault);
    }

    function withdrawFromSymbiotic(
        address vault,
        uint256 amount
    )
        external
        onlyRole(MANAGER_AGENT_ROLE)
        whenNotPaused
        returns (uint256 burnedShares, uint256 mintedShares)
    {
        (burnedShares, mintedShares) = ISymbioticVault.IVault(vault).withdraw(
            address(this),
            amount
        );
        emit WithdrawnFromSymbiotic(amount, vault);
    }

    function claimFromSymbiotic(
        address vault,
        uint256 epoch
    )
        external
        onlyRole(MANAGER_AGENT_ROLE)
        whenNotPaused
        returns (uint256 amount)
    {
        amount = ISymbioticVault.IVault(vault).claim(address(this), epoch);
        emit ClaimedFromSymbiotic(epoch, amount, vault);
    }
}
