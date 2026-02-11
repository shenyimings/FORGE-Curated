// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20BurnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20CappedUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlEnumerableUpgradeable.sol";

import "./interfaces/IERC20Token.sol";

/**
* @title Asset Token Contract
* @notice Asset token contract, used to manage assets
* @dev inherit ERC20BurnableUpgradeable, ERC20CappedUpgradeable, AccessControlEnumerableUpgradeable
 */
contract ERC20Token is AccessControlEnumerableUpgradeable, ERC20BurnableUpgradeable, ERC20CappedUpgradeable, IERC20Token {
    //roles
    bytes32 public constant ADMIN_ROLE = keccak256(abi.encodePacked("ADMIN_ROLE"));
    bytes32 public constant MINTER_ROLE = keccak256(abi.encodePacked("MINTER_ROLE"));
    bytes32 public constant BURNER_ROLE = keccak256(abi.encodePacked("BURNER_ROLE"));
    bytes32 public constant TRANSFER_ROLE = keccak256(abi.encodePacked("TRANSFER_ROLE"));

    constructor() {
        _disableInitializers();
    }

    function initialize(string calldata name_, string calldata symbol_, uint256 cap_, address admin_) external initializer {
        __Context_init_unchained();
        __AccessControl_init_unchained();
        __ERC20_init_unchained(name_, symbol_);
        __AccessControlEnumerable_init_unchained();
        __ERC20Burnable_init_unchained();
        __ERC20Capped_init_unchained(cap_);

        _setRoleAdmin(ADMIN_ROLE, ADMIN_ROLE);
        _setRoleAdmin(MINTER_ROLE, ADMIN_ROLE);
        _setRoleAdmin(BURNER_ROLE, ADMIN_ROLE);
        _setRoleAdmin(TRANSFER_ROLE, ADMIN_ROLE);
        _grantRole(ADMIN_ROLE, admin_);
    }

    function hasRole(bytes32 role, address account) public view virtual override(AccessControlUpgradeable, IAccessControlUpgradeable) returns (bool) {
        return super.hasRole(role, account) || super.hasRole(getRoleAdmin(role), account);
    }

    /**
     * @dev See {ERC20-_mint}.
     */
    function _mint(address account, uint256 amount) internal override (ERC20Upgradeable, ERC20CappedUpgradeable) {
        super._mint(account, amount);
    }

    /**
     * @dev require MINTER_ROLE=keccak256(abi.encodePacked("MINTER_ROLE"))
     */
    function mint(address account, uint256 amount) external onlyRole(MINTER_ROLE) {
        _mint(account, amount);
    }

    /**
     * @dev require BURNER_ROLE=keccak256(abi.encodePacked("BURNER_ROLE"))
     */
    function burn(uint256 amount) public override onlyRole(BURNER_ROLE) {
        super.burn(amount);
    }

    /**
     * @dev require BURNER_ROLE=keccak256(abi.encodePacked("BURNER_ROLE"))
     */
    function burn(address account, uint256 amount) public override onlyRole(BURNER_ROLE) {
        _burn(account, amount);
    }

    /**
     * @dev require BURNER_ROLE=keccak256(abi.encodePacked("BURNER_ROLE"))
     */
    function burnFrom(address account, uint256 amount) public override onlyRole(BURNER_ROLE) {
        super.burnFrom(account, amount);
    }
}