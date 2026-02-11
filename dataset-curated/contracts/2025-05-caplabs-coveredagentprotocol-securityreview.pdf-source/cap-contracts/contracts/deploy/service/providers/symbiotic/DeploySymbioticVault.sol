// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IBurnerRouter } from "@symbioticfi/burners/src/interfaces/router/IBurnerRouter.sol";
import { IBurnerRouterFactory } from "@symbioticfi/burners/src/interfaces/router/IBurnerRouterFactory.sol";
import { IBaseDelegator } from "@symbioticfi/core/src/interfaces/delegator/IBaseDelegator.sol";
import { Upgrades } from "openzeppelin-foundry-upgrades/Upgrades.sol";

import { IOperatorRegistry } from "@symbioticfi/core/src/interfaces/IOperatorRegistry.sol";
import { IOptInService } from "@symbioticfi/core/src/interfaces/service/IOptInService.sol";

import { NetworkRestakeDecreaseHook } from "./NetworkRestakeDecreaseHook.sol";
import { INetworkRegistry } from "@symbioticfi/core/src/interfaces/INetworkRegistry.sol";
import { IVaultConfigurator } from "@symbioticfi/core/src/interfaces/IVaultConfigurator.sol";
import { IDelegatorHook } from "@symbioticfi/core/src/interfaces/delegator/IDelegatorHook.sol";
import { SimpleBurner } from "@symbioticfi/core/test/mocks/SimpleBurner.sol";
import { IDefaultStakerRewards } from
    "@symbioticfi/rewards/src/interfaces/defaultStakerRewards/IDefaultStakerRewards.sol";
import { IDefaultStakerRewardsFactory } from
    "@symbioticfi/rewards/src/interfaces/defaultStakerRewards/IDefaultStakerRewardsFactory.sol";

import { ProxyUtils } from "../../../utils/ProxyUtils.sol";
import { IBaseDelegator } from "@symbioticfi/core/src/interfaces/delegator/IBaseDelegator.sol";
import { INetworkRestakeDelegator } from "@symbioticfi/core/src/interfaces/delegator/INetworkRestakeDelegator.sol";
import { INetworkMiddlewareService } from "@symbioticfi/core/src/interfaces/service/INetworkMiddlewareService.sol";
import { IBaseSlasher } from "@symbioticfi/core/src/interfaces/slasher/IBaseSlasher.sol";
import { ISlasher } from "@symbioticfi/core/src/interfaces/slasher/ISlasher.sol";
import { IVault } from "@symbioticfi/core/src/interfaces/vault/IVault.sol";

import { SymbioticVaultConfig, SymbioticVaultParams } from "../../../interfaces/SymbioticsDeployConfigs.sol";
import { DelegatorType, SlasherType, SymbioticAddressbook } from "../../../utils/SymbioticUtils.sol";

import { console } from "forge-std/console.sol";

contract DeploySymbioticVault is ProxyUtils {
    function _deploySymbioticVault(SymbioticAddressbook memory addressbook, SymbioticVaultParams memory params)
        internal
        returns (SymbioticVaultConfig memory config)
    {
        // deploy a default burner
        config.globalReceiver = address(new SimpleBurner(params.collateral));
        config.vaultEpochDuration = params.vaultEpochDuration;
        config.collateral = params.collateral;

        // burner router setup
        // https://docs.symbiotic.fi/guides/vault-deployment/#1-burner-router
        // https://docs.symbiotic.fi/guides/vault-deployment#network-specific-burners
        config.burnerRouter = address(
            IBurnerRouter(
                IBurnerRouterFactory(addressbook.factories.burnerRouterFactory).create(
                    IBurnerRouter.InitParams({
                        owner: params.vault_admin, // address of the router’s owner
                        collateral: params.collateral, // address of the collateral - wstETH (MUST be the same as for the Vault to connect)
                        delay: params.burnerRouterDelay, // duration of the receivers’ update delay (= 21 days)
                        globalReceiver: config.globalReceiver, // address of the pure burner corresponding to the collateral - wstETH_Burner (some collaterals are covered by us; see Deployments page)
                        networkReceivers: new IBurnerRouter.NetworkReceiver[](0), // array with IBurnerRouter.NetworkReceiver elements meaning network-specific receivers
                        operatorNetworkReceivers: new IBurnerRouter.OperatorNetworkReceiver[](0) // array with IBurnerRouter.OperatorNetworkReceiver elements meaning network-specific receivers
                     })
                )
            )
        );

        // vault setup
        // https://docs.symbiotic.fi/guides/vault-deployment/#vault
        NetworkRestakeDecreaseHook hook = new NetworkRestakeDecreaseHook();

        address[] memory networkLimitSetRoleHolders = new address[](2);
        networkLimitSetRoleHolders[0] = params.vault_admin;
        networkLimitSetRoleHolders[1] = address(hook);

        address[] memory operatorNetworkSharesSetRoleHolders = new address[](2);
        operatorNetworkSharesSetRoleHolders[0] = params.vault_admin;
        operatorNetworkSharesSetRoleHolders[1] = address(hook);

        (config.vault, config.delegator, config.slasher) = IVaultConfigurator(addressbook.services.vaultConfigurator)
            .create(
            IVaultConfigurator.InitParams({
                version: 1, // Vault’s version (= common one)
                owner: params.vault_admin, // address of the Vault’s owner (can migrate the Vault to new versions in the future)
                vaultParams: abi.encode(
                    IVault.InitParams({
                        collateral: params.collateral, // address of the collateral - wstETH
                        burner: config.burnerRouter, // address of the deployed burner router
                        epochDuration: params.vaultEpochDuration, // duration of the Vault epoch in seconds (= 7 days)
                        depositWhitelist: false, // if enable deposit whitelisting
                        isDepositLimit: false, // if enable deposit limit
                        depositLimit: 0, // deposit limit
                        defaultAdminRoleHolder: params.vault_admin, // address of the Vault’s admin (can manage all roles)
                        depositWhitelistSetRoleHolder: params.vault_admin, // address of the enabler/disabler of the deposit whitelisting
                        depositorWhitelistRoleHolder: params.vault_admin, // address of the depositors whitelister
                        isDepositLimitSetRoleHolder: params.vault_admin, // address of the enabler/disabler of the deposit limit
                        depositLimitSetRoleHolder: params.vault_admin // address of the deposit limit setter
                     })
                ),
                delegatorIndex: uint64(DelegatorType.NETWORK_RESTAKE), // Delegator’s type (= NetworkRestakeDelegator)
                delegatorParams: abi.encode(
                    INetworkRestakeDelegator.InitParams({
                        baseParams: IBaseDelegator.BaseParams({
                            defaultAdminRoleHolder: params.vault_admin, // address of the Delegator’s admin (can manage all roles)
                            hook: address(hook), // address of the hook (if not zero, receives onSlash() call on each slashing)
                            hookSetRoleHolder: params.vault_admin // address of the hook setter
                         }),
                        networkLimitSetRoleHolders: networkLimitSetRoleHolders, // array of addresses of the network limit setters
                        operatorNetworkSharesSetRoleHolders: operatorNetworkSharesSetRoleHolders // array of addresses of the operator-network shares setters
                     })
                ),
                withSlasher: true, // if enable Slasher module
                slasherIndex: uint64(SlasherType.INSTANT), // Slasher’s type (0 = ImmediateSlasher, 1 = VetoSlasher)
                slasherParams: abi.encode(
                    ISlasher.InitParams({
                        baseParams: IBaseSlasher.BaseParams({
                            isBurnerHook: true // if enable the `burner` to receive onSlash() call after each slashing (is needed for the burner router workflow)
                         })
                    })
                )
            })
        );

        console.log("deployed vault", config.vault);
    }
}
