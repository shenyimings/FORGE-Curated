// SPDX-License-Identifier: CC0-1.0
pragma solidity 0.8.28;

import "@openzeppelin/contracts/access/AccessControl.sol";

import {INeuDaoLockV1} from "../interfaces/ILockV1.sol";
import {INeuV3, INeuTokenV3} from "../interfaces/INeuV3.sol";

/**
 * @dev NeuDaoLock locks Ether donated from Neulock's sponsors until the
 * operator (currently managed by Studio V) sets the address of a permanent DAO
 * contract and the holders of at least 7 governance tokens agree to unlock the
 * funds by calling unlock(tokenId), which registers their token as a "key".
 * 
 * The operator can set the DAO address and, after that, the holders of
 * governance tokens can vote for unlocking the funds. If the operator changes
 * the DAO address, the votes are reset.
 * 
 * Given that there are at least 7 key tokens, anyone can call withdraw() to
 * send the locked funds to the DAO address.
 */
contract NeuDaoLockV1 is AccessControl, INeuDaoLockV1 {
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    uint256 public constant REQUIRED_KEY_TOKENS = 7;
    INeuTokenV3 immutable private _neuContract;

    address public neuDaoAddress;
    uint256[] public keyTokenIds;

    constructor(
        address defaultAdmin,
        address operator,
        address neuContractAddress
    ) {
        _grantRole(DEFAULT_ADMIN_ROLE, defaultAdmin);
        _grantRole(OPERATOR_ROLE, operator);

        _neuContract = INeuTokenV3(neuContractAddress);
    }

    function setNeuDaoAddress(address newNeoDaoAddress) external onlyRole(OPERATOR_ROLE) {
        delete keyTokenIds;
        // slither-disable-next-line missing-zero-check (we may want to set it again to 0x0, to prevent users from unlocking before we decide on a new DAO)
        neuDaoAddress = newNeoDaoAddress;

        emit AddressChange(newNeoDaoAddress);
    }

    function unlock(uint256 neuTokenId) external {
        require(_neuContract.ownerOf(neuTokenId) == msg.sender, "Caller does not own NEU");
        require(_neuContract.isGovernanceToken(neuTokenId), "Provided token is not governance");
        require(neuDaoAddress != address(0), "NEU DAO address not set");

        uint256 keyTokenIdsLength = keyTokenIds.length;

        for (uint256 i = 0; i < keyTokenIdsLength; i++) {
            require(keyTokenIds[i] != neuTokenId, "Token already used as key");
        }

        keyTokenIds.push(neuTokenId);

        emit Unlock(neuTokenId);
    }

    function cancelUnlock(uint256 neuTokenId) external {
        require(_neuContract.ownerOf(neuTokenId) == msg.sender, "Caller does not own NEU");

        uint256 keyTokenIdsLength = keyTokenIds.length;

        for (uint256 i = 0; i < keyTokenIdsLength; i++) {
            if (keyTokenIds[i] == neuTokenId) {
                keyTokenIds[i] = keyTokenIds[keyTokenIdsLength - 1];
                // slither-disable-next-line costly-loop (we return after the costly call)
                keyTokenIds.pop();

                emit UnlockCancel(neuTokenId);
                return;
            }
        }
        revert("NEU not found");
    }

    function withdraw() external {
        require(neuDaoAddress != address(0), "NEU DAO address not set");
        require(keyTokenIds.length >= REQUIRED_KEY_TOKENS, "Not enough key tokens");

        uint256 balance = address(this).balance;

        emit Withdraw(balance);

        // slither-disable-start low-level-calls (calling like this is the best practice for sending Ether)
        // slither-disable-next-line arbitrary-send-eth (neuDaoAddress is only set by the operator and approved by key holders who have called unlock())
        (bool sent, ) = address(neuDaoAddress).call{value: balance}("");
        require(sent, "Failed to send Ether");
        // slither-disable-end low-level-calls
    }

    receive() external payable {}
}