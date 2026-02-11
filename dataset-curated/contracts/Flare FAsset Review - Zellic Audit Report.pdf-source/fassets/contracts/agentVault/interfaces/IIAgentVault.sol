// SPDX-License-Identifier: MIT
pragma solidity >=0.7.6 <0.9;
pragma abicoder v2;

import {IAgentVault} from "../../userInterfaces/IAgentVault.sol";
import {IIAssetManager} from "../../assetManager/interfaces/IIAssetManager.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";


interface IIAgentVault is IAgentVault {
    /**
     * Used by asset manager when destroying agent.
     * Marks agent as destroyed so that funds can be withdrawn by the agent owner.
     * Note: Can only be called by the asset manager.
     */
    function destroy() external;

    // Used by asset manager for liquidation and failed redemption.
    // Is nonReentrant to prevent reentrancy in case the token has receive hooks.
    // onlyAssetManager
    function payout(IERC20 _token, address _recipient, uint256 _amount) external;

    // Returns the asset manager to which this vault belongs.
    function assetManager() external view returns (IIAssetManager);

    // Enables owner checks in the asset manager.
    function isOwner(address _address) external view returns (bool);
}
