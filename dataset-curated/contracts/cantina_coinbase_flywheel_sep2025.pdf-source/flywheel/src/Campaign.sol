// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";

import {Flywheel} from "./Flywheel.sol";

/// @title Campaign
///
/// @notice Holds funds for a single campaign
///
/// @dev Deployed on demand by protocol via clones
contract Campaign {
    /// @notice ERC-7528 address for native token
    address public constant NATIVE_TOKEN = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    /// @notice Address that created this token store
    address public immutable flywheel;

    /// @notice Emitted when the contract URI is updated
    event ContractURIUpdated();

    /// @notice Call sender is not flywheel
    error OnlyFlywheel();

    /// @notice Constructor
    constructor() {
        flywheel = msg.sender;
    }

    /// @notice Allow receiving native token
    receive() external payable {}

    /// @notice Send tokens to a recipient, called by escrow during capture/refund
    ///
    /// @param token The token being received
    /// @param recipient Address to receive the tokens
    /// @param amount Amount of tokens to receive
    ///
    /// @return success True if the transfer was successful
    function sendTokens(address token, address recipient, uint256 amount) external returns (bool) {
        if (msg.sender != flywheel) revert OnlyFlywheel();
        if (token == NATIVE_TOKEN) {
            SafeTransferLib.safeTransferETH(recipient, amount);
        } else {
            SafeTransferLib.safeTransfer(token, recipient, amount);
        }
        return true;
    }

    /// @notice Updates the metadata for the contract
    function updateContractURI() external {
        if (msg.sender != flywheel) revert OnlyFlywheel();
        emit ContractURIUpdated();
    }

    /// @notice Returns the URI for the contract
    ///
    /// @return uri The URI for the contract
    function contractURI() external view returns (string memory uri) {
        return Flywheel(flywheel).campaignURI(address(this));
    }
}
