// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {ERC20BurnableUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20BurnableUpgradeable.sol";
import {ERC20PermitUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PermitUpgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";

/// @notice This contract uses OZ 4.x, which does not namespace storage.  Upgrades to this contract must be done carefully to avoid storage clashing.
contract FrxUsdImplementationMock is ERC20Upgradeable, ERC20BurnableUpgradeable, ERC20PermitUpgradeable, AccessControlUpgradeable {
    
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    constructor() {
        _disableInitializers();
    }

    function initialize(
        string memory _name,
        string memory _symbol,
        address _initialAdmin,
        uint256 _initialSupply
    ) external initializer {
        __ERC20_init(_name, _symbol);
        __ERC20Permit_init(_name);
        __AccessControl_init();
        _grantRole(DEFAULT_ADMIN_ROLE, _initialAdmin);
        _grantRole(MINTER_ROLE, _initialAdmin);

        _mint(_initialAdmin, _initialSupply);
    }

    event TokenMinterBurned(address indexed from, address indexed to, uint256 amount);
    event TokenMinterMinted(address indexed from, address indexed to, uint256 amount);

    function minter_burn_from(address b_address, uint256 b_amount) external onlyRole(MINTER_ROLE) {
        super.burnFrom(b_address, b_amount);
        emit TokenMinterBurned(b_address, msg.sender, b_amount);
    }

    function minter_mint(address m_address, uint256 m_amount) external onlyRole(MINTER_ROLE) {
        super._mint(m_address, m_amount);
        emit TokenMinterMinted(msg.sender, m_address, m_amount);
    }

    /// @dev extra function to manage supply on chain without the approval that super.burnFrom() requires.
    function burn(address b_address, uint256 b_amount) external onlyRole(MINTER_ROLE) {
        super._burn(b_address, b_amount);
    }
}