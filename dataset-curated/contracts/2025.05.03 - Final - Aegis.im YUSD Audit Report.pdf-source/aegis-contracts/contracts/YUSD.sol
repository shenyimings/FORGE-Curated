// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import { IYUSD, IYUSDErrors } from "./interfaces/IYUSD.sol";

contract YUSD is Ownable2Step, ERC20Burnable, ERC20Permit, IYUSDErrors {
  address public minter;

  mapping(address => bool) public isBlackListed;

  event SetMinter(address indexed newMinter, address indexed oldMinter);
  event AddedBlackList(address _user);
  event RemovedBlackList(address _user);

  constructor(address admin) Ownable(admin) ERC20("YUSD", "YUSD") ERC20Permit("YUSD") {}

  modifier onlyMinter() {
    if (msg.sender != minter) {
      revert OnlyMinter();
    }
    _;
  }

  function getBlackListStatus(address _maker) external view returns (bool) {
    return isBlackListed[_maker];
  }

  function setMinter(address newMinter) external onlyOwner {
    emit SetMinter(newMinter, minter);
    minter = newMinter;
  }

  function addBlackList(address _user) public onlyOwner {
    isBlackListed[_user] = true;

    emit AddedBlackList(_user);
  }

  function removeBlackList(address _user) public onlyOwner {
    isBlackListed[_user] = false;

    emit RemovedBlackList(_user);
  }

  function mint(address account, uint256 value) external onlyMinter {
    _mint(account, value);
  }

  function _update(address from, address to, uint256 value) internal virtual override(ERC20) {
    if (isBlackListed[from]) {
      revert Blacklisted(from);
    }
    if (isBlackListed[to]) {
      revert Blacklisted(to);
    }
    super._update(from, to, value);
  }
}
