// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import {IIsolatedEigenLayerVault} from "./IIsolatedEigenLayerVault.sol";
import {IIsolatedEigenLayerVaultFactory} from "./IIsolatedEigenLayerVaultFactory.sol";
import {IProtocolAdapter} from "./IProtocolAdapter.sol";
import {IDelegationManager} from "@eigenlayer-interfaces/IDelegationManager.sol";
import {IPausable} from "@eigenlayer-interfaces/IPausable.sol";
import {IRewardsCoordinator} from "@eigenlayer-interfaces/IRewardsCoordinator.sol";
import {IStrategy, IStrategyManager} from "@eigenlayer-interfaces/IStrategyManager.sol";

import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {IERC20, SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {IEigenLayerWithdrawalQueue} from "../queues/IEigenLayerWithdrawalQueue.sol";

interface IEigenLayerAdapter is IProtocolAdapter {
    function factory() external view returns (IIsolatedEigenLayerVaultFactory);

    function rewardsCoordinator() external view returns (IRewardsCoordinator);

    function strategyManager() external view returns (IStrategyManager);

    function delegationManager() external view returns (IDelegationManager);
}
