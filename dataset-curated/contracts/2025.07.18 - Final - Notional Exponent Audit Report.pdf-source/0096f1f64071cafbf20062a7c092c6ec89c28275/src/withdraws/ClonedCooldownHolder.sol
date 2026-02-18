// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.29;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @notice Used for withdraws where only one cooldown period can exist per address,
 * this contract will receive the staked token and initiate a cooldown
 */
abstract contract ClonedCoolDownHolder {
    using SafeERC20 for ERC20;

    /// @notice The manager contract that is responsible for managing the cooldown period.
    address immutable manager;

    constructor(address _manager) { manager = _manager; }

    modifier onlyManager() {
        require(msg.sender == manager);
        _;
    }

    /// @notice If anything ever goes wrong, allows the manager to recover lost tokens.
    function rescueTokens(ERC20 token, address receiver, uint256 amount) external onlyManager {
       token.safeTransfer(receiver, amount);
    }

    // External methods with authentication
    function startCooldown(uint256 cooldownBalance) external onlyManager { _startCooldown(cooldownBalance); }
    function stopCooldown() external onlyManager { _stopCooldown(); }
    function finalizeCooldown() external onlyManager returns (uint256 tokensWithdrawn, bool finalized) { return _finalizeCooldown(); }

    // Internal implementation methods
    function _startCooldown(uint256 cooldownBalance) internal virtual;
    function _stopCooldown() internal virtual;
    function _finalizeCooldown() internal virtual returns (uint256 tokensWithdrawn, bool finalized);
}
