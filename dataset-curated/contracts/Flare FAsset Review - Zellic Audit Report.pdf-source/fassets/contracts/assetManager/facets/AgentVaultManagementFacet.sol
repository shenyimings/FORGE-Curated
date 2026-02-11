// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {IAddressValidity} from "@flarenetwork/flare-periphery-contracts/flare/IFdcVerification.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {AssetManagerBase} from "./AssetManagerBase.sol";
import {Agents} from "../library/Agents.sol";
import {AgentUpdates} from "../library/AgentUpdates.sol";
import {Globals} from "../library/Globals.sol";
import {TransactionAttestation} from "../library/TransactionAttestation.sol";
import {Agent} from "../library/data/Agent.sol";
import {AssetManagerState} from "../library/data/AssetManagerState.sol";
import {UnderlyingAddressOwnership} from "../library/data/UnderlyingAddressOwnership.sol";
import {CoreVaultClient} from "../library/CoreVaultClient.sol";
import {IIAgentVault} from "../../agentVault/interfaces/IIAgentVault.sol";
import {IIAgentVaultFactory} from "../../agentVault/interfaces/IIAgentVaultFactory.sol";
import {IIAssetManager} from "../../assetManager/interfaces/IIAssetManager.sol";
import {IICollateralPool} from "../../collateralPool/interfaces/IICollateralPool.sol";
import {IICollateralPoolFactory} from "../../collateralPool/interfaces/IICollateralPoolFactory.sol";
import {IICollateralPoolTokenFactory} from "../../collateralPool/interfaces/IICollateralPoolTokenFactory.sol";
import {IUpgradableContractFactory} from "../../utils/interfaces/IUpgradableContractFactory.sol";
import {IUpgradableProxy} from "../../utils/interfaces/IUpgradableProxy.sol";
import {AgentSettings} from "../../userInterfaces/data/AgentSettings.sol";
import {AssetManagerSettings} from "../../userInterfaces/data/AssetManagerSettings.sol";
import {IAssetManagerEvents} from "../../userInterfaces/IAssetManagerEvents.sol";
import {ICollateralPool} from "../../userInterfaces/ICollateralPool.sol";
import {ICollateralPoolToken} from "../../userInterfaces/ICollateralPoolToken.sol";


contract AgentVaultManagementFacet is AssetManagerBase {
    using SafeCast for uint256;
    using UnderlyingAddressOwnership for UnderlyingAddressOwnership.State;
    using Agents for Agent.State;
    using AgentUpdates for Agent.State;

    uint256 internal constant MIN_SUFFIX_LEN = 2;
    uint256 internal constant MAX_SUFFIX_LEN = 20;

    error AddressInvalid();
    error AgentStillAvailable();
    error AgentStillActive();
    error DestroyNotAnnounced();
    error DestroyNotAllowedYet();
    error SuffixReserved();
    error SuffixInvalidFormat();
    error AddressUsedByCoreVault();

    /**
     * Create an agent.
     * Agent will always be identified by `_agentVault` address.
     * (Externally, same account may own several agent vaults,
     *  but in fasset system, each agent vault acts as an independent agent.)
     * NOTE: may only be called by a whitelisted agent
     * @return _agentVault the new agent vault address
     */
    function createAgentVault(
        IAddressValidity.Proof calldata _addressProof,
        AgentSettings.Data calldata _settings
    )
        external
        onlyAttached
        notEmergencyPaused
        returns (address _agentVault)
    {
        AssetManagerState.State storage state = AssetManagerState.get();
        // reserve suffix quickly to prevent griefing attacks by frontrunning agent creation
        // with same suffix, wasting agent owner gas
        _reserveAndValidatePoolTokenSuffix(_settings.poolTokenSuffix);
        // can be called from management or work owner address
        address ownerManagementAddress = _getManagementAddress(msg.sender);
        // management address must be whitelisted
        Agents.requireWhitelisted(ownerManagementAddress);
        // require valid address
        TransactionAttestation.verifyAddressValidity(_addressProof);
        IAddressValidity.ResponseBody memory avb = _addressProof.data.responseBody;
        require(avb.isValid, AddressInvalid());
        require(avb.standardAddressHash != CoreVaultClient.coreVaultUnderlyingAddressHash(), AddressUsedByCoreVault());
        IIAssetManager assetManager = IIAssetManager(address(this));
        // create agent vault
        IIAgentVaultFactory agentVaultFactory = IIAgentVaultFactory(Globals.getSettings().agentVaultFactory);
        IIAgentVault agentVault = agentVaultFactory.create(assetManager);
        // set initial status
        Agent.State storage agent = Agent.getWithoutCheck(address(agentVault));
        assert(agent.status == Agent.Status.EMPTY);     // state should be empty on creation
        agent.status = Agent.Status.NORMAL;
        agent.ownerManagementAddress = ownerManagementAddress;
        // set collateral token types
        agent.setVaultCollateral(_settings.vaultCollateralToken);
        agent.poolCollateralIndex = state.poolCollateralIndex;
        // set initial collateral ratios
        agent.setMintingVaultCollateralRatioBIPS(_settings.mintingVaultCollateralRatioBIPS);
        agent.setMintingPoolCollateralRatioBIPS(_settings.mintingPoolCollateralRatioBIPS);
        // set minting fee and share
        agent.setFeeBIPS(_settings.feeBIPS);
        agent.setPoolFeeShareBIPS(_settings.poolFeeShareBIPS);
        agent.setBuyFAssetByAgentFactorBIPS(_settings.buyFAssetByAgentFactorBIPS);
        // claim the underlying address to make sure no other agent is using it
        state.underlyingAddressOwnership.claimAndTransfer(address(agentVault), avb.standardAddressHash);
        // set underlying address
        agent.underlyingAddressString = avb.standardAddress;
        agent.underlyingAddressHash = avb.standardAddressHash;
        agent.underlyingBlockAtCreation = state.currentUnderlyingBlock;
        // add collateral pool
        agent.collateralPool = _createCollateralPool(assetManager, address(agentVault), _settings);
        // run the pool setters just for validation
        agent.setPoolExitCollateralRatioBIPS(_settings.poolExitCollateralRatioBIPS);
        // set redemption pool fee share
        agent.setRedemptionPoolFeeShareBIPS(_settings.redemptionPoolFeeShareBIPS);
        // add to the list of all agents
        agent.allAgentsPos = state.allAgents.length.toUint32();
        state.allAgents.push(address(agentVault));
        // notify
        _emitAgentVaultCreated(ownerManagementAddress, address(agentVault), agent.collateralPool,
            avb.standardAddress, _settings);
        return address(agentVault);
    }

    /**
     * Announce that the agent is going to be destroyed. At this time, agent must not have any mintings
     * or collateral reservations and must not be on the available agents list.
     * NOTE: may only be called by the agent vault owner.
     * @return _destroyAllowedAt the timestamp at which the destroy can be executed
     */
    function announceDestroyAgent(
        address _agentVault
    )
        external
        notEmergencyPaused
        onlyAgentVaultOwner(_agentVault)
        returns (uint256 _destroyAllowedAt)
    {
        AssetManagerSettings.Data storage settings = Globals.getSettings();
        Agent.State storage agent = Agent.get(_agentVault);
        // all minting must stop and all minted assets must have been cleared
        require(agent.availableAgentsPos == 0, AgentStillAvailable());
        require(agent.totalBackedAMG() == 0, AgentStillActive());
        // if not destroying yet, start timing
        if (agent.status != Agent.Status.DESTROYING) {
            agent.status = Agent.Status.DESTROYING;
            uint256 destroyAllowedAt = block.timestamp + settings.withdrawalWaitMinSeconds;
            agent.destroyAllowedAt = destroyAllowedAt.toUint64();
            emit IAssetManagerEvents.AgentDestroyAnnounced(_agentVault, destroyAllowedAt);
        }
        return agent.destroyAllowedAt;
    }

    /**
     * Destroy agent - agent vault and collateral pool (send remaining collateral to the `_recipient`).
     * Procedure for destroying agent:
     * - exit available agents list
     * - wait until all assets are redeemed or perform self-close
     * - announce destroy (and wait the required time)
     * - call destroyAgent()
     * NOTE: may only be called by the agent vault owner.
     * NOTE: the remaining funds from the vault will be transferred to the provided recipient.
     * @param _agentVault address of the agent's vault to destroy
     * @param _recipient address that receives the remaining funds and possible vault balance
     */
    function destroyAgent(
        address _agentVault,
        address payable _recipient
    )
        external
        notFullyEmergencyPaused
        onlyAgentVaultOwner(_agentVault)
    {
        AssetManagerState.State storage state = AssetManagerState.get();
        Agent.State storage agent = Agent.get(_agentVault);
        // destroy must have been announced enough time before
        require(agent.status == Agent.Status.DESTROYING, DestroyNotAnnounced());
        require(block.timestamp > agent.destroyAllowedAt, DestroyNotAllowedYet());
        // cannot have any minting when in destroying status
        assert(agent.totalBackedAMG() == 0);
        // destroy pool
        agent.collateralPool.destroy(_recipient);
        // destroy agent vault
        IIAgentVault(_agentVault).destroy();
        // remove from the list of all agents
        uint256 ind = agent.allAgentsPos;
        if (ind + 1 < state.allAgents.length) {
            state.allAgents[ind] = state.allAgents[state.allAgents.length - 1];
            Agent.State storage movedAgent = Agent.get(state.allAgents[ind]);
            movedAgent.allAgentsPos = uint32(ind);
        }
        state.allAgents.pop();
        // mark as destroyed
        agent.status = Agent.Status.DESTROYED;
        // notify
        emit IAssetManagerEvents.AgentDestroyed(_agentVault);
    }

    /**
     * When agent vault, collateral pool or collateral pool token factory is upgraded, new agent vaults
     * automatically get the new implementation from the factory. But the existing agent vaults must
     * be upgraded by their owners using this method.
     * NOTE: may only be called by the agent vault owner.
     * @param _agentVault address of the agent's vault; both vault, its corresponding pool, and
     *  its pool token will be upgraded to the newest implementations
     */
    function upgradeAgentVaultAndPool(
        address _agentVault
    )
        external
        notEmergencyPaused
        onlyAgentVaultOwner(_agentVault)
    {
        _upgradeAgentVaultAndPool(_agentVault);
    }

    /**
     * When agent vault, collateral pool or collateral pool token factory is upgraded, new agent vaults
     * automatically get the new implementation from the factory. The existing vaults can be batch updated
     * by this method.
     * Parameters `_start` and `_end` allow limiting the upgrades to a selection of all agents, to avoid
     * breaking the block gas limit.
     * NOTE: may not be called directly - only through asset manager controller by governance.
     * @param _start the start index of the list of agent vaults (in getAllAgents()) to upgrade
     * @param _end the end index (exclusive) of the list of agent vaults to upgrade;
     *  can be larger then the number of agents, if gas is not an issue
     */
    function upgradeAgentVaultsAndPools(
        uint256 _start,
        uint256 _end
    )
        external
        onlyAssetManagerController
    {
        (address[] memory _agents,) = Agents.getAllAgents(_start, _end);
        for (uint256 i = 0; i < _agents.length; i++) {
            _upgradeAgentVaultAndPool(_agents[i]);
        }
    }

    function _upgradeAgentVaultAndPool(address _agentVault)
        private
    {
        AssetManagerSettings.Data storage settings = Globals.getSettings();
        ICollateralPool collateralPool = Agent.get(_agentVault).collateralPool;
        ICollateralPoolToken collateralPoolToken = collateralPool.poolToken();
        _upgradeContract(IIAgentVaultFactory(settings.agentVaultFactory), _agentVault);
        _upgradeContract(IICollateralPoolFactory(settings.collateralPoolFactory),
            address(collateralPool));
        _upgradeContract(IICollateralPoolTokenFactory(settings.collateralPoolTokenFactory),
            address(collateralPoolToken));
    }

    function _upgradeContract(
        IUpgradableContractFactory _factory,
        address _proxyAddress
    )
        private
    {
        IUpgradableProxy proxy = IUpgradableProxy(_proxyAddress);
        address newImplementation = _factory.implementation();
        address currentImplementation = proxy.implementation();
        if (currentImplementation != newImplementation) {
            bytes memory initCall = _factory.upgradeInitCall(_proxyAddress);
            if (initCall.length > 0) {
                proxy.upgradeToAndCall(newImplementation, initCall);
            } else {
                proxy.upgradeTo(newImplementation);
            }
        }
    }

    function _createCollateralPool(
        IIAssetManager _assetManager,
        address _agentVault,
        AgentSettings.Data calldata _settings
    )
        private
        returns (IICollateralPool)
    {
        AssetManagerSettings.Data storage globalSettings = Globals.getSettings();
        IICollateralPoolFactory collateralPoolFactory =
            IICollateralPoolFactory(globalSettings.collateralPoolFactory);
        IICollateralPoolTokenFactory poolTokenFactory =
            IICollateralPoolTokenFactory(globalSettings.collateralPoolTokenFactory);
        IICollateralPool collateralPool = collateralPoolFactory.create(_assetManager, _agentVault, _settings);
        address poolToken =
            poolTokenFactory.create(collateralPool, globalSettings.poolTokenSuffix, _settings.poolTokenSuffix);
        collateralPool.setPoolToken(poolToken);
        return collateralPool;
    }

    function _reserveAndValidatePoolTokenSuffix(string memory _suffix)
        private
    {
        AssetManagerState.State storage state = AssetManagerState.get();
        // reserve unique suffix
        require(!state.reservedPoolTokenSuffixes[_suffix], SuffixReserved());
        state.reservedPoolTokenSuffixes[_suffix] = true;
        // validate - require only printable ASCII characters (no spaces) and limited length
        bytes memory suffixb = bytes(_suffix);
        uint256 len = suffixb.length;
        require(len >= MIN_SUFFIX_LEN, SuffixInvalidFormat());
        require(len <= MAX_SUFFIX_LEN, SuffixInvalidFormat());
        for (uint256 i = 0; i < len; i++) {
            bytes1 ch = suffixb[i];
            // allow A-Z, 0-9 and '-' (but not at start or end)
            require((ch >= "A" && ch <= "Z") || (ch >= "0" && ch <= "9") || (i > 0 && i < len - 1 && ch == "-"),
                SuffixInvalidFormat());
        }
    }

    // Basically the same as `emit IAssetManagerEvents.AgentVaultCreated`.
    // Must be a separate method as workaround for EVM 16 stack variables limit.
    function _emitAgentVaultCreated(
        address _ownerManagementAddress,
        address _agentVault,
        IICollateralPool _collateralPool,
        string memory _underlyingAddress,
        AgentSettings.Data calldata _settings
    )
        private
    {
        IAssetManagerEvents.AgentVaultCreationData memory data;
        data.collateralPool = address(_collateralPool);
        data.collateralPoolToken = address(_collateralPool.poolToken());
        data.vaultCollateralToken = address(_settings.vaultCollateralToken);
        data.poolWNatToken = address(_collateralPool.wNat());
        data.underlyingAddress = _underlyingAddress;
        data.feeBIPS = _settings.feeBIPS;
        data.poolFeeShareBIPS = _settings.poolFeeShareBIPS;
        data.mintingVaultCollateralRatioBIPS = _settings.mintingVaultCollateralRatioBIPS;
        data.mintingPoolCollateralRatioBIPS = _settings.mintingPoolCollateralRatioBIPS;
        data.buyFAssetByAgentFactorBIPS = _settings.buyFAssetByAgentFactorBIPS;
        data.poolExitCollateralRatioBIPS = _settings.poolExitCollateralRatioBIPS;
        data.redemptionPoolFeeShareBIPS = _settings.redemptionPoolFeeShareBIPS;
        emit IAssetManagerEvents.AgentVaultCreated(_ownerManagementAddress, _agentVault, data);
    }

    // Returns management owner's address, given either work or management address.
    function _getManagementAddress(address _ownerAddress)
        private view
        returns (address)
    {
        address ownerManagementAddress = Globals.getAgentOwnerRegistry().getManagementAddress(_ownerAddress);
        return ownerManagementAddress != address(0) ? ownerManagementAddress : _ownerAddress;
    }
}
