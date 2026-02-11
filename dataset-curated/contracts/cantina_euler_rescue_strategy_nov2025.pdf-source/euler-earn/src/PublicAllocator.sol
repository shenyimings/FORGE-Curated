// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.26;

import {
    FlowCaps,
    FlowCapsConfig,
    Withdrawal,
    MAX_SETTABLE_FLOW_CAP,
    IPublicAllocatorStaticTyping,
    IPublicAllocatorBase
} from "./interfaces/IPublicAllocator.sol";
import {IEulerEarn, MarketAllocation} from "./interfaces/IEulerEarn.sol";

import {ErrorsLib} from "./libraries/ErrorsLib.sol";
import {EventsLib} from "./libraries/EventsLib.sol";

import {IERC4626} from "openzeppelin-contracts/interfaces/IERC4626.sol";
import {EVCUtil} from "ethereum-vault-connector/utils/EVCUtil.sol";

/// @title PublicAllocator
/// @author Forked with gratitude from Morpho Labs. Inspired by Silo Labs.
/// @custom:contact security@morpho.org
/// @custom:contact security@euler.xyz
/// @notice Publicly callable allocator for EulerEarn vaults.
contract PublicAllocator is EVCUtil, IPublicAllocatorStaticTyping {
    /* STORAGE */

    /// @inheritdoc IPublicAllocatorBase
    mapping(address => address) public admin;
    /// @inheritdoc IPublicAllocatorBase
    mapping(address => uint256) public fee;
    /// @inheritdoc IPublicAllocatorBase
    mapping(address => uint256) public accruedFee;
    /// @inheritdoc IPublicAllocatorStaticTyping
    mapping(address => mapping(IERC4626 => FlowCaps)) public flowCaps;

    /* MODIFIER */

    /// @dev Reverts if the caller is not the admin nor the owner of this vault.
    modifier onlyAdminOrVaultOwner(address vault) {
        address msgSender = _authenticateCallerWithStandardContextState(true);
        if (msgSender != admin[vault] && msgSender != IEulerEarn(vault).owner()) {
            revert ErrorsLib.NotAdminNorVaultOwner();
        }
        _;
    }

    /* CONSTRUCTOR */

    /// @dev Initializes the contract.
    constructor(address evc) EVCUtil(evc) {}

    /* ADMIN OR VAULT OWNER ONLY */

    /// @inheritdoc IPublicAllocatorBase
    function setAdmin(address vault, address newAdmin) external onlyAdminOrVaultOwner(vault) {
        if (admin[vault] == newAdmin) revert ErrorsLib.AlreadySet();
        admin[vault] = newAdmin;
        emit EventsLib.SetAdmin(_msgSender(), vault, newAdmin);
    }

    /// @inheritdoc IPublicAllocatorBase
    function setFee(address vault, uint256 newFee) external onlyAdminOrVaultOwner(vault) {
        if (fee[vault] == newFee) revert ErrorsLib.AlreadySet();
        fee[vault] = newFee;
        emit EventsLib.SetAllocationFee(_msgSender(), vault, newFee);
    }

    /// @inheritdoc IPublicAllocatorBase
    function setFlowCaps(address vault, FlowCapsConfig[] calldata config) external onlyAdminOrVaultOwner(vault) {
        for (uint256 i = 0; i < config.length; i++) {
            IERC4626 id = config[i].id;
            if (!IEulerEarn(vault).config(id).enabled && (config[i].caps.maxIn > 0 || config[i].caps.maxOut > 0)) {
                revert ErrorsLib.MarketNotEnabled(id);
            }
            if (config[i].caps.maxIn > MAX_SETTABLE_FLOW_CAP || config[i].caps.maxOut > MAX_SETTABLE_FLOW_CAP) {
                revert ErrorsLib.MaxSettableFlowCapExceeded();
            }
            flowCaps[vault][id] = config[i].caps;
        }

        emit EventsLib.SetFlowCaps(_msgSender(), vault, config);
    }

    /// @inheritdoc IPublicAllocatorBase
    function transferFee(address vault, address payable feeRecipient) external onlyAdminOrVaultOwner(vault) {
        uint256 claimed = accruedFee[vault];
        accruedFee[vault] = 0;
        (bool success,) = feeRecipient.call{value: claimed}("");
        if (!success) revert ErrorsLib.FeeTransferFailed(feeRecipient);
        emit EventsLib.TransferAllocationFee(_msgSender(), vault, claimed, feeRecipient);
    }

    /* PUBLIC */

    /// @inheritdoc IPublicAllocatorBase
    function reallocateTo(address vault, Withdrawal[] calldata withdrawals, IERC4626 supplyId) external payable {
        if (msg.value != fee[vault]) revert ErrorsLib.IncorrectFee();
        if (msg.value > 0) accruedFee[vault] += msg.value;

        if (withdrawals.length == 0) revert ErrorsLib.EmptyWithdrawals();

        if (!IEulerEarn(vault).config(supplyId).enabled) revert ErrorsLib.MarketNotEnabled(supplyId);

        MarketAllocation[] memory allocations = new MarketAllocation[](withdrawals.length + 1);
        uint128 totalWithdrawn;

        IERC4626 id;
        IERC4626 prevId;
        for (uint256 i = 0; i < withdrawals.length; i++) {
            prevId = id;
            id = withdrawals[i].id;
            if (!IEulerEarn(vault).config(id).enabled) revert ErrorsLib.MarketNotEnabled(id);
            uint128 withdrawnAssets = withdrawals[i].amount;
            if (withdrawnAssets == 0) revert ErrorsLib.WithdrawZero(id);

            if (address(id) <= address(prevId)) revert ErrorsLib.InconsistentWithdrawals();
            if (address(id) == address(supplyId)) revert ErrorsLib.DepositMarketInWithdrawals();

            uint256 assets = IEulerEarn(vault).expectedSupplyAssets(id);

            if (flowCaps[vault][id].maxOut < withdrawnAssets) revert ErrorsLib.MaxOutflowExceeded(id);
            if (assets < withdrawnAssets) revert ErrorsLib.NotEnoughSupply(id);

            flowCaps[vault][id].maxIn += withdrawnAssets;
            flowCaps[vault][id].maxOut -= withdrawnAssets;
            allocations[i].id = withdrawals[i].id;
            allocations[i].assets = assets - withdrawnAssets;

            totalWithdrawn += withdrawnAssets;

            emit EventsLib.PublicWithdrawal(_msgSender(), vault, id, withdrawnAssets);
        }

        if (flowCaps[vault][supplyId].maxIn < totalWithdrawn) revert ErrorsLib.MaxInflowExceeded(supplyId);

        flowCaps[vault][supplyId].maxIn -= totalWithdrawn;
        flowCaps[vault][supplyId].maxOut += totalWithdrawn;
        allocations[withdrawals.length].id = supplyId;
        allocations[withdrawals.length].assets = type(uint256).max;

        IEulerEarn(vault).reallocate(allocations);

        emit EventsLib.PublicReallocateTo(_msgSender(), vault, supplyId, totalWithdrawn);
    }
}
