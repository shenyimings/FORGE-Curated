// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PermitUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import "./interfaces/IAssToken.sol";

contract AssToken is IAssToken, ERC20PermitUpgradeable, OwnableUpgradeable, UUPSUpgradeable {
  /* ============ State Variables ============ */
  address public minter;

  /* ============ Events ============ */
  event SetMinter(address indexed _address);

  /* ============ Constructor ============ */
  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    _disableInitializers();
  }

  /**
   * @dev initialize the contract
   * @param _name - AssToken name
   * @param _symbol - AssToken symbol
   * @param _owner - Address of the owner
   * @param _minter - Address of the minter
   */
  function initialize(
    string memory _name,
    string memory _symbol,
    address _owner,
    address _minter
  ) external override initializer {
    require(_owner != address(0), "Invalid owner address");
    require(_minter != address(0), "Invalid minter address");

    __Ownable_init(_owner);
    __ERC20_init(_name, _symbol);
    __ERC20Permit_init(_name);
    __UUPSUpgradeable_init();

    minter = _minter;
  }

  /* ============ Modifiers ============ */
  modifier onlyMinter() {
    require(msg.sender == minter, "AssToken: caller is not the minter");
    _;
  }

  /* ============ External Authorize Functions ============ */
  /**
   * @dev Mint new tokens, only minter can call this function
   * @param _account - Address of the account
   * @param _amount - Amount of tokens to mint
   */
  function mint(address _account, uint256 _amount) external override onlyMinter {
    _mint(_account, _amount);
  }

  /* ============ Admin Functions ============ */
  /**
   * @dev Set the minter
   * @param _address - Address of the minter
   */
  function setMinter(address _address) external override onlyOwner {
    require(_address != address(0), "Invalid minter address");
    require(_address != minter, "Minter is the same");
    minter = _address;
    emit SetMinter(_address);
  }

  /* ============ Internal Functions ============ */
  function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}
