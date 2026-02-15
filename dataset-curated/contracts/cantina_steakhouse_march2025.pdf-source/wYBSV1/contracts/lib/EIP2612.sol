// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {PaxosBaseAbstract} from "./PaxosBaseAbstract.sol";
import {EIP712} from "./EIP712.sol";

/**
 * @title EIP2612 contract
 * @dev An abstract contract to provide EIP2612 functionality.
 * @custom:security-contact smart-contract-security@paxos.com
 */
abstract contract EIP2612 is PaxosBaseAbstract {
    // keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)")
    bytes32 public constant PERMIT_TYPEHASH =
        0x6e71edae12b1b97f4d1f60370fef10105fa2faae0126114a169c64845d6126c9;

    mapping(address => uint256) internal _nonces;
    // Storage gap: https://docs.openzeppelin.com/upgrades-plugins/1.x/writing-upgradeable#storage-gaps
    uint256[10] private __gap_EIP2612; // solhint-disable-line var-name-mixedcase

    error BlockedAccountOwner();
    error PermitExpired();

    /**
     * @notice Nonces for permit
     * @param owner Token owner's address
     * @return Next nonce
     */
    function nonces(address owner) external view returns (uint256) {
        return _nonces[owner];
    }

    /**
     * @notice update allowance with a signed permit
     * @param owner     Token owner's address (Authorizer)
     * @param spender   Spender's address
     * @param value     Amount of allowance
     * @param deadline  The time at which this expires (unix time)
     * @param v         v of the signature
     * @param r         r of the signature
     * @param s         s of the signature
     */
    function permit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external whenNotPaused {
        if (deadline < block.timestamp) revert PermitExpired();
        if (isAddrBlocked(owner)) revert BlockedAccountOwner();
        if (isAddrBlocked(spender)) revert BlockedAccountSpender();

        bytes memory data = abi.encode(
            PERMIT_TYPEHASH,
            owner,
            spender,
            value,
            _nonces[owner]++,
            deadline
        );
        if (EIP712.recover(DOMAIN_SEPARATOR(), v, r, s, data) != owner)
            revert InvalidSignature();

        _approve(owner, spender, value);
    }
}
