// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {IERC20, SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {Constants} from "./Constants.sol";
import {Flywheel} from "./Flywheel.sol";

/// @title Campaign
///
/// @notice Holds funds for a single campaign
///
/// @dev Deployed on demand by protocol via clones
/// @dev Follows ERC-7572 convention for contract metadata
///
/// @author Coinbase (https://github.com/base/flywheel)
contract Campaign {
    /// @notice Flywheel contract address
    address public immutable FLYWHEEL;

    /// @notice Emitted when the contract URI is updated
    event ContractURIUpdated();

    /// @notice Call sender is not Flywheel
    error OnlyFlywheel();

    /// @notice Constructor
    constructor() {
        FLYWHEEL = msg.sender;
    }

    /// @notice Allow receiving native token
    receive() external payable {}

    /// @notice Send tokens to a recipient
    ///
    /// @dev Delegates all logic of when to send tokens to Flywheel
    ///
    /// @param token The token being received
    /// @param recipient Address to receive the tokens
    /// @param amount Amount of tokens to receive
    ///
    /// @return success True if the transfer was successful
    function sendTokens(address token, address recipient, uint256 amount) external returns (bool success) {
        if (msg.sender != FLYWHEEL) revert OnlyFlywheel();
        if (token == Constants.NATIVE_TOKEN) {
            (success,) = payable(recipient).call{value: amount}("");
        } else {
            success = SafeERC20.trySafeTransfer(IERC20(token), recipient, amount);
        }
    }

    /// @notice Updates the metadata for the contract
    function updateContractURI() external {
        if (msg.sender != FLYWHEEL) revert OnlyFlywheel();
        emit ContractURIUpdated();
    }

    /// @notice Returns the URI for the contract
    ///
    /// @return uri The URI for the contract
    function contractURI() external view returns (string memory uri) {
        return Flywheel(FLYWHEEL).campaignURI(address(this));
    }
}
