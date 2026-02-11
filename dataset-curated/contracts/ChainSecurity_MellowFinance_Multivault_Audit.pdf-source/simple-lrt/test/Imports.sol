// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import "forge-std/Test.sol";

import "../src/adapters/ERC4626Adapter.sol";
import "../src/adapters/EigenLayerAdapter.sol";
import "../src/adapters/EigenLayerWstETHAdapter.sol";
import "../src/adapters/IsolatedEigenLayerVault.sol";
import "../src/adapters/IsolatedEigenLayerVaultFactory.sol";
import "../src/adapters/IsolatedEigenLayerWstETHVault.sol";
import "../src/adapters/SymbioticAdapter.sol";

import "../src/queues/EigenLayerWithdrawalQueue.sol";
import {EigenLayerWithdrawalQueue as EigenLayerWstETHWithdrawalQueue} from
    "../src/queues/EigenLayerWithdrawalQueue.sol";
import "../src/queues/SymbioticWithdrawalQueue.sol";

import "../src/strategies/RatiosStrategy.sol";

import "../src/utils/Claimer.sol";
import "../src/utils/EthWrapper.sol";
import "../src/utils/WhitelistedEthWrapper.sol";

import "../src/vaults/ERC4626Vault.sol";
import "../src/vaults/MultiVault.sol";
import "../src/vaults/MultiVaultStorage.sol";
import "../src/vaults/VaultControl.sol";
import "../src/vaults/VaultControlStorage.sol";

import "./Constants.sol";
import "./SymbioticHelper.sol";

interface IELStrategyManager {
    function setWithdrawalDelayBlocks(uint256 _withdrawalDelayBlocks) external;
}
