// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {AssetManagerBase} from "./AssetManagerBase.sol";
import {AgentCollateral} from "../library/AgentCollateral.sol";
import {Agents} from "../library/Agents.sol";
import {Conversion} from "../library/Conversion.sol";
import {Liquidation} from "../library/Liquidation.sol";
import {LiquidationPaymentStrategy} from "../library/LiquidationPaymentStrategy.sol";
import {UnderlyingBalance} from "../library/UnderlyingBalance.sol";
import {Agent} from "../library/data/Agent.sol";
import {AssetManagerState} from "../library/data/AssetManagerState.sol";
import {Collateral} from "../library/data/Collateral.sol";
import {CollateralTypeInt} from "../library/data/CollateralTypeInt.sol";
import {IICollateralPool} from "../../collateralPool/interfaces/IICollateralPool.sol";
import {AgentInfo} from "../../userInterfaces/data/AgentInfo.sol";


contract AgentInfoFacet is AssetManagerBase {
    using SafeCast for uint256;
    using AgentCollateral for Collateral.CombinedData;
    using AgentCollateral for Collateral.Data;
    using Agents for Agent.State;

    /**
     * Get (a part of) the list of all agents.
     * The list must be retrieved in parts since retrieving the whole list can consume too much gas for one block.
     * @param _start first index to return from the available agent's list
     * @param _end end index (one above last) to return from the available agent's list
     */
    function getAllAgents(
        uint256 _start,
        uint256 _end
    )
        external view
        returns (address[] memory _agents, uint256 _totalLength)
    {
        return Agents.getAllAgents(_start, _end);
    }

    /**
     * Check if the collateral pool token has been used already by some vault.
     * @param _suffix the suffix to check
     */
    function isPoolTokenSuffixReserved(string memory _suffix)
        external view
        returns (bool)
    {
        AssetManagerState.State storage state = AssetManagerState.get();
        return state.reservedPoolTokenSuffixes[_suffix];
    }

    /**
     * Return basic info about an agent, typically needed by a minter.
     * @param _agentVault agent vault address
     * @return _info structure containing agent's minting fee (BIPS), min collateral ratio (BIPS),
     *      and current free collateral (lots)
     */
    function getAgentInfo(
        address _agentVault
    )
        external view
        returns (AgentInfo.Info memory _info)
    {
        Agent.State storage agent = Agent.getAllowDestroyed(_agentVault);
        Collateral.CombinedData memory collateralData = AgentCollateral.combinedData(agent);
        CollateralTypeInt.Data storage collateral = agent.getVaultCollateral();
        CollateralTypeInt.Data storage poolCollateral = agent.getPoolCollateral();
        IICollateralPool collateralPool = agent.collateralPool;
        Liquidation.CRData memory cr = Liquidation.getCollateralRatiosBIPS(agent);
        _info.status = Agents.getAgentStatus(agent);
        _info.ownerManagementAddress = agent.ownerManagementAddress;
        _info.ownerWorkAddress = Agents.getWorkAddress(agent);
        _info.collateralPool = address(collateralPool);
        _info.collateralPoolToken = address(collateralPool.poolToken());
        _info.underlyingAddressString = agent.underlyingAddressString;
        _info.publiclyAvailable = agent.availableAgentsPos != 0;
        _info.vaultCollateralToken = collateral.token;
        _info.feeBIPS = agent.feeBIPS;
        _info.poolFeeShareBIPS = agent.poolFeeShareBIPS;
        _info.mintingVaultCollateralRatioBIPS =
            Math.max(agent.mintingVaultCollateralRatioBIPS, collateral.minCollateralRatioBIPS);
        _info.mintingPoolCollateralRatioBIPS =
            Math.max(agent.mintingPoolCollateralRatioBIPS, poolCollateral.minCollateralRatioBIPS);
        _info.freeCollateralLots = collateralData.freeCollateralLots(agent);
        _info.totalVaultCollateralWei = collateralData.agentCollateral.fullCollateral;
        _info.freeVaultCollateralWei = collateralData.agentCollateral.freeCollateralWei(agent);
        _info.vaultCollateralRatioBIPS = cr.vaultCR;
        _info.poolWNatToken = poolCollateral.token;
        _info.totalPoolCollateralNATWei = collateralData.poolCollateral.fullCollateral;
        _info.freePoolCollateralNATWei = collateralData.poolCollateral.freeCollateralWei(agent);
        _info.poolCollateralRatioBIPS = cr.poolCR;
        _info.totalAgentPoolTokensWei = collateralData.agentPoolTokens.fullCollateral;
        _info.freeAgentPoolTokensWei = collateralData.agentPoolTokens.freeCollateralWei(agent);
        _info.announcedVaultCollateralWithdrawalWei =
            agent.withdrawalAnnouncement(Collateral.Kind.VAULT).amountWei;
        _info.announcedPoolTokensWithdrawalWei =
            agent.withdrawalAnnouncement(Collateral.Kind.AGENT_POOL).amountWei;
        _info.mintedUBA = Conversion.convertAmgToUBA(agent.mintedAMG);
        _info.reservedUBA = Conversion.convertAmgToUBA(agent.reservedAMG);
        _info.redeemingUBA = Conversion.convertAmgToUBA(agent.redeemingAMG);
        _info.poolRedeemingUBA = Conversion.convertAmgToUBA(agent.poolRedeemingAMG);
        _info.dustUBA = Conversion.convertAmgToUBA(agent.dustAMG);
        _info.liquidationStartTimestamp = agent.liquidationStartedAt;
        (_info.liquidationPaymentFactorVaultBIPS, _info.liquidationPaymentFactorPoolBIPS,
            _info.maxLiquidationAmountUBA) = _getLiquidationFactorsAndMaxAmount(agent, cr);
        _info.underlyingBalanceUBA = agent.underlyingBalanceUBA;
        _info.requiredUnderlyingBalanceUBA = UnderlyingBalance.requiredUnderlyingUBA(agent);
        _info.freeUnderlyingBalanceUBA =
            _info.underlyingBalanceUBA - _info.requiredUnderlyingBalanceUBA.toInt256();
        _info.announcedUnderlyingWithdrawalId = agent.announcedUnderlyingWithdrawalId;
        _info.buyFAssetByAgentFactorBIPS = agent.buyFAssetByAgentFactorBIPS;
        _info.poolExitCollateralRatioBIPS = agent.collateralPool.exitCollateralRatioBIPS();
        _info.redemptionPoolFeeShareBIPS = agent.redemptionPoolFeeShareBIPS;
    }

    function getCollateralPool(address _agentVault)
        external view
        returns (address)
    {
        return address(Agent.getAllowDestroyed(_agentVault).collateralPool);
    }

    function getAgentVaultOwner(address _agentVault)
        external view
        returns (address _ownerManagementAddress)
    {
        return Agent.getAllowDestroyed(_agentVault).ownerManagementAddress;
    }

    function getAgentVaultCollateralToken(address _agentVault)
        external view
        returns (IERC20)
    {
        return Agent.get(_agentVault).getVaultCollateral().token;
    }

    function getAgentFullVaultCollateral(address _agentVault)
        external view
        returns (uint256)
    {
        return _getFullCollateral(_agentVault, Collateral.Kind.VAULT);
    }

    function getAgentFullPoolCollateral(address _agentVault)
        external view
        returns (uint256)
    {
        return _getFullCollateral(_agentVault, Collateral.Kind.POOL);
    }

    function getAgentLiquidationFactorsAndMaxAmount(address _agentVault)
        external view
        returns (
            uint256 _liquidationPaymentFactorVaultBIPS,
            uint256 _liquidationPaymentFactorPoolBIPS,
            uint256 _maxLiquidationAmountUBA
        )
    {
        Agent.State storage agent = Agent.get(_agentVault);
        Liquidation.CRData memory cr = Liquidation.getCollateralRatiosBIPS(agent);
        return _getLiquidationFactorsAndMaxAmount(agent, cr);
    }

    function getAgentMinPoolCollateralRatioBIPS(address _agentVault)
        external view
        returns (uint256)
    {
        return _getMinCollateralRatioBIPS(_agentVault, Collateral.Kind.POOL);
    }

    function getAgentMinVaultCollateralRatioBIPS(address _agentVault)
        external view
        returns (uint256)
    {
        return _getMinCollateralRatioBIPS(_agentVault, Collateral.Kind.VAULT);
    }

    function _getFullCollateral(address _agentVault, Collateral.Kind _kind)
        private view
        returns (uint256)
    {
        Agent.State storage agent = Agent.get(_agentVault);
        Collateral.Data memory collateral = AgentCollateral.singleCollateralData(agent, _kind);
        return collateral.fullCollateral;
    }

    function _getMinCollateralRatioBIPS(address _agentVault, Collateral.Kind _kind)
        private view
        returns (uint256)
    {
        Agent.State storage agent = Agent.get(_agentVault);
        (, uint256 sysMinCR) = AgentCollateral.mintingMinCollateralRatio(agent, _kind);
        return sysMinCR;
    }

    function _getLiquidationFactorsAndMaxAmount(
        Agent.State storage _agent,
        Liquidation.CRData memory _cr
    )
        private view
        returns (uint256 _vaultFactorBIPS, uint256 _poolFactorBIPS, uint256 _maxLiquidatedUBA)
    {
        Agent.Status agentStatus = _agent.status;
        if (agentStatus != Agent.Status.LIQUIDATION && agentStatus != Agent.Status.FULL_LIQUIDATION) {
            return (0, 0, 0);
        }
        // split liquidation payment between agent vault and pool
        (_vaultFactorBIPS, _poolFactorBIPS) =
            LiquidationPaymentStrategy.currentLiquidationFactorBIPS(_agent, _cr.vaultCR, _cr.poolCR);
        // calculate liquidation amount
        uint256 maxLiquidatedAMG = Math.max(
            Liquidation.maxLiquidationAmountAMG(_agent, _cr.vaultCR, _vaultFactorBIPS, Collateral.Kind.VAULT),
            Liquidation.maxLiquidationAmountAMG(_agent, _cr.poolCR, _poolFactorBIPS, Collateral.Kind.POOL));
        _maxLiquidatedUBA = Conversion.convertAmgToUBA(maxLiquidatedAMG.toUint64());
    }
}
