// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {IERC5805} from "@openzeppelin/contracts/interfaces/IERC5805.sol";
import {Context} from "@openzeppelin/contracts/utils/Context.sol";
import {Nonces} from "@openzeppelin/contracts/utils/Nonces.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {Checkpoints} from "@openzeppelin/contracts/utils/structs/Checkpoints.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {Time} from "@openzeppelin/contracts/utils/types/Time.sol";

/**
 * @dev OpenZeppelin's Votes.sol file was not extensible for our needs, as Anvil will need to rework delegate
 * calculations to make it so that ANVL locked in the Claim contract on behalf of an address may still be delegated
 * by that address. This could have been repurposed if certain fields and functions were internal rather than private,
 * but it is understandable why they are not and this logic was encapsulated.
 *
 * Given the requirements above, this is an exact clone of OpenZeppelin's {Votes} contract with the following modifications:
 *   - _delegate(...) is abstract, as it  needs to account for claims
 *   - _moveDelegateVotes(...) is removed since that logic will be up to the implementor
 *   - _transferVotingUnits(...) is removed since it was only in this contract for access to _moveDelegateVotes(...)
 *   _ _totalCheckpoints is removed since it would not be updated outside of the constructor (and a constant was added to replace it).
 *   - _push(...), _add(...), and _subtract(...) are moved to Anvil.sol.
 *   - _delagatee and _delegateCheckpoints fields are internal now rather than private.
 *
 *  The original Votes.sol is intact below with modifications called out and original logic commented out where applicable.
 *
 * @custom:security-contact security@af.xyz
 */
abstract contract AnvilVotes is Context, EIP712, Nonces, IERC5805 {
    using Checkpoints for Checkpoints.Trace208;

    bytes32 private constant DELEGATION_TYPEHASH =
        keccak256("Delegation(address delegatee,uint256 nonce,uint256 expiry)");

    // NB: Changed to internal
    // mapping(address account => address) private _delegatee;
    mapping(address account => address) internal _delegatee;

    // NB: Changed to internal
    // mapping(address delegatee => Checkpoints.Trace208) private _delegateCheckpoints;
    mapping(address delegatee => Checkpoints.Trace208) internal _delegateCheckpoints;

    // NB: Removed because it is no longer needed.
    // Checkpoints.Trace208 private _totalCheckpoints;

    /**
     * @dev The clock was incorrectly modified.
     */
    error ERC6372InconsistentClock();

    /**
     * @dev Lookup to future votes is not available.
     */
    error ERC5805FutureLookup(uint256 timepoint, uint48 clock);

    /**
     * @dev Clock used for flagging checkpoints. Can be overridden to implement timestamp based
     * checkpoints (and voting), in which case {CLOCK_MODE} should be overridden as well to match.
     */
    function clock() public view virtual returns (uint48) {
        return Time.blockNumber();
    }

    /**
     * @dev Machine-readable description of the clock as specified in EIP-6372.
     */
    // solhint-disable-next-line func-name-mixedcase
    function CLOCK_MODE() public view virtual returns (string memory) {
        // Check that the clock was not modified
        if (clock() != Time.blockNumber()) {
            revert ERC6372InconsistentClock();
        }
        return "mode=blocknumber&from=default";
    }

    /**
     * @dev Returns the current amount of votes that `account` has.
     */
    function getVotes(address account) public view virtual returns (uint256) {
        return _delegateCheckpoints[account].latest();
    }

    /**
     * @dev Returns the amount of votes that `account` had at a specific moment in the past. If the `clock()` is
     * configured to use block numbers, this will return the value at the end of the corresponding block.
     *
     * Requirements:
     *
     * - `timepoint` must be in the past. If operating using block numbers, the block must be already mined.
     */
    function getPastVotes(address account, uint256 timepoint) public view virtual returns (uint256) {
        uint48 currentTimepoint = clock();
        if (timepoint >= currentTimepoint) {
            revert ERC5805FutureLookup(timepoint, currentTimepoint);
        }
        return _delegateCheckpoints[account].upperLookupRecent(SafeCast.toUint48(timepoint));
    }

    // NB: This is commented out because it is implemented by AnvilERC20Votes.
    //    /**
    //     * @dev Returns the total supply of votes available at a specific moment in the past. If the `clock()` is
    //     * configured to use block numbers, this will return the value at the end of the corresponding block.
    //     *
    //     * NOTE: This value is the sum of all available votes, which is not necessarily the sum of all delegated votes.
    //     * Votes that have not been delegated are still part of total supply, even though they would not participate in a
    //     * vote.
    //     *
    //     * Requirements:
    //     *
    //     * - `timepoint` must be in the past. If operating using block numbers, the block must be already mined.
    //     */
    //    function getPastTotalSupply(uint256 timepoint) public view virtual returns (uint256) {
    //        uint48 currentTimepoint = clock();
    //        if (timepoint >= currentTimepoint) {
    //            revert ERC5805FutureLookup(timepoint, currentTimepoint);
    //        }
    //        return _totalCheckpoints.upperLookupRecent(SafeCast.toUint48(timepoint));
    //    }

    // NB: This is commented out because it is no longer used.
    //    /**
    //     * @dev Returns the current total supply of votes.
    //     */
    //    function _getTotalSupply() internal view virtual returns (uint256) {
    //        return _totalCheckpoints.latest();
    //    }

    /**
     * @dev Returns the delegate that `account` has chosen.
     */
    function delegates(address account) public view virtual returns (address) {
        return _delegatee[account];
    }

    /**
     * @dev Delegates votes from the sender to `delegatee`.
     */
    function delegate(address delegatee) public virtual {
        address account = _msgSender();
        _delegate(account, delegatee);
    }

    /**
     * @dev Delegates votes from signer to `delegatee`.
     */
    function delegateBySig(
        address delegatee,
        uint256 nonce,
        uint256 expiry,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) public virtual {
        if (block.timestamp > expiry) {
            revert VotesExpiredSignature(expiry);
        }
        address signer = ECDSA.recover(
            _hashTypedDataV4(keccak256(abi.encode(DELEGATION_TYPEHASH, delegatee, nonce, expiry))),
            v,
            r,
            s
        );
        _useCheckedNonce(signer, nonce);
        _delegate(signer, delegatee);
    }

    //    NB: These functions have been removed in favor of implementing them in Anvil.sol.
    //    _delegate(...) is now abstract (see bottom of file), since functions within this file depend on it.
    //    /**
    //     * @dev Delegate all of `account`'s voting units to `delegatee`.
    //     *
    //     * Emits events {IVotes-DelegateChanged} and {IVotes-DelegateVotesChanged}.
    //     */
    //    function _delegate(address account, address delegatee) internal virtual {
    //        address oldDelegate = delegates(account);
    //        _delegatee[account] = delegatee;
    //
    //        emit DelegateChanged(account, oldDelegate, delegatee);
    //        _moveDelegateVotes(oldDelegate, delegatee, _getVotingUnits(account));
    //    }
    //
    //    /**
    //     * @dev Transfers, mints, or burns voting units. To register a mint, `from` should be zero. To register a burn, `to`
    //     * should be zero. Total supply of voting units will be adjusted with mints and burns.
    //     */
    //    function _transferVotingUnits(address from, address to, uint256 amount) internal virtual {
    //        if (from == address(0)) {
    //            _push(_totalCheckpoints, _add, SafeCast.toUint208(amount));
    //        }
    //        if (to == address(0)) {
    //            _push(_totalCheckpoints, _subtract, SafeCast.toUint208(amount));
    //        }
    //        _moveDelegateVotes(delegates(from), delegates(to), amount);
    //    }
    //
    //    /**
    //     * @dev Moves delegated votes from one delegate to another.
    //     */
    //    function _moveDelegateVotes(address from, address to, uint256 amount) private {
    //        if (from != to && amount > 0) {
    //            if (from != address(0)) {
    //                (uint256 oldValue, uint256 newValue) = _push(
    //                    _delegateCheckpoints[from],
    //                    _subtract,
    //                    SafeCast.toUint208(amount)
    //                );
    //                emit DelegateVotesChanged(from, oldValue, newValue);
    //            }
    //            if (to != address(0)) {
    //                (uint256 oldValue, uint256 newValue) = _push(
    //                    _delegateCheckpoints[to],
    //                    _add,
    //                    SafeCast.toUint208(amount)
    //                );
    //                emit DelegateVotesChanged(to, oldValue, newValue);
    //            }
    //        }
    //    }

    /**
     * @dev Get number of checkpoints for `account`.
     */
    function _numCheckpoints(address account) internal view virtual returns (uint32) {
        return SafeCast.toUint32(_delegateCheckpoints[account].length());
    }

    /**
     * @dev Get the `pos`-th checkpoint for `account`.
     */
    function _checkpoints(
        address account,
        uint32 pos
    ) internal view virtual returns (Checkpoints.Checkpoint208 memory) {
        return _delegateCheckpoints[account].at(pos);
    }

    //    NB: Moved, exactly as is, to Anvil.sol, as delegate update logic now lives there.
    //    function _push(
    //        Checkpoints.Trace208 storage store,
    //        function(uint208, uint208) view returns (uint208) op,
    //        uint208 delta
    //    ) private returns (uint208, uint208) {
    //        return store.push(clock(), op(store.latest(), delta));
    //    }
    //
    //    function _add(uint208 a, uint208 b) private pure returns (uint208) {
    //        return a + b;
    //    }
    //
    //    function _subtract(uint208 a, uint208 b) private pure returns (uint208) {
    //        return a - b;
    //    }

    //    NB: Removed, as voting logic is now in Anvil.sol so there are no dependencies on this function.
    //    /**
    //     * @dev Must return the voting units held by an account.
    //     */
    //    function _getVotingUnits(address) internal view virtual returns (uint256);

    /*************
     * ADDITIONS *
     *************/
    /**
     * @dev Delegate all of `account`'s voting units to `delegatee`.
     *
     * Emits events {IVotes-DelegateChanged} and {IVotes-DelegateVotesChanged}.
     */
    function _delegate(address account, address delegatee) internal virtual;
}
