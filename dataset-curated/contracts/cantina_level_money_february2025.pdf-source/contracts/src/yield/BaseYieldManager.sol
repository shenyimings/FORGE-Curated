// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.19;

import {SingleAdminAccessControl} from "../auth/v5/SingleAdminAccessControl.sol";
import "../interfaces/ILevelBaseYieldManager.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title Base Yield Manager
 */
abstract contract BaseYieldManager is
    ILevelBaseYieldManager,
    SingleAdminAccessControl
{
    using SafeERC20 for IERC20;

    bytes32 public YIELD_RECOVERER_ROLE = keccak256("YIELD_RECOVERER_ROLE");

    /* --------------- CONSTRUCTOR --------------- */

    constructor(address _admin) {
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
    }

    /* --------------- EXTERNAL --------------- */

    // approval function
    function approveSpender(
        address token,
        address spender,
        uint256 amount
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        IERC20(token).forceApprove(spender, amount);
    }
}
