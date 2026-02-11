// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {IAllowListEvents} from "../common/IEvents.sol";

/**
 * @title Allowed List Interface
 * @dev holds the signature of an allowed list
 * @author  @oscarsernarosero @mpetersoCode55 @cirsteve
 */

interface IAllowList is IAllowListEvents {
    /**
     * @dev Tells if an address is allowed
     * @param _address address of the yToken or deployer.
     * @return true if _address is allowed in a pool.
     */
    function isAllowed(address _address) external view returns (bool);

    /**
     * @dev Adds an address to the allowed list
     * @param _address address to be allowed
     */
    function addToAllowList(address _address) external;

    /**
     * @dev Removes an address from the list
     * @param _address address to remove from list
     */
    function removeFromAllowList(address _address) external;
}
