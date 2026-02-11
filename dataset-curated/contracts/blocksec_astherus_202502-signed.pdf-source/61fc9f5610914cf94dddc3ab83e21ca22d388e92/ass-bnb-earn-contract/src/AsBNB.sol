// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";

import "./interfaces/IAsBNB.sol";

contract AsBNB is IAsBNB, ERC20, ERC20Permit, Ownable2Step {
  /* ============ State Variables ============ */
  address public minter;

  /* ============ Events ============ */
  event SetMinter(address indexed _address);

  /* ============ Constructor ============ */
  constructor(
    string memory _name,
    string memory _symbol,
    address _owner,
    address _minter
  ) ERC20(_name, _symbol) ERC20Permit(_name) Ownable(_owner) {
    require(_owner != address(0), "Invalid owner address");
    require(_minter != address(0), "Invalid minter address");

    minter = _minter;
  }

  /* ============ Modifiers ============ */
  modifier onlyMinter() {
    require(msg.sender == minter, "AsBNB: caller is not the minter");
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

  /**
   * @dev burn ass tokens, only minter can call this function
   * @param _account - Address of the account
   * @param _amount - Amount of tokens to burn
   */
  function burn(address _account, uint256 _amount) external override onlyMinter {
    _burn(_account, _amount);
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
}
