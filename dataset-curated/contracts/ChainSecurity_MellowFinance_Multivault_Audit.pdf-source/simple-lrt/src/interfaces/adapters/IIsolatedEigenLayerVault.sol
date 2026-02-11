// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import {IEigenLayerWithdrawalQueue} from "../queues/IEigenLayerWithdrawalQueue.sol";
import {IIsolatedEigenLayerVaultFactory} from "./IIsolatedEigenLayerVaultFactory.sol";
import {IDelegationManager} from "@eigenlayer-interfaces/IDelegationManager.sol";
import {IRewardsCoordinator} from "@eigenlayer-interfaces/IRewardsCoordinator.sol";
import {ISignatureUtils} from "@eigenlayer-interfaces/ISignatureUtils.sol";
import {IStrategy, IStrategyManager} from "@eigenlayer-interfaces/IStrategyManager.sol";

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {IERC20, IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

interface IIsolatedEigenLayerVault {
    function factory() external view returns (address);

    function vault() external view returns (address);

    function asset() external view returns (address);

    function isDelegated() external view returns (bool);

    function initialize(address vault) external;

    function delegateTo(
        address manager,
        address operator,
        ISignatureUtils.SignatureWithExpiry memory signature,
        bytes32 salt
    ) external;

    function deposit(address manager, address strategy, uint256 assets) external;

    function withdraw(address queue, address reciever, uint256 request, bool flag) external;

    function processClaim(
        IRewardsCoordinator coodrinator,
        IRewardsCoordinator.RewardsMerkleClaim memory farmData,
        IERC20 rewardToken
    ) external;

    function claimWithdrawal(
        IDelegationManager manager,
        IDelegationManager.Withdrawal calldata data
    ) external returns (uint256 assets);

    function queueWithdrawals(
        IDelegationManager manager,
        IDelegationManager.QueuedWithdrawalParams[] calldata requests
    ) external;

    function sharesToUnderlyingView(address strategy, uint256 shares)
        external
        view
        returns (uint256 assets);

    function underlyingToSharesView(address strategy, uint256 assets)
        external
        view
        returns (uint256 shares);
}
