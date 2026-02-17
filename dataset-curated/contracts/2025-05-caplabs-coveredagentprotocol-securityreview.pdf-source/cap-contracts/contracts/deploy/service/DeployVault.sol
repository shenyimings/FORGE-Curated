// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import { AccessControl } from "../../access/AccessControl.sol";

import { Delegation } from "../../delegation/Delegation.sol";
import { NetworkMiddleware } from "../../delegation/providers/symbiotic/NetworkMiddleware.sol";

import { FeeAuction } from "../../feeAuction/FeeAuction.sol";

import { ILender } from "../../interfaces/ILender.sol";
import { IMinter } from "../../interfaces/IMinter.sol";

import { Lender } from "../../lendingPool/Lender.sol";
import { InterestDebtToken } from "../../lendingPool/tokens/InterestDebtToken.sol";
import { PrincipalDebtToken } from "../../lendingPool/tokens/PrincipalDebtToken.sol";
import { RestakerDebtToken } from "../../lendingPool/tokens/RestakerDebtToken.sol";
import { FractionalReserve } from "../../vault/FractionalReserve.sol";
import { Minter } from "../../vault/Minter.sol";

import { CapToken } from "../../token/CapToken.sol";
import { OFTLockbox } from "../../token/OFTLockbox.sol";
import { StakedCap } from "../../token/StakedCap.sol";
import { Vault } from "../../vault/Vault.sol";
import { ZapOFTComposer } from "../../zap/ZapOFTComposer.sol";
import {
    FeeConfig,
    ImplementationsConfig,
    InfraConfig,
    UsersConfig,
    VaultConfig,
    VaultLzPeriphery
} from "../interfaces/DeployConfigs.sol";

import { LzAddressbook } from "../utils/LzUtils.sol";
import { ProxyUtils } from "../utils/ProxyUtils.sol";
import { ZapAddressbook } from "../utils/ZapUtils.sol";

contract DeployVault is ProxyUtils {
    function _deployVault(
        ImplementationsConfig memory implementations,
        InfraConfig memory infra,
        string memory name,
        string memory symbol,
        address[] memory assets
    ) internal returns (VaultConfig memory d) {
        // deploy and init cap instances
        d.capToken = _proxy(implementations.capToken);
        d.stakedCapToken = _proxy(implementations.stakedCap);

        // deploy fee auction for this vault
        d.feeAuction = _proxy(implementations.feeAuction);
        FeeAuction(d.feeAuction).initialize(
            infra.accessControl,
            d.capToken, // payment token is the vault's cap token
            d.stakedCapToken, // payment recipient is the staked cap token
            3 hours, // 3 hour auctions
            1e18 // min price of 1 token
        );

        CapToken(d.capToken).initialize(name, symbol, infra.accessControl, d.feeAuction, infra.oracle, assets);
        StakedCap(d.stakedCapToken).initialize(infra.accessControl, d.capToken, 24 hours);

        // deploy and init debt tokens
        d.assets = assets;
        d.restakerInterestReceiver = infra.delegation;
        d.principalDebtTokens = new address[](assets.length);
        d.restakerDebtTokens = new address[](assets.length);
        d.interestDebtTokens = new address[](assets.length);
        for (uint256 i = 0; i < assets.length; i++) {
            d.principalDebtTokens[i] = _proxy(implementations.principalDebtToken);
            d.restakerDebtTokens[i] = _proxy(implementations.restakerDebtToken);
            d.interestDebtTokens[i] = _proxy(implementations.interestDebtToken);
            PrincipalDebtToken(d.principalDebtTokens[i]).initialize(infra.accessControl, assets[i]);
            RestakerDebtToken(d.restakerDebtTokens[i]).initialize(
                infra.accessControl, infra.oracle, d.principalDebtTokens[i], assets[i]
            );
            InterestDebtToken(d.interestDebtTokens[i]).initialize(
                infra.accessControl, infra.oracle, d.principalDebtTokens[i], assets[i]
            );
        }
    }

    function _deployVaultLzPeriphery(
        LzAddressbook memory lzAddressbook,
        ZapAddressbook memory zapAddressbook,
        VaultConfig memory vault,
        UsersConfig memory users
    ) internal returns (VaultLzPeriphery memory d) {
        // deploy the lockboxes
        d.capOFTLockbox =
            address(new OFTLockbox(vault.capToken, address(lzAddressbook.endpointV2), users.vault_config_admin));

        d.stakedCapOFTLockbox =
            address(new OFTLockbox(vault.stakedCapToken, address(lzAddressbook.endpointV2), users.vault_config_admin));

        // deploy the zap composers
        d.capZapComposer = address(
            new ZapOFTComposer(
                address(lzAddressbook.endpointV2),
                d.capOFTLockbox,
                zapAddressbook.zapRouter,
                zapAddressbook.tokenManager
            )
        );
        d.stakedCapZapComposer = address(
            new ZapOFTComposer(
                address(lzAddressbook.endpointV2),
                d.stakedCapOFTLockbox,
                zapAddressbook.zapRouter,
                zapAddressbook.tokenManager
            )
        );
    }

    function _initVaultAccessControl(InfraConfig memory infra, VaultConfig memory vault, UsersConfig memory users)
        internal
    {
        AccessControl accessControl = AccessControl(infra.accessControl);
        accessControl.grantAccess(Vault.borrow.selector, vault.capToken, infra.lender);
        accessControl.grantAccess(Vault.repay.selector, vault.capToken, infra.lender);
        accessControl.grantAccess(Minter.setFeeData.selector, vault.capToken, users.lender_admin);
        accessControl.grantAccess(Minter.setRedeemFee.selector, vault.capToken, users.lender_admin);
        accessControl.grantAccess(Vault.pause.selector, vault.capToken, users.vault_config_admin);
        accessControl.grantAccess(Vault.unpause.selector, vault.capToken, users.vault_config_admin);

        accessControl.grantAccess(FractionalReserve.setReserve.selector, vault.capToken, users.vault_config_admin);
        accessControl.grantAccess(
            FractionalReserve.setFractionalReserveVault.selector, vault.capToken, users.vault_config_admin
        );
        accessControl.grantAccess(FractionalReserve.investAll.selector, vault.capToken, users.vault_config_admin);
        accessControl.grantAccess(FractionalReserve.divestAll.selector, vault.capToken, users.vault_config_admin);
        accessControl.grantAccess(FractionalReserve.realizeInterest.selector, vault.capToken, users.vault_config_admin);

        // Configure FeeAuction access control
        accessControl.grantAccess(FeeAuction.setStartPrice.selector, vault.feeAuction, infra.lender);
        accessControl.grantAccess(FeeAuction.setDuration.selector, vault.feeAuction, infra.lender);
        accessControl.grantAccess(FeeAuction.setMinStartPrice.selector, vault.feeAuction, infra.lender);

        for (uint256 i = 0; i < vault.assets.length; i++) {
            accessControl.grantAccess(PrincipalDebtToken.mint.selector, vault.principalDebtTokens[i], infra.lender);
            accessControl.grantAccess(PrincipalDebtToken.burn.selector, vault.principalDebtTokens[i], infra.lender);
            accessControl.grantAccess(RestakerDebtToken.burn.selector, vault.restakerDebtTokens[i], infra.lender);
            accessControl.grantAccess(InterestDebtToken.burn.selector, vault.interestDebtTokens[i], infra.lender);
        }

        accessControl.grantAccess(FeeAuction.setMinStartPrice.selector, vault.feeAuction, users.fee_auction_admin);
        accessControl.grantAccess(FeeAuction.setDuration.selector, vault.feeAuction, users.fee_auction_admin);
        accessControl.grantAccess(FeeAuction.setStartPrice.selector, vault.feeAuction, users.fee_auction_admin);
    }

    function _initVaultLender(VaultConfig memory d, InfraConfig memory infra, FeeConfig memory fee) internal {
        for (uint256 i = 0; i < d.assets.length; i++) {
            Lender(infra.lender).addAsset(
                ILender.AddAssetParams({
                    asset: d.assets[i],
                    vault: d.capToken,
                    principalDebtToken: d.principalDebtTokens[i],
                    restakerDebtToken: d.restakerDebtTokens[i],
                    interestDebtToken: d.interestDebtTokens[i],
                    interestReceiver: d.feeAuction,
                    restakerInterestReceiver: d.restakerInterestReceiver,
                    bonusCap: 0.1e27
                })
            );

            Lender(infra.lender).pauseAsset(d.assets[i], false);

            Minter(d.capToken).setFeeData(
                d.assets[i],
                IMinter.FeeData({
                    slope0: fee.slope0,
                    slope1: fee.slope1,
                    mintKinkRatio: fee.mintKinkRatio,
                    burnKinkRatio: fee.burnKinkRatio,
                    optimalRatio: fee.optimalRatio
                })
            );
        }
    }
}
