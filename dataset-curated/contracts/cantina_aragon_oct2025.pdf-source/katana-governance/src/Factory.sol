// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { PermissionLib } from "@aragon/osx-commons-contracts/src/permission/PermissionLib.sol";
import { PermissionManager } from "@aragon/osx/core/permission/PermissionManager.sol";

import { VotingEscrow, Lock as LockNFT } from "@setup/GaugeVoterSetup_v1_4_0.sol";
import { Action } from "@aragon/osx-commons-contracts/src/executors/IExecutor.sol";
import { DAO } from "@aragon/osx/core/dao/DAO.sol";

import { ProxyLib } from "@aragon/osx-commons-contracts/src/utils/deployment/ProxyLib.sol";

import { AvKATVault } from "src/AvKATVault.sol";
import { VKatMetadata } from "src/VKatMetadata.sol";
import { IVKatMetadata } from "src/interfaces/IVKatMetadata.sol";
import { AragonMerklAutoCompoundStrategy as AutoCompoundStrategy } from
    "src/strategies/AragonMerklAutoCompoundStrategy.sol";

import { deploySwapper } from "src/utils/Deployers.sol";
import { DefaultStrategy } from "src/strategies/DefaultStrategy.sol";

struct BaseContracts {
    address vault;
    address autoCompoundStrategy;
    address defaultStrategy;
    address vkatMetadata;
}

struct DeploymentParameters {
    address merklDistributor;
    address dao;
    address escrow;
    address executor;
}

struct Deployment {
    address vault;
    address autoCompoundStrategy;
    address defaultStrategy;
    address swapper;
    address vkatMetadata;
}

contract Factory {
    using ProxyLib for address;

    address private owner;
    BaseContracts internal bases;

    DeploymentParameters parameters;
    Deployment deps;

    constructor(BaseContracts memory _bases) {
        owner = msg.sender;

        bases = _bases;
    }

    function deployOnce(DeploymentParameters memory _params) public returns (Deployment memory) {
        if (owner != msg.sender) revert("NOT_OWNER");
        if (deps.vault != address(0)) revert("ALREADY_DEPLOYED");

        // ======== Deploys Vkat Related contracts ========

        deps.defaultStrategy = bases.defaultStrategy.deployUUPSProxy(
            abi.encodeCall(DefaultStrategy.initialize, (_params.dao, _params.escrow, address(0)))
        );

        deps.vault = bases.vault.deployUUPSProxy(
            abi.encodeCall(
                AvKATVault.initialize,
                (_params.dao, _params.escrow, deps.defaultStrategy, "Autocompounding vKAT", "avKAT")
            )
        );

        DefaultStrategy(deps.defaultStrategy).initializeOwner(deps.vault);

        address nftLock = VotingEscrow(_params.escrow).lockNFT();

        // deploy swapper
        deps.swapper = deploySwapper(_params.merklDistributor, _params.escrow, _params.executor);

        deps.vkatMetadata = bases.vkatMetadata.deployUUPSProxy(
            abi.encodeCall(VKatMetadata.initialize, (_params.dao, nftLock, new address[](0)))
        );

        deps.autoCompoundStrategy = bases.autoCompoundStrategy.deployUUPSProxy(
            abi.encodeCall(
                AutoCompoundStrategy.initialize,
                (_params.dao, _params.escrow, deps.swapper, deps.vault, _params.merklDistributor)
            )
        );

        Action[] memory actions = getActions(_params.dao, _params.escrow, nftLock, deps);
        DAO(payable(_params.dao)).execute(bytes32(uint256(uint160(address(this)))), actions, 0);

        return deps;
    }

    function getActions(
        address _dao,
        address _escrow,
        address _nftLock,
        Deployment memory _deps
    )
        internal
        view
        returns (Action[] memory)
    {
        PermissionLib.MultiTargetPermission[] memory permissions = new PermissionLib.MultiTargetPermission[](6);

        // VKatMetadata permissions
        permissions[0] = PermissionLib.MultiTargetPermission({
            operation: PermissionLib.Operation.Grant,
            where: _deps.vkatMetadata,
            who: _dao,
            permissionId: VKatMetadata(_deps.vkatMetadata).ADMIN_ROLE(),
            condition: PermissionLib.NO_CONDITION
        });

        // compound strategy permissions
        permissions[1] = PermissionLib.MultiTargetPermission({
            operation: PermissionLib.Operation.Grant,
            where: _deps.autoCompoundStrategy,
            who: _dao,
            permissionId: AutoCompoundStrategy(_deps.autoCompoundStrategy).AUTOCOMPOUND_STRATEGY_ADMIN_ROLE(),
            condition: PermissionLib.NO_CONDITION
        });

        // default strategy permissions
        permissions[2] = PermissionLib.MultiTargetPermission({
            operation: PermissionLib.Operation.Grant,
            where: _deps.defaultStrategy,
            who: _dao,
            permissionId: DefaultStrategy(_deps.defaultStrategy).DEFAULT_STRATEGY_ADMIN_ROLE(),
            condition: PermissionLib.NO_CONDITION
        });

        // vault permissions
        permissions[3] = PermissionLib.MultiTargetPermission({
            operation: PermissionLib.Operation.Grant,
            where: _deps.vault,
            who: _dao,
            permissionId: AvKATVault(_deps.vault).VAULT_ADMIN_ROLE(),
            condition: PermissionLib.NO_CONDITION
        });

        permissions[4] = PermissionLib.MultiTargetPermission({
            operation: PermissionLib.Operation.Grant,
            where: _deps.vault,
            who: _dao,
            permissionId: AvKATVault(_deps.vault).SWEEPER_ROLE(),
            condition: PermissionLib.NO_CONDITION
        });

        // This factory needs execute permission on dao to work.
        // This revokes execute permission as all other work
        // has been done at this point.
        permissions[5] = PermissionLib.MultiTargetPermission({
            operation: PermissionLib.Operation.Revoke,
            where: _dao,
            who: address(this),
            permissionId: DAO(payable(_dao)).EXECUTE_PERMISSION_ID(),
            condition: PermissionLib.NO_CONDITION
        });

        Action[] memory actions = new Action[](6);

        actions[0].to = _dao;
        actions[0].data = abi.encodeCall(PermissionManager.applyMultiTargetPermissions, permissions);

        // make vault and strategies whitelisted for nft transfers
        actions[1].to = _nftLock;
        actions[1].data = abi.encodeCall(LockNFT.setWhitelisted, (_deps.vault, true));

        actions[2].to = _nftLock;
        actions[2].data = abi.encodeCall(LockNFT.setWhitelisted, (_deps.defaultStrategy, true));

        actions[3].to = _nftLock;
        actions[3].data = abi.encodeCall(LockNFT.setWhitelisted, (_deps.autoCompoundStrategy, true));

        actions[4].to = _escrow;
        actions[4].data = abi.encodeCall(VotingEscrow.setEnableSplit, (_deps.defaultStrategy, true));

        actions[5].to = _escrow;
        actions[5].data = abi.encodeCall(VotingEscrow.setEnableSplit, (_deps.autoCompoundStrategy, true));

        return actions;
    }
}
