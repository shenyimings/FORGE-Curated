// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.19;

import "@openzeppelin-4.9.0/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin-4.9.0/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin-4.9.0/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "@openzeppelin-4.9.0/contracts/access/Ownable2Step.sol";
import "./interfaces/IlvlUSDDefinitions.sol";
import {SingleAdminAccessControl} from "./auth/v4/SingleAdminAccessControl.sol";

/**
 * @title lvlUSD
 * @notice lvlUSD contract
 */
contract lvlUSD is
    ERC20Burnable,
    ERC20Permit,
    IlvlUSDDefinitions,
    SingleAdminAccessControl
{
    /// @notice The role that is allowed to denylist and un-denylist addresses
    bytes32 private constant DENYLIST_MANAGER_ROLE =
        keccak256("DENYLIST_MANAGER_ROLE");

    mapping(address => bool) public denylisted;

    address public minter;

    constructor(
        address admin
    ) ERC20("Level USD", "lvlUSD") ERC20Permit("Level USD") {
        if (admin == address(0)) revert ZeroAddressException();
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(DENYLIST_MANAGER_ROLE, admin);
    }

    modifier notOwner(address account) {
        if (hasRole(DEFAULT_ADMIN_ROLE, account)) revert IsOwner();
        _;
    }

    function setMinter(
        address newMinter
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        emit MinterUpdated(newMinter, minter);
        minter = newMinter;
    }

    function mint(address to, uint256 amount) external {
        if (msg.sender != minter) revert OnlyMinter();
        _mint(to, amount);
    }

    /**
     * @dev Remove renounce role access from AccessControl, to prevent users from resigning from roles.
     */
    function renounceRole(bytes32, address) public virtual override {
        revert OperationNotAllowed();
    }

    /**
     * @dev Hook that is called before any transfer of tokens. This includes
     * minting and burning. Disables transfers from or to of addresses with the DENYLISTED_ROLE role.
     */

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256
    ) internal virtual override {
        if (denylisted[from] || denylisted[to] || denylisted[msg.sender]) {
            revert Denylisted();
        }
    }

    /**
     * @notice Allows the owner (DEFAULT_ADMIN_ROLE) and denylist managers to denylist addresses.
     * @param target The address to denylist.
     */
    function addToDenylist(
        address target
    ) external onlyRole(DENYLIST_MANAGER_ROLE) notOwner(target) {
        denylisted[target] = true;
    }

    /**
     * @notice Allows denylist managers to remove addresses from the denylist.
     * @param target The address to remove from the denylist.
     */
    function removeFromDenylist(
        address target
    ) external onlyRole(DENYLIST_MANAGER_ROLE) {
        denylisted[target] = false;
    }
}
