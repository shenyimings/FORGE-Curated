// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {IProver} from "./IProver.sol";
import {Route, Intent, Reward} from "../types/Intent.sol";

/**
 * @title ILocalProver
 * @notice Interface for LocalProver with flash-fulfill capability
 * @dev Extends IProver with flash-fulfill functionality for same-chain intents
 */
interface ILocalProver is IProver {
    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error InvalidClaimant();
    error NativeTransferFailed();

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Emitted when an intent is flash-fulfilled
     * @param intentHash Hash of the fulfilled intent
     * @param claimant Address receiving the fulfillment reward
     * @param nativeFee Amount of native tokens paid to claimant (ERC20 tokens also transferred but not tracked here)
     */
    event FlashFulfilled(
        bytes32 indexed intentHash,
        bytes32 indexed claimant,
        uint256 nativeFee
    );

    /*//////////////////////////////////////////////////////////////
                            EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Atomically withdraws, fulfills an intent, and pays claimant the fulfillment reward
     * @dev Claimant receives all reward tokens and native (minus amounts consumed by route execution).
     *      Intent hash is computed from route and reward, no need to pass it separately.
     * @param route Route information for the intent
     * @param reward Reward details for the intent
     * @param claimant Address that receives the fulfillment reward (ERC20 tokens + native ETH)
     * @return results Results from the fulfill execution
     */
    function flashFulfill(
        Route calldata route,
        Reward calldata reward,
        bytes32 claimant
    ) external payable returns (bytes[] memory results);
}
