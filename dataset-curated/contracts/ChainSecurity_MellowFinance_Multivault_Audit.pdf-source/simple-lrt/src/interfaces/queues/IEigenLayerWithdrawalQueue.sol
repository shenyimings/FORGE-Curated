// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import {IIsolatedEigenLayerVault} from "../adapters/IIsolatedEigenLayerVault.sol";
import {IWithdrawalQueue} from "./IWithdrawalQueue.sol";
import {IDelegationManager} from "@eigenlayer-interfaces/IDelegationManager.sol";
import {IStrategy} from "@eigenlayer-interfaces/IStrategy.sol";

import {IDelegationManagerExtended} from "../utils/IDelegationManagerExtended.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {IERC20, SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

interface IEigenLayerWithdrawalQueue is IWithdrawalQueue {
    struct WithdrawalData {
        IDelegationManager.Withdrawal data;
        bool isClaimed;
        uint256 assets;
        uint256 shares;
        mapping(address account => uint256) sharesOf;
    }

    struct AccountData {
        uint256 claimableAssets;
        EnumerableSet.UintSet withdrawals;
        EnumerableSet.UintSet transferredWithdrawals;
    }

    function MAX_WITHDRAWALS() external view returns (uint256);

    function isolatedVault() external view returns (address);

    function claimer() external view returns (address);

    function delegation() external view returns (address);

    function strategy() external view returns (address);

    function operator() external view returns (address);

    function isShutdown() external view returns (bool);

    function latestWithdrawableBlock() external view returns (uint256);

    function getAccountData(
        address account,
        uint256 withdrawalsLimit,
        uint256 withdrawalsOffset,
        uint256 transferredWithdrawalsLimit,
        uint256 transferredWithdrawalsOffset
    )
        external
        view
        returns (
            uint256 claimableAssets,
            uint256[] memory withdrawals,
            uint256[] memory transferredWithdrawals
        );

    function getWithdrawalRequest(uint256 index, address account)
        external
        view
        returns (
            IDelegationManager.Withdrawal memory data,
            bool isClaimed,
            uint256 assets,
            uint256 shares,
            uint256 accountShares
        );

    function withdrawalRequests() external view returns (uint256);

    function initialize(address isolatedVault_, address strategy_, address operator_) external;

    function request(address account, uint256 assets, bool isSelfRequested) external;

    function handleWithdrawals(address account) external;

    function acceptPendingAssets(address account, uint256[] calldata withdrawals_) external;

    // permissionless function
    function shutdown(uint32 blockNumber, uint256 shares) external;

    event Transfer(
        address indexed from, address indexed to, uint256 indexed withdrawalIndex, uint256 assets
    );

    event Pull(uint256 indexed withdrawalIndex, uint256 assets);

    event Handled(address indexed account, uint256 indexed withdrawalIndex, uint256 assets);

    event Request(
        address indexed account,
        uint256 indexed withdrawalIndex,
        uint256 assets,
        bool isSelfRequested
    );

    event Claimed(address indexed account, address indexed to, uint256 assets);

    event Accepted(address indexed account, uint256 indexed withdrawalIndex);

    event Shutdown(address indexed sender, uint32 indexed blockNumber, uint256 indexed shares);
}
