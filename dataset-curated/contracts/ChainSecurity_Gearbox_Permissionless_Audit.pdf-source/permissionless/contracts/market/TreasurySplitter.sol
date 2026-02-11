// SPDX-License-Identifier: BUSL-1.1
// Gearbox Protocol. Generalized leverage for DeFi protocols
// (c) Gearbox Foundation, 2024.
pragma solidity ^0.8.23;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import {PERCENTAGE_FACTOR} from "@gearbox-protocol/core-v3/contracts/libraries/Constants.sol";

import {ITreasurySplitter} from "../interfaces/ITreasurySplitter.sol";
import {IAddressProvider} from "../interfaces/IAddressProvider.sol";
import {Split, TwoAdminProposal} from "../interfaces/Types.sol";

import {
    AP_TREASURY, AP_TREASURY_PROXY, AP_TREASURY_SPLITTER, NO_VERSION_CONTROL
} from "../libraries/ContractLiterals.sol";

contract TreasurySplitter is ITreasurySplitter {
    using EnumerableSet for EnumerableSet.Bytes32Set;
    using SafeERC20 for IERC20;

    /// @notice Contract version
    uint256 public constant override version = 3_10;

    /// @notice Contract type
    bytes32 public constant override contractType = AP_TREASURY_SPLITTER;

    /// @notice Address of the market admin
    address public immutable override admin;

    /// @notice Address of the Treasury proxy
    address public immutable override treasuryProxy;

    /// @dev Default split for this splitter. Used when no specific split is set for the distributed token.
    Split internal _defaultSplit;

    /// @dev Mapping from token address to the associated split. Used to set specific splits for certain tokens.
    mapping(address token => Split) internal _tokenSplits;

    /// @notice Mapping from token address to the minimal amount kept on the splitter for insurance, before distribution starts
    mapping(address token => uint256) public override tokenInsuranceAmount;

    /// @dev Mapping from proposal calldata hash to whether either of the admins confirmed it
    mapping(bytes32 callDataHash => TwoAdminProposal) internal _proposals;

    /// @dev Set of all active proposals
    EnumerableSet.Bytes32Set internal _activeProposals;

    modifier onlySelf() {
        if (msg.sender != address(this)) revert OnlySelfException();
        _;
    }

    modifier onlyTreasuryProxyOrAdmin() {
        if (msg.sender != admin && msg.sender != treasuryProxy) revert OnlyAdminOrTreasuryProxyException();
        _;
    }

    constructor(address addressProvider_, address admin_, address adminFeeTreasury_) {
        admin = admin_;
        address treasury = IAddressProvider(addressProvider_).getAddressOrRevert(AP_TREASURY, NO_VERSION_CONTROL);
        treasuryProxy = IAddressProvider(addressProvider_).getAddressOrRevert(AP_TREASURY_PROXY, NO_VERSION_CONTROL);

        address[] memory receivers = new address[](2);

        receivers[0] = adminFeeTreasury_;
        receivers[1] = treasury;

        uint16[] memory proportions = new uint16[](2);
        proportions[0] = PERCENTAGE_FACTOR / 2;
        proportions[1] = PERCENTAGE_FACTOR / 2;

        _setSplit(_defaultSplit, receivers, proportions);

        emit SetDefaultSplit(receivers, proportions);
    }

    /// @notice Returns a Split struct for a particular token
    function tokenSplits(address token) external view override returns (Split memory split) {
        return _tokenSplits[token];
    }

    /// @notice Returns the default Split struct
    function defaultSplit() external view override returns (Split memory) {
        return _defaultSplit;
    }

    /// @notice Returns proposal info by hash of its call data
    function getProposal(bytes32 callDataHash) external view override returns (TwoAdminProposal memory) {
        return _proposals[callDataHash];
    }

    /// @notice Returns active proposals
    function activeProposals() external view override returns (TwoAdminProposal[] memory proposals) {
        bytes32[] memory _activeHashes = _activeProposals.values();

        uint256 len = _activeHashes.length;

        proposals = new TwoAdminProposal[](len);

        for (uint256 i = 0; i < len; ++i) {
            proposals[i] = _proposals[_activeHashes[i]];
        }
    }

    /// @notice Distributes any new amount sent to the contract according to either the token-specific or default split.
    /// @param token Token to distribute
    function distribute(address token) external override onlyTreasuryProxyOrAdmin {
        _distribute(token);
    }

    /// @dev Internal function for `distribute`.
    function _distribute(address token) internal {
        Split memory split = _tokenSplits[token].initialized ? _tokenSplits[token] : _defaultSplit;

        uint256 len = split.receivers.length;

        uint256 balance = IERC20(token).balanceOf(address(this));

        uint256 insuranceAmount = tokenInsuranceAmount[token];

        if (balance <= insuranceAmount) return;

        uint256 balanceDiff = balance - insuranceAmount;

        for (uint256 i = 0; i < len; ++i) {
            address receiver = split.receivers[i];
            uint16 proportion = split.proportions[i];

            if (receiver != address(this)) {
                IERC20(token).safeTransfer(receiver, proportion * balanceDiff / PERCENTAGE_FACTOR);
            }
        }

        emit DistributeToken(token, balanceDiff);
    }

    /// @notice Configures parameters for this splitter. Calldata must have a selector for one of the configuration functions.
    function configure(bytes memory callData) external override onlyTreasuryProxyOrAdmin {
        bytes4 selector = bytes4(callData);

        if (
            selector != ITreasurySplitter.setTokenInsuranceAmount.selector
                && selector != ITreasurySplitter.setDefaultSplit.selector
                && selector != ITreasurySplitter.setTokenSplit.selector
                && selector != ITreasurySplitter.withdrawToken.selector
        ) {
            revert IncorrectConfigureSelectorException();
        }

        bytes32 callDataHash = keccak256(callData);

        TwoAdminProposal storage _proposal = _proposals[callDataHash];

        if (!_activeProposals.contains(callDataHash)) {
            _activeProposals.add(callDataHash);
            _proposal.callData = callData;
        }

        if (msg.sender == admin) {
            _proposal.confirmedByAdmin = true;
        } else {
            _proposal.confirmedByTreasuryProxy = true;
        }

        if (_proposal.confirmedByAdmin && _proposal.confirmedByTreasuryProxy) {
            Address.functionCall(address(this), callData);
            _proposal.confirmedByAdmin = false;
            _proposal.confirmedByTreasuryProxy = false;
            _activeProposals.remove(callDataHash);
        }
    }

    /// @notice Cancels an active proposal
    function cancelConfigure(bytes memory callData) external override onlyTreasuryProxyOrAdmin {
        bytes32 callDataHash = keccak256(callData);

        TwoAdminProposal storage _proposal = _proposals[callDataHash];

        _proposal.confirmedByAdmin = false;
        _proposal.confirmedByTreasuryProxy = false;
        _activeProposals.remove(callDataHash);
    }

    /// @notice Sets the insurance amount for a token
    function setTokenInsuranceAmount(address token, uint256 amount) external override onlySelf {
        tokenInsuranceAmount[token] = amount;

        emit SetTokenInsuranceAmount(token, amount);
    }

    /// @notice Sets a split for a specific token
    function setTokenSplit(
        address token,
        address[] memory receivers,
        uint16[] memory proportions,
        bool distributeBefore
    ) external override onlySelf {
        if (distributeBefore) {
            _distribute(token);
        }

        _setSplit(_tokenSplits[token], receivers, proportions);

        emit SetTokenSplit(token, receivers, proportions);
    }

    /// @notice Sets a default split used for tokens that don't have a specific split
    /// @dev All tokens should be distributed manually before calling this, so that
    ///      the new default distribution does not apply to undistributed tokens
    function setDefaultSplit(address[] memory receivers, uint16[] memory proportions) external override onlySelf {
        _setSplit(_defaultSplit, receivers, proportions);

        emit SetDefaultSplit(receivers, proportions);
    }

    /// @dev Internal logic for `setTokenSplit` and `setDefaultSplit`
    function _setSplit(Split storage _split, address[] memory receivers, uint16[] memory proportions) internal {
        uint256 len = proportions.length;

        if (receivers.length != len) revert SplitArraysDifferentLengthException();

        uint256 propSum = 0;

        for (uint256 i = 0; i < len; ++i) {
            if (receivers[i] == address(this)) revert TreasurySplitterAsReceiverException();

            propSum += proportions[i];
        }

        if (propSum != PERCENTAGE_FACTOR) revert PropotionSumIncorrectException();

        _split.initialized = true;
        _split.receivers = receivers;
        _split.proportions = proportions;
    }

    /// @notice Withdraws an amount of a token to another address
    function withdrawToken(address token, address to, uint256 amount) external override onlySelf {
        IERC20(token).safeTransfer(to, amount);

        emit WithdrawToken(token, to, amount);
    }
}
