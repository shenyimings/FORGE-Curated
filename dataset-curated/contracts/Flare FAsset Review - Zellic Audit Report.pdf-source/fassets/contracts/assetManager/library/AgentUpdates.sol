// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafePct} from "../../utils/library/SafePct.sol";
import {Agent} from "./data/Agent.sol";
import {Collateral} from "./data/Collateral.sol";
import {AssetManagerState} from "./data/AssetManagerState.sol";
import {CollateralTypeInt} from "./data/CollateralTypeInt.sol";
import {Agents} from "./Agents.sol";
import {CollateralTypes} from "./CollateralTypes.sol";
import {AgentCollateral} from "./AgentCollateral.sol";
import {CollateralType} from "../../userInterfaces/data/CollateralType.sol";

library AgentUpdates {
    using SafeCast for uint256;

    error CollateralRatioTooSmall();
    error CollateralDeprecated();
    error NotEnoughCollateral();
    error FeeTooHigh();
    error ValueTooHigh();
    error ValueTooLow();
    error IncreaseTooBig();

    function setVaultCollateral(
        Agent.State storage _agent,
        IERC20 _token
    )
        internal
    {
        AssetManagerState.State storage state = AssetManagerState.get();
        uint256 tokenIndex = CollateralTypes.getIndex(CollateralType.Class.VAULT, _token);
        CollateralTypeInt.Data storage collateral = state.collateralTokens[tokenIndex];
        assert(collateral.collateralClass == CollateralType.Class.VAULT);
        // agent should never use a deprecated or already invalid collateral
        require(collateral.__validUntil == 0, CollateralDeprecated());
        // set the new index
        _agent.vaultCollateralIndex = tokenIndex.toUint16();
        // check there is enough collateral for current mintings
        Collateral.Data memory switchCollateralData = AgentCollateral.agentVaultCollateralData(_agent);
        uint256 crBIPS = AgentCollateral.collateralRatioBIPS(switchCollateralData, _agent);
        require(crBIPS >= collateral.minCollateralRatioBIPS, NotEnoughCollateral());
    }

    function setMintingVaultCollateralRatioBIPS(
        Agent.State storage _agent,
        uint256 _mintingVaultCollateralRatioBIPS
    )
        internal
    {
        CollateralTypeInt.Data storage collateral = Agents.getVaultCollateral(_agent);
        require(_mintingVaultCollateralRatioBIPS >= collateral.minCollateralRatioBIPS,
            CollateralRatioTooSmall());
        _agent.mintingVaultCollateralRatioBIPS = _mintingVaultCollateralRatioBIPS.toUint32();
    }

    function setMintingPoolCollateralRatioBIPS(
        Agent.State storage _agent,
        uint256 _mintingPoolCollateralRatioBIPS
    )
        internal
    {
        CollateralTypeInt.Data storage collateral = Agents.getPoolCollateral(_agent);
        require(_mintingPoolCollateralRatioBIPS >= collateral.minCollateralRatioBIPS,
            CollateralRatioTooSmall());
        _agent.mintingPoolCollateralRatioBIPS = _mintingPoolCollateralRatioBIPS.toUint32();
    }

    function setFeeBIPS(
        Agent.State storage _agent,
        uint256 _feeBIPS
    )
        internal
    {
        require(_feeBIPS <= SafePct.MAX_BIPS, FeeTooHigh());
        _agent.feeBIPS = _feeBIPS.toUint16();
    }

    function setPoolFeeShareBIPS(
        Agent.State storage _agent,
        uint256 _poolFeeShareBIPS
    )
        internal
    {
        require(_poolFeeShareBIPS <= SafePct.MAX_BIPS, ValueTooHigh());
        _agent.poolFeeShareBIPS = _poolFeeShareBIPS.toUint16();
    }

    function setRedemptionPoolFeeShareBIPS(
        Agent.State storage _agent,
        uint256 _redemptionPoolFeeShareBIPS
    )
        internal
    {
        require(_redemptionPoolFeeShareBIPS <= SafePct.MAX_BIPS, ValueTooHigh());
        _agent.redemptionPoolFeeShareBIPS = _redemptionPoolFeeShareBIPS.toUint16();
    }

    function setBuyFAssetByAgentFactorBIPS(
        Agent.State storage _agent,
        uint256 _buyFAssetByAgentFactorBIPS
    )
        internal
    {
        // This factor's function is to compensate agent in case of price fluctuations, so allowing it
        // above 100% doesn't make sense - it is only good for exploits.
        require(_buyFAssetByAgentFactorBIPS <= SafePct.MAX_BIPS, ValueTooHigh());
        // We also don't want to allow it to be too low as this allows agents to underpay
        // the exiting collateral providers.
        require(_buyFAssetByAgentFactorBIPS >= 9000, ValueTooLow());
        _agent.buyFAssetByAgentFactorBIPS = _buyFAssetByAgentFactorBIPS.toUint16();
    }

    function setPoolExitCollateralRatioBIPS(
        Agent.State storage _agent,
        uint256 _poolExitCollateralRatioBIPS
    )
        internal
    {
        CollateralTypeInt.Data storage collateral = Agents.getPoolCollateral(_agent);
        uint256 minCR = collateral.minCollateralRatioBIPS;
        require(_poolExitCollateralRatioBIPS >= minCR, ValueTooLow());
        uint256 currentExitCR = _agent.collateralPool.exitCollateralRatioBIPS();
        // if minCollateralRatioBIPS is increased too quickly, it may be impossible for pool exit CR
        // to be increased fast enough, so it can always be changed up to 1.2 * minCR
        require(_poolExitCollateralRatioBIPS <= currentExitCR * 3 / 2 ||
                _poolExitCollateralRatioBIPS <= minCR * 12 / 10,
                IncreaseTooBig());
        // never allow exitCR to grow too big, even in several steps
        require(_poolExitCollateralRatioBIPS <= minCR * 3, ValueTooHigh());
        _agent.collateralPool.setExitCollateralRatioBIPS(_poolExitCollateralRatioBIPS);
    }
}
