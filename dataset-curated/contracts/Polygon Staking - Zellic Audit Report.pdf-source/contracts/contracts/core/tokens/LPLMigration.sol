// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.22;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title LPL Migration
 * @dev Migrates LPL tokens to SDL
 */
contract LPLMigration {
    using SafeERC20 for IERC20;

    uint256 public constant MIGRATION_RATIO = 2;

    address public lplToken;
    address public sdlToken;

    event LPLMigrated(address indexed sender, uint256 amount);

    constructor(address _lplToken, address _sdlToken) {
        lplToken = _lplToken;
        sdlToken = _sdlToken;
    }

    /**
     * @dev swaps LPL tokens for SDL tokens
     * @param _sender address that is migrating
     * @param _value amount to migrate
     **/
    function onTokenTransfer(address _sender, uint256 _value, bytes memory) public {
        require(msg.sender == lplToken, "Sender must be LPL token");
        IERC20(sdlToken).safeTransfer(_sender, _value / MIGRATION_RATIO);
        emit LPLMigrated(_sender, _value);
    }
}
