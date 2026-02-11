// Copyright (c) 2025 Merge Layers Inc.
//
// This source code is licensed under the Business Source License 1.1
// (the "License"); you may not use this file except in compliance with the
// License. You may obtain a copy of the License at
//
//     https://github.com/malda-protocol/malda-lending/blob/main/LICENSE-BSL
//
// See the License for the specific language governing permissions and
// limitations under the License.

// SPDX-License-Identifier: BSL-1.1
pragma solidity =0.8.28;

/*
 _____ _____ __    ____  _____ 
|     |  _  |  |  |    \|  _  |
| | | |     |  |__|  |  |     |
|_|_|_|__|__|_____|____/|__|__|   
*/

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {IRoles} from "src/interfaces/IRoles.sol";
import {IBlacklister} from "src/interfaces/IBlacklister.sol";


contract Blacklister is OwnableUpgradeable, IBlacklister {
    // ----------- STORAGE -----------
    mapping(address => bool) public isBlacklisted;
    
    address[] private _blacklistedList;

    IRoles public rolesOperator;

    // ----------- ERRORS -----------
    error Blacklister_AlreadyBlacklisted();
    error Blacklister_NotBlacklisted();
    error Blacklister_NotAllowed();

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address payable _owner, address _roles)
        external
        initializer
    {
        __Ownable_init(_owner);
        rolesOperator = IRoles(_roles);
    }

    modifier onlyOwnerOrGuardian() {
        require(msg.sender == owner() || rolesOperator.isAllowedFor(msg.sender, rolesOperator.GUARDIAN_BLACKLIST()), Blacklister_NotAllowed());
        _;
    }

    // ----------- VIEW ------------
    function getBlacklistedAddresses() external view returns (address[] memory) {
        return _blacklistedList;
    }
    
    // ----------- OWNER ------------
    function blacklist(address user) external override onlyOwnerOrGuardian {
        if (isBlacklisted[user]) revert Blacklister_AlreadyBlacklisted();
        _addToBlacklist(user);
    }

    function unblacklist(address user) external override onlyOwnerOrGuardian {
        if (!isBlacklisted[user]) revert Blacklister_NotBlacklisted();
        isBlacklisted[user] = false;
        _removeFromBlacklistList(user);
        emit Unblacklisted(user);
    }

   
    // ----------- INTERNAL ------------
    function _addToBlacklist(address user) internal {
        isBlacklisted[user] = true;
        _blacklistedList.push(user);
        emit Blacklisted(user);
    }
    
    function _removeFromBlacklistList(address user) internal {
        uint256 len = _blacklistedList.length;
        for (uint256 i; i < len; ++i) {
            if (_blacklistedList[i] == user) {
                _blacklistedList[i] = _blacklistedList[len - 1];
                _blacklistedList.pop();
                break;
            }
        }
    }
}