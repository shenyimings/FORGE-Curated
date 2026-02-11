// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import { AccessControl } from "../../access/AccessControl.sol";

import { Delegation } from "../../delegation/Delegation.sol";
import { Lender } from "../../lendingPool/Lender.sol";
import { Oracle } from "../../oracle/Oracle.sol";

import { L2Token } from "../../token/L2Token.sol";
import { Vault } from "../../vault/Vault.sol";

import { PreMainnetVault } from "../../testnetCampaign/PreMainnetVault.sol";
import {
    ImplementationsConfig,
    InfraConfig,
    L2VaultConfig,
    PreMainnetInfraConfig,
    UsersConfig,
    VaultConfig
} from "../interfaces/DeployConfigs.sol";
import { LzAddressbook } from "../utils/LzUtils.sol";
import { ProxyUtils } from "../utils/ProxyUtils.sol";

contract DeployInfra is ProxyUtils {
    function _deployInfra(ImplementationsConfig memory implementations, UsersConfig memory users)
        internal
        returns (InfraConfig memory d)
    {
        // deploy proxy contracts
        d.accessControl = _proxy(implementations.accessControl);
        d.lender = _proxy(implementations.lender);
        d.oracle = _proxy(implementations.oracle);
        d.delegation = _proxy(implementations.delegation);

        // init infra instances
        AccessControl(d.accessControl).initialize(users.access_control_admin);
        Lender(d.lender).initialize(d.accessControl, d.delegation, d.oracle, 1.33e27, 1 hours, 1 days, 0.1e27, 0.7e27);
        Oracle(d.oracle).initialize(d.accessControl);
        Delegation(d.delegation).initialize(d.accessControl, d.oracle, 1 days);
    }

    function _deployPreMainnetInfra(
        LzAddressbook memory srcAddressbook,
        LzAddressbook memory dstAddressbook,
        address asset,
        uint48 maxCampaignLength
    ) internal returns (PreMainnetInfraConfig memory d) {
        d.preMainnetVault = address(
            new PreMainnetVault(asset, address(srcAddressbook.endpointV2), dstAddressbook.eid, maxCampaignLength)
        );
    }

    function _deployL2InfraForVault(
        UsersConfig memory users,
        VaultConfig memory l1Vault,
        LzAddressbook memory addressbook
    ) internal returns (L2VaultConfig memory d) {
        address lzEndpoint = address(addressbook.endpointV2);
        string memory name;
        string memory symbol;
        address delegate = users.vault_config_admin;

        name = Vault(l1Vault.capToken).name();
        symbol = Vault(l1Vault.capToken).symbol();
        d.bridgedCapToken = address(new L2Token(name, symbol, lzEndpoint, delegate));

        name = Vault(l1Vault.stakedCapToken).name();
        symbol = Vault(l1Vault.stakedCapToken).symbol();
        d.bridgedStakedCapToken = address(new L2Token(name, symbol, lzEndpoint, delegate));
    }
}
