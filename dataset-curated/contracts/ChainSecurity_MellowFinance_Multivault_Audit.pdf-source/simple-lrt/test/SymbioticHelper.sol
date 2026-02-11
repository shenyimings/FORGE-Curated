// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import "./Constants.sol";
import "./Imports.sol";
import "./RandomLib.sol";
import {IDelegatorFactory} from "@symbiotic/core/interfaces/IDelegatorFactory.sol";
import {INetworkRegistry} from "@symbiotic/core/interfaces/INetworkRegistry.sol";
import {IOperatorRegistry} from "@symbiotic/core/interfaces/IOperatorRegistry.sol";
import {ISlasherFactory} from "@symbiotic/core/interfaces/ISlasherFactory.sol";
import {IVaultConfigurator} from "@symbiotic/core/interfaces/IVaultConfigurator.sol";
import {IVaultFactory} from "@symbiotic/core/interfaces/IVaultFactory.sol";
import {
    IBaseDelegator,
    IFullRestakeDelegator
} from "@symbiotic/core/interfaces/delegator/IFullRestakeDelegator.sol";
import {INetworkMiddlewareService} from
    "@symbiotic/core/interfaces/service/INetworkMiddlewareService.sol";
import {ISlasher} from "@symbiotic/core/interfaces/slasher/ISlasher.sol";
import {IBaseSlasher, IVetoSlasher} from "@symbiotic/core/interfaces/slasher/IVetoSlasher.sol";
import {IVault as ISymbioticVault} from "@symbiotic/core/interfaces/vault/IVault.sol";
import {IDefaultStakerRewards} from
    "@symbiotic/rewards/interfaces/defaultStakerRewards/IDefaultStakerRewards.sol";

contract SymbioticHelper {
    using RandomLib for RandomLib.Storage;

    Constants.SymbioticDeployment private deployment = Constants.symbioticDeployment();
    RandomLib.Storage private rnd = RandomLib.Storage(0xcaca0);

    function createSymbioticVault(
        address asset,
        address burner,
        uint256 depositLimit,
        uint48 epochDuration
    ) public returns (address symbioticVault, address delegator, address slasher, address admin) {
        admin = rnd.randAddress();
        (symbioticVault, delegator, slasher) = IVaultConfigurator(deployment.vaultConfigurator)
            .create(
            IVaultConfigurator.InitParams({
                version: 1,
                owner: admin,
                vaultParams: abi.encode(
                    ISymbioticVault.InitParams({
                        collateral: asset,
                        burner: burner,
                        epochDuration: epochDuration,
                        depositWhitelist: false,
                        isDepositLimit: depositLimit != type(uint256).max,
                        depositLimit: depositLimit,
                        defaultAdminRoleHolder: admin,
                        depositWhitelistSetRoleHolder: admin,
                        depositorWhitelistRoleHolder: admin,
                        isDepositLimitSetRoleHolder: admin,
                        depositLimitSetRoleHolder: admin
                    })
                ),
                delegatorIndex: 0,
                delegatorParams: abi.encode(
                    IFullRestakeDelegator.InitParams({
                        baseParams: IBaseDelegator.BaseParams({
                            defaultAdminRoleHolder: rnd.randAddress(),
                            hook: address(0),
                            hookSetRoleHolder: rnd.randAddress()
                        }),
                        networkLimitSetRoleHolders: new address[](0),
                        operatorNetworkLimitSetRoleHolders: new address[](0)
                    })
                ),
                withSlasher: true,
                slasherIndex: 0,
                slasherParams: abi.encode(
                    IVetoSlasher.InitParams({
                        baseParams: IBaseSlasher.BaseParams({isBurnerHook: false}),
                        vetoDuration: 1 hours,
                        resolverSetEpochsDelay: 3
                    })
                )
            })
        );
    }

    function createDefaultSymbioticVault(address asset)
        public
        returns (address symbioticVault, address delegator, address slasher, address admin)
    {
        return createSymbioticVault(asset, address(0), type(uint256).max, 1 weeks);
    }

    function testSymbioticHelper() internal pure {}
}
