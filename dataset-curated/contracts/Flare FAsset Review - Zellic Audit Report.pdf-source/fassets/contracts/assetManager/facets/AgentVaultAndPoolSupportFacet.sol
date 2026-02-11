// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AssetManagerBase} from "./AssetManagerBase.sol";
import {Agents} from "../library/Agents.sol";
import {Conversion} from "../library/Conversion.sol";
import {Globals} from "../library/Globals.sol";
import {Agent} from "../library/data/Agent.sol";
import {IWNat} from "../../flareSmartContracts/interfaces/IWNat.sol";
import {AssetManagerSettings} from "../../userInterfaces/data/AssetManagerSettings.sol";
import {CollateralType} from "../../userInterfaces/data/CollateralType.sol";
import {CollateralTypes} from "../library/CollateralTypes.sol";


contract AgentVaultAndPoolSupportFacet is AssetManagerBase {
    using Agents for Agent.State;

    /**
     * Returns price of asset (UBA) in NAT Wei as a fraction.
     */
    function assetPriceNatWei()
        external view
        returns (uint256 _multiplier, uint256 _divisor)
    {
        AssetManagerSettings.Data storage settings = Globals.getSettings();
        _multiplier = Conversion.currentAmgPriceInTokenWei(Globals.getPoolCollateral());
        _divisor = Conversion.AMG_TOKEN_WEI_PRICE_SCALE * settings.assetMintingGranularityUBA;
    }

    /**
     * Check if `_token` is either vault collateral token for `_agentVault` or the pool token.
     * These types of tokens cannot be simply transferred from the agent vault, but can only be
     * withdrawn after announcement if they are not backing any f-assets.
     */
    function isLockedVaultToken(address _agentVault, IERC20 _token)
        external view
        returns (bool)
    {
        Agent.State storage agent = Agent.get(_agentVault);
        return _token == agent.getVaultCollateralToken() || _token == agent.collateralPool.poolToken();
    }

    /**
     * Check if `_token` is any of the vault collateral tokens (including already invalidated).
     */
    function isVaultCollateralToken(IERC20 _token)
        external view
        returns (bool)
    {
        return CollateralTypes.exists(CollateralType.Class.VAULT, _token);
    }

    function getFAssetsBackedByPool(address _agentVault)
        external view
        returns (uint256)
    {
        Agent.State storage agent = Agent.get(_agentVault);
        return Conversion.convertAmgToUBA(agent.reservedAMG + agent.mintedAMG + agent.poolRedeemingAMG);
    }

    function isAgentVaultOwner(address _agentVault, address _address)
        external view
        returns (bool)
    {
        Agent.State storage agent = Agent.getAllowDestroyed(_agentVault);
        return Agents.isOwner(agent, _address);
    }

    function getWorkAddress(address _managementAddress)
        external view
        returns (address)
    {
        return Globals.getAgentOwnerRegistry().getWorkAddress(_managementAddress);
    }

    /**
     * Get WNat contract. Used by AgentVault.
     * @return WNat contract
     */
    function getWNat()
        external view
        returns (IWNat)
    {
        return Globals.getWNat();
    }
}
