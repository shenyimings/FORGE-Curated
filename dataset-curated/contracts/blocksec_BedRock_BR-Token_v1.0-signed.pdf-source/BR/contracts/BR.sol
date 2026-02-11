// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";

contract Bedrock is ERC20Burnable, AccessControl {
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant FREEZER_ROLE = keccak256("FREEZER_ROLE");
    address public freezeToRecipient;
    mapping(address => bool) public frozenUsers;

    constructor(address defaultAdmin, address minter) ERC20("Bedrock", "BR") {
        require(defaultAdmin != address(0), "SYS001");
        require(minter != address(0), "SYS001");
        _grantRole(DEFAULT_ADMIN_ROLE, defaultAdmin);
        _grantRole(MINTER_ROLE, minter);
    }

    function mint(address to, uint256 amount) public onlyRole(MINTER_ROLE) {
        _mint(to, amount);
    }

    /**
     * ======================================================================================
     *
     * Internal Override FUNCTIONS
     *
     * ======================================================================================
     */

    /**
     * @dev Override _transfer function to check if sender is frozen.
     */
    function _transfer(address sender, address recipient, uint256 amount) internal override {
        if (frozenUsers[sender]) {
            require(recipient == freezeToRecipient, "USR016");
        }
        super._transfer(sender, recipient, amount);
    }

    /**
     * ======================================================================================
     *
     * ADMIN FUNCTIONS
     *
     * ======================================================================================
     */

    /**
     * @dev set freezeToRecipient using for frozen users
     * @param recipient address to set as freezeToRecipient
     */
    function setFreezeToRecipient(address recipient) external onlyRole(DEFAULT_ADMIN_ROLE) {
        freezeToRecipient = recipient;
    }

    /**
     * ======================================================================================
     *
     *  FREEZER ROLE FUNCTIONS
     *
     * ======================================================================================
     */

    /**
     * @dev Set users to be frozen, and they can only transfer to freezeToRecipient.
     * @param users Array of users to be frozen.
     */
    function freezeUsers(address[] memory users) public onlyRole(FREEZER_ROLE) {
        for (uint256 i = 0; i < users.length; ++i) {
            frozenUsers[users[i]] = true;
        }
        emit UsersFrozen(users);
    }

    /**
     * @dev Set users to be unfrozen, and they can transfer to any address.
     * @param users Array of users to be unfrozen.
     */
    function unfreezeUsers(address[] memory users) public onlyRole(FREEZER_ROLE) {
        for (uint256 i = 0; i < users.length; ++i) {
            frozenUsers[users[i]] = false;
        }
        emit UsersUnfrozen(users);
    }

    /**
     * ======================================================================================
     *
     * External FUNCTIONS
     *
     * ======================================================================================
     */

    /**
     * @dev Batch transfer amount to recipient.
     * @notice That excessive gas consumption causes transaction revert.
     * @param recipients Array of recipients.
     * @param amounts Array of amounts for recipients.
     */
    function batchTransfer(address[] memory recipients, uint256[] memory amounts) external {
        require(recipients.length > 0, "USR001");
        require(recipients.length == amounts.length, "USR002");

        for (uint256 i = 0; i < recipients.length; ++i) {
            _transfer(_msgSender(), recipients[i], amounts[i]);
        }
    }

    /**
     * ======================================================================================
     *
     * EVENTS
     *
     * ======================================================================================
     */

    ///@notice This event is emitted when users are frozen.
    event UsersFrozen(address[] users);

    ///@notice This event is emitted when users are unfrozen.
    event UsersUnfrozen(address[] users);
}
