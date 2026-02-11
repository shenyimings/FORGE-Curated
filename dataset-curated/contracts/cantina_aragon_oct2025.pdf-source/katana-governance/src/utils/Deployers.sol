// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import { ProxyLib } from "@aragon/osx-commons-contracts/src/utils/deployment/ProxyLib.sol";
import { AccessControlManager } from "@merkl/AccessControlManager.sol";
import { Distributor as MerklDistributor } from "@merkl/Distributor.sol";

import { AvKATVault } from "src/AvKATVault.sol";
import { Swapper } from "src/Swapper.sol";
import { AragonMerklAutoCompoundStrategy as AutoCompoundStrategy } from
    "src/strategies/AragonMerklAutoCompoundStrategy.sol";
import { VKatMetadata } from "src/VKatMetadata.sol";
import { IVKatMetadata } from "src/interfaces/IVKatMetadata.sol";

function deployVault(
    address _dao,
    address _escrow,
    address _defaultStrategy,
    string memory _name,
    string memory _symbol
)
    returns (address, address)
{
    address vaultBase = address(new AvKATVault());

    address vault = ProxyLib.deployUUPSProxy(
        vaultBase, abi.encodeCall(AvKATVault.initialize, (_dao, _escrow, _defaultStrategy, _name, _symbol))
    );

    return (vaultBase, vault);
}

function deploySwapper(address _merkleDistributor, address _escrow, address _executor) returns (address) {
    address swapper = address(new Swapper(_merkleDistributor, _escrow, _executor));
    return swapper;
}

function deployAutoCompoundStrategy(
    address _dao,
    address _escrow,
    address _swapper,
    address _vault,
    address _merklDistributor
)
    returns (address, address)
{
    address strategyBase = address(new AutoCompoundStrategy());

    address strategy = ProxyLib.deployUUPSProxy(
        strategyBase,
        abi.encodeCall(AutoCompoundStrategy.initialize, (_dao, _escrow, _swapper, _vault, _merklDistributor))
    );

    return (strategyBase, strategy);
}

function deployVKatMetadata(
    address _dao,
    address _token,
    address[] memory _rewardTokens,
    IVKatMetadata.VKatMetaDataV1 memory _defaultPreferences
)
    returns (address, address)
{
    address metadataBase = address(new VKatMetadata());

    address vkatMetadata =
        ProxyLib.deployUUPSProxy(metadataBase, abi.encodeCall(VKatMetadata.initialize, (_dao, _token, _rewardTokens)));

    return (metadataBase, vkatMetadata);
}

function deployMerklDistributor(address _aclManager, address _guardian) returns (address, address) {
    address acm = ProxyLib.deployUUPSProxy(
        address(new AccessControlManager()), abi.encodeCall(AccessControlManager.initialize, (_aclManager, _guardian))
    );

    address merklDistributor = ProxyLib.deployUUPSProxy(
        address(new MerklDistributor()), abi.encodeCall(MerklDistributor.initialize, AccessControlManager(acm))
    );

    return (acm, merklDistributor);
}
