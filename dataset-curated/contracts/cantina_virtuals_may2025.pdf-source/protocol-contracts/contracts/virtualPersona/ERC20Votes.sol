// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// This contract extends ERC20VotesUpgradeable to add tracking of delegatee changes
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20VotesUpgradeable.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import "../libs/AddressCheckpoints.sol";

abstract contract ERC20Votes is ERC20VotesUpgradeable {
    using AddressCheckpoints for AddressCheckpoints.Trace;
    mapping(address => AddressCheckpoints.Trace) private _delegateeCheckpoints;

    function _delegate(address account, address delegatee) internal override {
        super._delegate(account, delegatee);
        _delegateeCheckpoints[account].push(clock(), delegatee);
    }

    function _getPastDelegates(
        address account,
        uint256 timepoint
    ) internal view virtual returns (address) {
        uint48 currentTimepoint = clock();
        if (timepoint >= currentTimepoint) {
            revert ERC5805FutureLookup(timepoint, currentTimepoint);
        }
        return
            _delegateeCheckpoints[account].upperLookupRecent(
                SafeCast.toUint48(timepoint)
            );
    }
}
