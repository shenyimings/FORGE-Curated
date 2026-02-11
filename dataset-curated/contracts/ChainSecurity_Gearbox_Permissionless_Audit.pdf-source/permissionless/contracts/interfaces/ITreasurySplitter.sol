// SPDX-License-Identifier: MIT
// Gearbox Protocol. Generalized leverage for DeFi protocols
// (c) Gearbox Foundation, 2024.
pragma solidity ^0.8.23;

import {IVersion} from "@gearbox-protocol/core-v3/contracts/interfaces/base/IVersion.sol";
import {Split, TwoAdminProposal} from "./Types.sol";

/// @title Treasury splitter
interface ITreasurySplitter is IVersion {
    // ------ //
    // ERRORS //
    // ------ //

    /// @notice Thrown when attempting to set a split with different-sized receiver and proportion arrays
    error SplitArraysDifferentLengthException();

    /// @notice Thrown when attempting to set a split that doesn't have proportions summing to 1
    error PropotionSumIncorrectException();

    /// @notice Thrown when attempting to distribute a token for which a split is not defined
    error UndefinedSplitException();

    /// @notice Thrown when a restricted function is called by non-multisig address
    error OnlySelfException();

    /// @notice Thrown when a restricted function is called not by admin or treasury proxy
    error OnlyAdminOrTreasuryProxyException();

    /// @notice Thrown when attempting to call a configure function with an incorrect selector
    error IncorrectConfigureSelectorException();

    /// @notice Thrown when attempting the add the splitter itself as split receiver
    error TreasurySplitterAsReceiverException();

    // ------ //
    // EVENTS //
    // ------ //

    /// @notice Emitted when a new default split is set
    event SetDefaultSplit(address[] receivers, uint16[] proportions);

    /// @notice Emitted when a new token-specific split is set
    event SetTokenSplit(address indexed token, address[] receivers, uint16[] proportions);

    /// @notice Emitted whan a token is withdrawn to another address
    event WithdrawToken(address indexed token, address indexed to, uint256 withdrawnAmount);

    /// @notice Emitted when tokens are distributed
    event DistributeToken(address indexed token, uint256 distributedAmount);

    /// @notice Emitted when setting a new token insurance amount
    event SetTokenInsuranceAmount(address indexed token, uint256 amount);

    // --------------- //
    // STATE VARIABLES //
    // --------------- //

    function admin() external view returns (address);

    function treasuryProxy() external view returns (address);

    function tokenSplits(address token) external view returns (Split memory);

    function defaultSplit() external view returns (Split memory);

    function tokenInsuranceAmount(address token) external view returns (uint256);

    function getProposal(bytes32 callDataHash) external view returns (TwoAdminProposal memory);

    function activeProposals() external view returns (TwoAdminProposal[] memory);

    // ------------- //
    // CONFIGURATION //
    // ------------- //

    function distribute(address token) external;

    function configure(bytes memory callData) external;

    function cancelConfigure(bytes memory callData) external;

    // ------------- //
    // SELF-CALLABLE //
    // ------------- //

    function setTokenInsuranceAmount(address token, uint256 amount) external;

    function setTokenSplit(address token, address[] memory receivers, uint16[] memory proportions, bool distribute)
        external;

    function setDefaultSplit(address[] memory receivers, uint16[] memory proportions) external;

    function withdrawToken(address token, address to, uint256 amount) external;
}
