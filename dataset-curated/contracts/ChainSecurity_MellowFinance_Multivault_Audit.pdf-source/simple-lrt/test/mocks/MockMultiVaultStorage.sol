// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import "../Imports.sol";

contract MockMultiVaultStorage is MultiVaultStorage {
    constructor(bytes32 name_, uint256 version_) MultiVaultStorage(name_, version_) {}

    function initializeMultiVaultStorage(
        address depositStrategy_,
        address withdrawalStrategy_,
        address rebalanceStrategy_,
        address defaultCollateral_,
        address symbioticAdapter_,
        address eigenLayerAdapter_,
        address erc4626Adapter_
    ) external initializer {
        __initializeMultiVaultStorage(
            depositStrategy_,
            withdrawalStrategy_,
            rebalanceStrategy_,
            defaultCollateral_,
            symbioticAdapter_,
            eigenLayerAdapter_,
            erc4626Adapter_
        );
    }

    function setSymbioticAdapter(address symbioticAdapter_) external {
        _setSymbioticAdapter(symbioticAdapter_);
    }

    function setEigenLayerAdapter(address eigenLayerAdapter_) external {
        _setEigenLayerAdapter(eigenLayerAdapter_);
    }

    function setERC4626Adapter(address erc4626Adapter_) external {
        _setERC4626Adapter(erc4626Adapter_);
    }

    function setDepositStrategy(address newDepositStrategy) external {
        _setDepositStrategy(newDepositStrategy);
    }

    function setWithdrawalStrategy(address newWithdrawalStrategy) external {
        _setWithdrawalStrategy(newWithdrawalStrategy);
    }

    function setRebalanceStrategy(address newRebalanceStrategy) external {
        _setRebalanceStrategy(newRebalanceStrategy);
    }

    function setDefaultCollateral(address defaultCollateral_) external {
        _setDefaultCollateral(defaultCollateral_);
    }

    function addSubvault(address vault, address withdrawalQueue, Protocol protocol) external {
        _addSubvault(vault, withdrawalQueue, protocol);
    }

    function removeSubvault(address vault) external {
        _removeSubvault(vault);
    }

    function setRewardData(uint256 farmId, RewardData memory data) external {
        _setRewardData(farmId, data);
    }

    function testMultiVaultStorage() internal pure {}
}
