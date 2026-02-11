// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import { AccessControl } from "../../../../access/AccessControl.sol";

import { Network } from "../../../../delegation/providers/symbiotic/Network.sol";
import { NetworkMiddleware } from "../../../../delegation/providers/symbiotic/NetworkMiddleware.sol";
import { InfraConfig, UsersConfig } from "../../../interfaces/DeployConfigs.sol";
import {
    SymbioticNetworkAdapterConfig,
    SymbioticNetworkAdapterImplementationsConfig,
    SymbioticNetworkAdapterParams,
    SymbioticNetworkRewardsConfig,
    SymbioticVaultConfig
} from "../../../interfaces/SymbioticsDeployConfigs.sol";
import { ProxyUtils } from "../../../utils/ProxyUtils.sol";
import { SymbioticAddressbook } from "../../../utils/SymbioticUtils.sol";

import { IBurnerRouter } from "@symbioticfi/burners/src/interfaces/router/IBurnerRouter.sol";

import { IOperatorRegistry } from "@symbioticfi/core/src/interfaces/IOperatorRegistry.sol";
import { IDefaultStakerRewards } from
    "@symbioticfi/rewards/src/interfaces/defaultStakerRewards/IDefaultStakerRewards.sol";
import { IDefaultStakerRewardsFactory } from
    "@symbioticfi/rewards/src/interfaces/defaultStakerRewards/IDefaultStakerRewardsFactory.sol";

contract DeployCapNetworkAdapter is ProxyUtils {
    function _deploySymbioticNetworkAdapterImplems()
        internal
        returns (SymbioticNetworkAdapterImplementationsConfig memory d)
    {
        d.network = address(new Network());
        d.networkMiddleware = address(new NetworkMiddleware());
    }

    function _deploySymbioticNetworkAdapterInfra(
        InfraConfig memory infra,
        SymbioticAddressbook memory addressbook,
        SymbioticNetworkAdapterImplementationsConfig memory implems,
        SymbioticNetworkAdapterParams memory params
    ) internal returns (SymbioticNetworkAdapterConfig memory d) {
        d.network = _proxy(address(implems.network));
        Network(d.network).initialize(infra.accessControl, addressbook.registries.networkRegistry);

        d.networkMiddleware = _proxy(address(implems.networkMiddleware));
        NetworkMiddleware(d.networkMiddleware).initialize(
            infra.accessControl,
            d.network,
            addressbook.registries.vaultRegistry,
            infra.oracle,
            params.vaultEpochDuration,
            params.feeAllowed
        );
    }

    function _deploySymbioticRestakerRewardContract(
        SymbioticAddressbook memory addressbook,
        UsersConfig memory users,
        SymbioticVaultConfig memory vaultConfig
    ) internal returns (SymbioticNetworkRewardsConfig memory d) {
        d.stakerRewarder = address(
            IDefaultStakerRewards(
                IDefaultStakerRewardsFactory(addressbook.factories.defaultStakerRewardsFactory).create(
                    IDefaultStakerRewards.InitParams({
                        vault: vaultConfig.vault, // address of the deployed Vault
                        adminFee: 1000, // admin fee percent to get from all the rewards distributions (10% = 1_000 | 100% = 10_000)
                        defaultAdminRoleHolder: users.staker_rewards_admin, // address of the main admin (can manage all roles)
                        adminFeeClaimRoleHolder: users.staker_rewards_admin, // address of the admin fee claimer
                        adminFeeSetRoleHolder: users.staker_rewards_admin // address of the admin fee setter
                     })
                )
            )
        );
    }

    function _initSymbioticNetworkAdapterAccessControl(
        InfraConfig memory infra,
        SymbioticNetworkAdapterConfig memory adapter,
        UsersConfig memory users
    ) internal {
        Network network = Network(adapter.network);
        NetworkMiddleware middleware = NetworkMiddleware(adapter.networkMiddleware);
        AccessControl accessControl = AccessControl(infra.accessControl);

        accessControl.grantAccess(middleware.registerVault.selector, address(middleware), users.middleware_admin);
        accessControl.grantAccess(middleware.registerAgent.selector, address(middleware), users.middleware_admin);
        accessControl.grantAccess(middleware.slash.selector, address(middleware), infra.delegation);
        accessControl.grantAccess(middleware.distributeRewards.selector, address(middleware), infra.delegation);

        accessControl.grantAccess(network.registerMiddleware.selector, address(network), users.middleware_admin);
        accessControl.grantAccess(network.registerVault.selector, address(network), users.middleware_admin);

        accessControl.grantAccess(middleware.registerVault.selector, address(middleware), address(network));
    }

    function _registerCapNetwork(SymbioticAddressbook memory addressbook, SymbioticNetworkAdapterConfig memory adapter)
        internal
    {
        Network(adapter.network).registerMiddleware(
            adapter.networkMiddleware, addressbook.services.networkMiddlewareService
        );
    }

    function _registerCapNetworkInVault(SymbioticNetworkAdapterConfig memory adapter, SymbioticVaultConfig memory vault)
        internal
    {
        IBurnerRouter(vault.burnerRouter).setNetworkReceiver(adapter.network, address(adapter.networkMiddleware));
        IBurnerRouter(vault.burnerRouter).acceptNetworkReceiver(adapter.network);
    }

    function _registerVaultsInNetworkMiddleware(
        SymbioticNetworkAdapterConfig memory adapter,
        SymbioticVaultConfig memory vault,
        address agent
    ) internal {
        NetworkMiddleware(adapter.networkMiddleware).registerAgent(vault.vault, agent);
    }

    function _agentRegisterAsOperator(SymbioticAddressbook memory addressbook) internal {
        IOperatorRegistry(addressbook.registries.operatorRegistry).registerOperator();
    }
}
