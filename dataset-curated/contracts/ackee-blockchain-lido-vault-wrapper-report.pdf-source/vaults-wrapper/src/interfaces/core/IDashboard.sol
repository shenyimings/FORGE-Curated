// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0;

import {IAccessControlEnumerable} from "@openzeppelin/contracts/access/extensions/IAccessControlEnumerable.sol";

import {IStakingVault} from "./IStakingVault.sol";
import {IVaultHub} from "./IVaultHub.sol";

interface IDashboard is IAccessControlEnumerable {
    // ==================== Structs ====================
    struct RoleAssignment {
        address account;
        bytes32 role;
    }

    struct Report {
        uint104 totalValue;
        int152 inOutDelta;
        uint64 timestamp;
    }

    // ==================== Events ====================
    event UnguaranteedDeposits(address indexed stakingVault, uint256 deposits, uint256 totalAmount);
    event ERC20Recovered(address indexed to, address indexed token, uint256 amount);
    event ERC721Recovered(address indexed to, address indexed token, uint256 tokenId);
    event ConfirmExpirySet(address indexed sender, uint256 oldConfirmExpiry, uint256 newConfirmExpiry);
    event RoleMemberConfirmed(
        address indexed member, bytes32 indexed role, uint256 confirmTimestamp, uint256 expiryTimestamp, bytes data
    );
    event FeeRateSet(address indexed sender, uint256 oldFeeRate, uint256 newFeeRate);
    event FeeRecipientSet(address indexed sender, address oldFeeRecipient, address newFeeRecipient);
    event FeeDisbursed(address indexed sender, uint256 fee, address recipient);
    event SettledGrowthSet(int256 oldSettledGrowth, int256 newSettledGrowth);
    event CorrectionTimestampUpdated(uint256 timestamp);

    // ==================== Errors ====================
    error ExceedsWithdrawable(uint256 amount, uint256 withdrawableValue);
    error ExceedsMintingCapacity(uint256 requestedShares, uint256 remainingShares);
    error EthTransferFailed(address recipient, uint256 amount);
    error ConnectedToVaultHub();
    error TierChangeNotConfirmed();
    error DashboardNotAllowed();
    error FeeValueExceed100Percent();
    error IncreasedOverLimit();
    error InvalidatedAdjustmentVote(uint256 currentAdjustment, uint256 currentAtPropositionAdjustment);
    error SameAdjustment();
    error SameRecipient();
    error ReportStale();
    error AdjustmentNotReported();
    error AdjustmentNotSettled();
    error VaultQuarantined();
    error NonProxyCallsForbidden();
    error AlreadyInitialized();
    error ZeroArgument();
    error ZeroAddress();
    error ConfirmExpiryOutOfBounds();
    error SenderNotMember();
    error ZeroConfirmingRoles();
    error PDGPolicyAlreadyActive();
    error ForbiddenByPDGPolicy();
    error ForbiddenToConnectByNodeOperator();

    // ==================== Constants and Immutables ====================
    function STETH() external view returns (address);
    function WSTETH() external view returns (address);
    function ETH() external view returns (address);
    function FUND_ON_RECEIVE_FLAG_SLOT() external view returns (bytes32);
    function VAULT_HUB() external view returns (address);
    function LIDO_LOCATOR() external view returns (address);
    function NODE_OPERATOR_MANAGER_ROLE() external view returns (bytes32);
    function NODE_OPERATOR_FEE_EXEMPT_ROLE() external view returns (bytes32);
    function NODE_OPERATOR_UNGUARANTEED_DEPOSIT_ROLE() external view returns (bytes32);
    function NODE_OPERATOR_PROVE_UNKNOWN_VALIDATOR_ROLE() external view returns (bytes32);
    function VAULT_CONFIGURATION_ROLE() external view returns (bytes32);
    function COLLECT_VAULT_ERC20_ROLE() external view returns (bytes32);
    function DEFAULT_ADMIN_ROLE() external view returns (bytes32);
    function MIN_CONFIRM_EXPIRY() external view returns (uint256);
    function MAX_CONFIRM_EXPIRY() external view returns (uint256);

    // Role constants
    function FUND_ROLE() external view returns (bytes32);
    function WITHDRAW_ROLE() external view returns (bytes32);
    function MINT_ROLE() external view returns (bytes32);
    function BURN_ROLE() external view returns (bytes32);
    function REBALANCE_ROLE() external view returns (bytes32);
    function PAUSE_BEACON_CHAIN_DEPOSITS_ROLE() external view returns (bytes32);
    function RESUME_BEACON_CHAIN_DEPOSITS_ROLE() external view returns (bytes32);
    function REQUEST_VALIDATOR_EXIT_ROLE() external view returns (bytes32);
    function TRIGGER_VALIDATOR_WITHDRAWAL_ROLE() external view returns (bytes32);
    function VOLUNTARY_DISCONNECT_ROLE() external view returns (bytes32);
    function PDG_COMPENSATE_PREDEPOSIT_ROLE() external view returns (bytes32);
    function PDG_PROVE_VALIDATOR_ROLE() external view returns (bytes32);
    function UNGUARANTEED_BEACON_CHAIN_DEPOSIT_ROLE() external view returns (bytes32);
    function CHANGE_TIER_ROLE() external view returns (bytes32);

    // ==================== Initialization ====================
    function initialize(
        address _defaultAdmin,
        address _nodeOperatorManager,
        address _nodeOperatorFeeRecipient,
        uint256 _nodeOperatorFeeBP,
        uint256 _confirmExpiry
    ) external;

    function initialized() external view returns (bool);

    // ==================== View Functions ====================
    function stakingVault() external view returns (IStakingVault);
    function vaultConnection() external view returns (IVaultHub.VaultConnection memory);
    function liabilityShares() external view returns (uint256);
    function totalValue() external view returns (uint256);
    function locked() external view returns (uint256);
    function maxLockableValue() external view returns (uint256);
    function totalMintingCapacityShares() external view returns (uint256);
    function remainingMintingCapacityShares(uint256 _etherToFund) external view returns (uint256);
    function withdrawableValue() external view returns (uint256);
    function obligations() external view returns (uint256 sharesToBurn, uint256 feesToSettle);
    function healthShortfallShares() external view returns (uint256);

    // ==================== Node Operator Fee Functions ====================
    function feeRecipient() external view returns (address);
    function feeRate() external view returns (uint16);
    function settledGrowth() external view returns (int128);
    function latestCorrectionTimestamp() external view returns (uint64);
    function latestReport() external view returns (Report memory);
    function accruedFee() external view returns (uint256);
    function disburseFee() external;
    function disburseAbnormallyHighFee() external;
    function setFeeRate(uint256 _newFeeRate) external returns (bool);
    function correctSettledGrowth(int256 _newSettledGrowth, int256 _expectedSettledGrowth) external returns (bool);
    function addFeeExemption(uint256 _exemptedAmount) external;
    function setFeeRecipient(address _newFeeRecipient) external;

    // ==================== Confirmation Functions ====================
    function confirmingRoles() external pure returns (bytes32[] memory);
    function getConfirmExpiry() external view returns (uint256);
    function confirmation(bytes memory _callData, bytes32 _role) external view returns (uint256);
    function setConfirmExpiry(uint256 _newConfirmExpiry) external returns (bool);

    // ==================== Access Control Functions ====================
    function hasRole(bytes32 role, address account) external view returns (bool);
    function getRoleAdmin(bytes32 role) external view returns (bytes32);
    function grantRole(bytes32 role, address account) external;
    function revokeRole(bytes32 role, address account) external;
    function renounceRole(bytes32 role, address callerConfirmation) external;
    function grantRoles(RoleAssignment[] calldata _assignments) external;
    function revokeRoles(RoleAssignment[] calldata _assignments) external;
    function getRoleMember(bytes32 role, uint256 index) external view returns (address);
    function getRoleMemberCount(bytes32 role) external view returns (uint256);

    // ==================== Vault Management Functions ====================
    function transferVaultOwnership(address _newOwner) external;
    function voluntaryDisconnect() external;
    function abandonDashboard(address _newOwner) external;
    function reconnectToVaultHub() external;
    function connectToVaultHub() external payable;
    function connectAndAcceptTier(uint256 _tierId, uint256 _requestedShareLimit) external payable;
    function changeTier(uint256 _tierId, uint256 _requestedShareLimit) external returns (bool);
    function syncTier() external returns (bool);
    function updateShareLimit(uint256 _requestedShareLimit) external returns (bool);

    // ==================== Vault Operations ====================
    function fund() external payable;
    function withdraw(address _recipient, uint256 _ether) external;
    function mintShares(address _recipient, uint256 _amountOfShares) external payable;
    function mintStETH(address _recipient, uint256 _amountOfStETH) external payable;
    function mintWstETH(address _recipient, uint256 _amountOfWstETH) external payable;
    function burnShares(uint256 _amountOfShares) external;
    function burnStETH(uint256 _amountOfStETH) external;
    function burnWstETH(uint256 _amountOfWstETH) external;
    function rebalanceVaultWithShares(uint256 _shares) external;
    function rebalanceVaultWithEther(uint256 _ether) external payable;

    // ==================== Beacon Chain Operations ====================
    function pauseBeaconChainDeposits() external;
    function resumeBeaconChainDeposits() external;
    function requestValidatorExit(bytes calldata _pubkeys) external;
    function triggerValidatorWithdrawals(bytes calldata _pubkeys, uint64[] calldata _amounts, address _refundRecipient)
        external
        payable;
    function unguaranteedDepositToBeaconChain(IStakingVault.Deposit[] calldata _deposits)
        external
        returns (uint256 totalAmount);

    // ==================== PDG Operations ====================
    function compensateDisprovenPredepositFromPDG(bytes calldata _pubkey, address _recipient) external;

    // ==================== Asset Recovery ====================
    function recoverERC20(address _token, address _recipient, uint256 _amount) external;
    function collectERC20FromVault(address _token, address _recipient, uint256 _amount) external;

    // ==================== PDG Policy ====================
    enum PDGPolicy {
        STRICT,
        ALLOW_PROVE,
        ALLOW_DEPOSIT_AND_PROVE
    }

    function pdgPolicy() external view returns (PDGPolicy);
    function setPDGPolicy(PDGPolicy _pdgPolicy) external;

    // ==================== Receive Function ====================
    receive() external payable;
}
