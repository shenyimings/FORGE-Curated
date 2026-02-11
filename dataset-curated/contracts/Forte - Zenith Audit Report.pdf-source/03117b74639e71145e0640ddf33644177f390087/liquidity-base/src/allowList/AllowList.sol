// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import "../common/IErrors.sol";
import {IAllowList} from "./IAllowList.sol";
import "../common/TBC.sol";

/**
 * @title Allowed List
 * @dev holds an allowed list
 * @author  @oscarsernarosero @mpetersoCode55 @cirsteve
 */

contract AllowList is Ownable2Step, IAllowList {
    mapping(address _address => bool allowed) allowList;

    constructor() Ownable(_msgSender()) {
        emit AllowListDeployed();
    }

    /**
     * @dev Tells if an address is allowed
     * @param _address address of the yToken or deployer.
     * @return true if _address is allowed in a pool.
     */
    function isAllowed(address _address) external view returns (bool) {
        return allowList[_address];
    }

    /**
     * @dev Adds an address to the allowed list
     * @param _address address to be allowed
     */
    function addToAllowList(address _address) external onlyOwner {
        allowList[_address] = true;
        emit AddressAllowed(_address, true);
    }

    /**
     * @dev Removes an address from the list
     * @param _address address to remove from list
     */
    function removeFromAllowList(address _address) external onlyOwner {
        allowList[_address] = false;
        emit AddressAllowed(_address, false);
    }
}
