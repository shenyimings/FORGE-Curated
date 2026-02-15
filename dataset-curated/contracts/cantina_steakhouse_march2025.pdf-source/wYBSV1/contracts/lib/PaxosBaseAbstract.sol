// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";

/**
 * @dev PaxosBaseAbstract
 * An abstract contract for Paxos tokens with additional internal functions.
 * @custom:security-contact smart-contract-security@paxos.com
 */
abstract contract PaxosBaseAbstract is PausableUpgradeable {
    function _approve(
        address owner,
        address spender,
        uint256 amount
    ) internal virtual;

    function _transfer(
        address _from,
        address _to,
        uint256 _value
    ) internal virtual;

    function isAddrBlocked(address _addr) public view virtual returns (bool);
    function DOMAIN_SEPARATOR() public view virtual returns (bytes32);

    error ArgumentLengthMismatch();
    error BlockedAccountSpender();
    error BlockedAccountSender();
    error BlockedAccountReceiver();
    error AccountNotBlocked();
    error InvalidSignature();
}
