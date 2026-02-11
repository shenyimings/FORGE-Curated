// SPDX-License-Identifier: CC0-1.0
pragma solidity 0.8.28;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import {INeuDaoLockV1} from "../interfaces/ILockV1.sol";
import {INeuV3, INeuTokenV3} from "../interfaces/INeuV3.sol";

/**
 * @title NeuDaoLockV2
 * @author Lucas Neves (lneves.eth) for Studio V
 * @notice Locks Ether donated from Neulock's sponsors until DAO governance unlocks funds.
 * @dev Upgradeable lock contract for Neulock. Operator sets DAO address; holders of at least 7 governance tokens must agree to unlock funds. Integrates with NeuTokenV3 for governance logic.
 * @custom:security-contact security@studiov.tech
 */
contract NeuDaoLockV2 is AccessControl, INeuDaoLockV1 {
    using EnumerableSet for EnumerableSet.UintSet;

    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    uint256 public constant REQUIRED_KEY_TOKENS = 7;
    INeuTokenV3 immutable private _neuContract;

    address public neuDaoAddress;
    
    // slither-disable-next-line uninitialized-state-variables (see https://github.com/crytic/slither/issues/456)
    mapping(uint256 => EnumerableSet.UintSet) private _keyTokenIds;
    uint256 private _keyTokenIdsIndex;

    /**
     * @notice Deploys the contract and sets up roles and the NEU contract address.
     * @dev Grants DEFAULT_ADMIN_ROLE and OPERATOR_ROLE. Stores NeuTokenV3 contract address.
     * @param defaultAdmin The address to be granted DEFAULT_ADMIN_ROLE.
     * @param operator The address to be granted OPERATOR_ROLE.
     * @param neuContractAddress The address of the NeuTokenV3 contract.
     */
    constructor(
        address defaultAdmin,
        address operator,
        address neuContractAddress
    ) {
        _grantRole(DEFAULT_ADMIN_ROLE, defaultAdmin);
        _grantRole(OPERATOR_ROLE, operator);

        _neuContract = INeuTokenV3(neuContractAddress);
    }

    /**
     * @notice Returns the tokenId of a key used to unlock the DAO at a given index.
     * @dev Indexes into the current set of key tokens.
     * @param index The index in the key token set.
     * @return The NEU governance tokenId used as a key.
     */
    function keyTokenIds(uint256 index) external view returns (uint256) {
        return _getCurrentKeysSet().at(index);
    }

    /**
     * @notice Sets the address of the permanent DAO contract.
     * @dev Only callable by OPERATOR_ROLE. Resets all current unlock votes (keys) when called.
     * @param newNeoDaoAddress The address of the new DAO contract.
     *
     * Emits {AddressChange} event.
     */
    function setNeuDaoAddress(address newNeoDaoAddress) external onlyRole(OPERATOR_ROLE) {
        _clearKeysSet();

        // slither-disable-next-line missing-zero-check (we may want to set it again to 0x0, to prevent users from unlocking before we decide on a new DAO)
        neuDaoAddress = newNeoDaoAddress;

        emit AddressChange(newNeoDaoAddress);
    }

    /**
     * @notice Registers a NEU governance token as a key to unlock the DAO funds.
     * @dev Caller must own the NEU token and it must be a governance token. DAO address must be set.
     * @param neuTokenId The NEU governance tokenId to register as a key.
     *
     * Emits {Unlock} event.
     *
     * Requirements:
     * - Caller must own the NEU token.
     * - Token must be a governance token.
     * - DAO address must be set.
     * - Token must not already be used as a key.
     */
    function unlock(uint256 neuTokenId) external {
        require(_neuContract.ownerOf(neuTokenId) == msg.sender, "Caller does not own NEU");
        require(_neuContract.isGovernanceToken(neuTokenId), "Provided token is not governance");
        require(neuDaoAddress != address(0), "NEU DAO address not set");

        EnumerableSet.UintSet storage keysSet = _getCurrentKeysSet();

        require(keysSet.add(neuTokenId), "Token already used as key");

        emit Unlock(neuTokenId);
    }

    /**
     * @notice Cancels a previously registered NEU governance token key.
     * @dev Caller must own the NEU token. Removes the key from the current set.
     * @param neuTokenId The NEU governance tokenId to remove as a key.
     *
     * Emits {UnlockCancel} event.
     *
     * Requirements:
     * - Caller must own the NEU token.
     * - Token must be currently registered as a key.
     */
    function cancelUnlock(uint256 neuTokenId) external {
        require(_neuContract.ownerOf(neuTokenId) == msg.sender, "Caller does not own NEU");

        EnumerableSet.UintSet storage keysSet = _getCurrentKeysSet();

        require(keysSet.remove(neuTokenId), "NEU not found");

        emit UnlockCancel(neuTokenId);
    }

    /**
     * @notice Withdraws all locked Ether to the DAO address if enough key tokens are present.
     * @dev Anyone can call this if at least 7 governance tokens have unlocked. Sends Ether to DAO address and emits Withdraw event.
     *
     * Emits {Withdraw} event.
     *
     * Requirements:
     * - At least 7 key tokens must have unlocked.
     * - DAO address must be set.
     */
    function withdraw() external {
        require(_getCurrentKeysSet().length() >= REQUIRED_KEY_TOKENS, "Not enough key tokens");

        uint256 balance = address(this).balance;

        emit Withdraw(balance);

        // slither-disable-start low-level-calls (calling like this is the best practice for sending Ether)
        // slither-disable-next-line arbitrary-send-eth (neuDaoAddress is only set by the operator and approved by key holders who have called unlock())
        (bool sent, ) = address(neuDaoAddress).call{value: balance}("");
        require(sent, "Failed to send Ether");
        // slither-disable-end low-level-calls
    }

    /**
     * @notice Accepts Ether donations to be locked in the contract.
     * @dev Ether sent to this contract is locked until unlocked and withdrawn to the DAO.
     */
    receive() external payable {}

    function _getCurrentKeysSet() internal view returns (EnumerableSet.UintSet storage) {
        return _keyTokenIds[_keyTokenIdsIndex];
    }

    function _clearKeysSet() internal {
        _keyTokenIdsIndex += 1;
    }
}