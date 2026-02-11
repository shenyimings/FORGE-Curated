// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {AssetManagerBase} from "./AssetManagerBase.sol";
import {AgentUpdates} from "../library/AgentUpdates.sol";
import {Agent} from "../library/data/Agent.sol";
import {Globals} from "../library/Globals.sol";
import {IAssetManagerEvents} from "../../userInterfaces/IAssetManagerEvents.sol";
import {AssetManagerSettings} from "../../userInterfaces/data/AssetManagerSettings.sol";


contract AgentSettingsFacet is AssetManagerBase {
    using SafeCast for uint256;

    bytes32 internal constant FEE_BIPS = keccak256("feeBIPS");
    bytes32 internal constant POOL_FEE_SHARE_BIPS = keccak256("poolFeeShareBIPS");
    bytes32 internal constant REDEMPTION_POOL_FEE_SHARE_BIPS = keccak256("redemptionPoolFeeShareBIPS");
    bytes32 internal constant MINTING_VAULT_COLLATERAL_RATIO_BIPS = keccak256("mintingVaultCollateralRatioBIPS");
    bytes32 internal constant MINTING_POOL_COLLATERAL_RATIO_BIPS = keccak256("mintingPoolCollateralRatioBIPS");
    bytes32 internal constant BUY_FASSET_BY_AGENT_FACTOR_BIPS = keccak256("buyFAssetByAgentFactorBIPS");
    bytes32 internal constant POOL_EXIT_COLLATERAL_RATIO_BIPS = keccak256("poolExitCollateralRatioBIPS");

    error NoPendingUpdate();
    error UpdateNotValidYet();
    error UpdateNotValidAnymore();
    error InvalidSettingName();

    /**
     * Due to effect on the pool, all agent settings are timelocked.
     * This method announces a setting change. The change can be executed after the timelock expires.
     * NOTE: may only be called by the agent vault owner.
     * @return _updateAllowedAt the timestamp at which the update can be executed
     */
    function announceAgentSettingUpdate(
        address _agentVault,
        string memory _name,
        uint256 _value
    )
        external
        onlyAgentVaultOwner(_agentVault)
        returns (uint256 _updateAllowedAt)
    {
        Agent.State storage agent = Agent.get(_agentVault);
        bytes32 hash = _getAndCheckHash(_name);
        _updateAllowedAt = block.timestamp + _getTimelock(hash);
        agent.settingUpdates[hash] = Agent.SettingUpdate({
            value: _value.toUint128(),
            validAt: _updateAllowedAt.toUint64()
        });
        emit IAssetManagerEvents.AgentSettingChangeAnnounced(_agentVault, _name, _value, _updateAllowedAt);
    }

    /**
     * Due to effect on the pool, all agent settings are timelocked.
     * This method executes a setting change after the timelock expired.
     * NOTE: may only be called by the agent vault owner.
     */
    function executeAgentSettingUpdate(
        address _agentVault,
        string memory _name
    )
        external
        onlyAgentVaultOwner(_agentVault)
    {
        Agent.State storage agent = Agent.get(_agentVault);
        bytes32 hash = _getAndCheckHash(_name);
        Agent.SettingUpdate storage update = agent.settingUpdates[hash];
        require(update.validAt != 0, NoPendingUpdate());
        require(update.validAt <= block.timestamp, UpdateNotValidYet());
        AssetManagerSettings.Data storage settings = Globals.getSettings();
        require(update.validAt + settings.agentTimelockedOperationWindowSeconds >= block.timestamp,
            UpdateNotValidAnymore());
        _executeUpdate(agent, hash, update.value);
        emit IAssetManagerEvents.AgentSettingChanged(_agentVault, _name, update.value);
        delete agent.settingUpdates[hash];
    }

    /**
     * Get agent's setting by name. Setting names are the same as for the updates.
     * This allows reading individual settings.
     * @return _value the setting value
     */
    function getAgentSetting(
        address _agentVault,
        string memory _name
    )
        external view
        returns (uint256 _value)
    {
        Agent.State storage agent = Agent.get(_agentVault);
        bytes32 hash = _getAndCheckHash(_name);
        if (hash == FEE_BIPS) {
            return agent.feeBIPS;
        } else if (hash == POOL_FEE_SHARE_BIPS) {
            return agent.poolFeeShareBIPS;
        } else if (hash == REDEMPTION_POOL_FEE_SHARE_BIPS) {
            return agent.redemptionPoolFeeShareBIPS;
        } else if (hash == MINTING_VAULT_COLLATERAL_RATIO_BIPS) {
            return agent.mintingVaultCollateralRatioBIPS;
        } else if (hash == MINTING_POOL_COLLATERAL_RATIO_BIPS) {
            return agent.mintingPoolCollateralRatioBIPS;
        } else if (hash == BUY_FASSET_BY_AGENT_FACTOR_BIPS) {
            return agent.buyFAssetByAgentFactorBIPS;
        } else if (hash == POOL_EXIT_COLLATERAL_RATIO_BIPS) {
            return agent.collateralPool.exitCollateralRatioBIPS();
        } else {
            assert(false);
        }
    }

    function _executeUpdate(
        Agent.State storage _agent,
        bytes32 _hash,
        uint256 _value
    )
        private
    {
        if (_hash == FEE_BIPS) {
            AgentUpdates.setFeeBIPS(_agent, _value);
        } else if (_hash == POOL_FEE_SHARE_BIPS) {
            AgentUpdates.setPoolFeeShareBIPS(_agent, _value);
        } else if (_hash == REDEMPTION_POOL_FEE_SHARE_BIPS) {
            AgentUpdates.setRedemptionPoolFeeShareBIPS(_agent, _value);
        } else if (_hash == MINTING_VAULT_COLLATERAL_RATIO_BIPS) {
            AgentUpdates.setMintingVaultCollateralRatioBIPS(_agent, _value);
        } else if (_hash == MINTING_POOL_COLLATERAL_RATIO_BIPS) {
            AgentUpdates.setMintingPoolCollateralRatioBIPS(_agent, _value);
        } else if (_hash == BUY_FASSET_BY_AGENT_FACTOR_BIPS) {
            AgentUpdates.setBuyFAssetByAgentFactorBIPS(_agent, _value);
        } else if (_hash == POOL_EXIT_COLLATERAL_RATIO_BIPS) {
            AgentUpdates.setPoolExitCollateralRatioBIPS(_agent, _value);
        } else {
            assert(false);
        }
    }

    function _getTimelock(bytes32 _hash) private view returns (uint64) {
        AssetManagerSettings.Data storage settings = Globals.getSettings();
        if (_hash == FEE_BIPS || _hash == POOL_FEE_SHARE_BIPS || _hash == REDEMPTION_POOL_FEE_SHARE_BIPS ||
            _hash == BUY_FASSET_BY_AGENT_FACTOR_BIPS) {
            return settings.agentFeeChangeTimelockSeconds;
        } else if (_hash == MINTING_VAULT_COLLATERAL_RATIO_BIPS || _hash == MINTING_POOL_COLLATERAL_RATIO_BIPS) {
            return settings.agentMintingCRChangeTimelockSeconds;
        } else {
            return settings.poolExitCRChangeTimelockSeconds;
        }
    }

    function _getAndCheckHash(string memory _name) private pure returns (bytes32) {
        bytes32 hash = keccak256(bytes(_name));
        bool settingNameValid =
            hash == FEE_BIPS ||
            hash == POOL_FEE_SHARE_BIPS ||
            hash == REDEMPTION_POOL_FEE_SHARE_BIPS ||
            hash == MINTING_VAULT_COLLATERAL_RATIO_BIPS ||
            hash == MINTING_POOL_COLLATERAL_RATIO_BIPS ||
            hash == BUY_FASSET_BY_AGENT_FACTOR_BIPS ||
            hash == POOL_EXIT_COLLATERAL_RATIO_BIPS;
        require(settingNameValid, InvalidSettingName());
        return hash;
    }
}
