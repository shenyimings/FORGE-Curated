// SPDX-License-Identifier: MIT

pragma solidity 0.8.25;

import "./AnvilVotes.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @notice This is an exact clone of OpenZeppelin's {ERC20Votes} contract with the following modifications:
 *   - getPastTotalSupply(...) is implemented and returns _maxSupply() since Anvil has a constant supply.
 *   - _getVotingUnits(...) is removed, as it is no longer required by the parent contract.
 *   - _maxSupply(...) is updated to a hard-coded value.
 *   - _transferVotingUnits(...) is declared as abstract in this file (it originally was in Votes.sol, but it is no longer necessary there.)
 *
 * @custom:security-contact security@af.xyz
 */
abstract contract AnvilERC20Votes is ERC20, AnvilVotes {
    /**
     * @dev Total supply cap has been exceeded, introducing a risk of votes overflowing.
     */
    error ERC20ExceededSafeSupply(uint256 increasedSupply, uint256 cap);

    /**
     * @dev Maximum token supply. Hardcoded because it cannot change.
     */
    function _maxSupply() internal view virtual returns (uint256) {
        // NB: This is updated to return the constant supply
        // return type(uint208).max;
        return 100_000_000_000 * 10 ** uint256(decimals());
    }

    /**
     * @dev Move voting power when tokens are transferred.
     *
     * Emits a {IVotes-DelegateVotesChanged} event.
     */
    function _update(address from, address to, uint256 value) internal virtual override {
        super._update(from, to, value);
        if (from == address(0)) {
            uint256 supply = totalSupply();
            uint256 cap = _maxSupply();
            if (supply > cap) {
                revert ERC20ExceededSafeSupply(supply, cap);
            }
        }
        _transferVotingUnits(from, to, value);
    }

    //    NB: This is no longer necessary, as vote delegation logic is in Anvil.sol.
    //    /**
    //     * @dev Returns the voting units of an `account`.
    //     *
    //     * WARNING: Overriding this function may compromise the internal vote accounting.
    //     * `ERC20Votes` assumes tokens map to voting units 1:1 and this is not easy to change.
    //     */
    //    function _getVotingUnits(address account) internal view virtual override returns (uint256) {
    //        return balanceOf(account);
    //    }

    /**
     * @dev Get number of checkpoints for `account`.
     */
    function numCheckpoints(address account) public view virtual returns (uint32) {
        return _numCheckpoints(account);
    }

    /**
     * @dev Get the `pos`-th checkpoint for `account`.
     */
    function checkpoints(address account, uint32 pos) public view virtual returns (Checkpoints.Checkpoint208 memory) {
        return _checkpoints(account, pos);
    }

    /*************
     * ADDITIONS *
     *************/

    // NB: this is referenced in this file and must be implemented in Anvil.sol, where delegation logic lives.
    /**
     * @dev Must transfer voting units as a result of the transfer of `value` tokens from `from` to `to`.
     */
    function _transferVotingUnits(address from, address to, uint256 value) internal virtual;

    /**
     * @notice Anvil has a constant supply post-construction, so this can be hard-coded to `_maxSupply()`.
     *
     * @dev There is no future check because, although it is typically invalid to pass in a future timepoint, since
     * Anvil has a constant supply, this can confidently return what the supply will be at that time.
     */
    function getPastTotalSupply(uint256) public view virtual returns (uint256) {
        return _maxSupply();
    }
}
