// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
import { AccessManaged } from "@openzeppelin/contracts/access/manager/AccessManaged.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title FeeCollectorCore
/// @author Cooper Labs
/// @custom:contact security@cooperlabs.xyz
/// @notice Abstract contract that handle the commun logic between SideChainFeeCollector and MainFeeDistributor
/// contracts.
abstract contract FeeCollectorCore is AccessManaged, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    //-------------------------------------------
    // Storage
    //-------------------------------------------

    /// @notice The fee token contract.
    IERC20 public immutable feeToken;

    //-------------------------------------------
    // Events
    //-------------------------------------------

    /// @notice Emitted when tokens are rescued.
    /// @param token The address of the token.
    /// @param to The address of the recipient.
    /// @param amount The amount of tokens rescued.
    event EmergencyRescued(address token, address to, uint256 amount);

    //-------------------------------------------
    // Errors
    //-------------------------------------------

    /// @notice Thrown when the amount to release is zero.
    error NothingToRelease();

    //-------------------------------------------
    // Constructor
    //-------------------------------------------

    ///@notice FeeCollectorCore constructor.
    ///@param _accessManager address of the AccessManager contract.
    ///@param _feeToken address of the fee token.
    constructor(address _accessManager, address _feeToken) AccessManaged(_accessManager) {
        feeToken = IERC20(_feeToken);
    }

    //-------------------------------------------
    // AccessManaged functions
    //-------------------------------------------

    /// @notice Allow to rescue tokens own by the contract.
    /// @param _token The address of the ERC20 token to rescue.
    /// @param _to The address of the receiver.
    /// @param _amount The amount of tokens to rescue.
    function emergencyRescue(address _token, address _to, uint256 _amount) external restricted whenPaused {
        emit EmergencyRescued(_token, _to, _amount);
        IERC20(_token).safeTransfer(_to, _amount);
    }

    /// @notice Allow AccessManager to pause the contract.
    /// @dev This function can only be called by an authorized() address.
    function pause() external restricted {
        _pause();
    }

    /// @notice Allow AccessManager to unpause the contract.
    /// @dev This function can only be called by an authorized() address.
    function unpause() external restricted {
        _unpause();
    }
}
