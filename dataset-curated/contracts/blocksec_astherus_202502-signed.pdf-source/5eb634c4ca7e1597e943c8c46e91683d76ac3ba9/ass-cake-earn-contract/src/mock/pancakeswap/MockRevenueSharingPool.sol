// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";


contract MockRevenueSharingPool {
  using SafeERC20 for IERC20;

  IERC20 public rewardToken;

  /// @dev User can set recipient address for claim
  mapping(address => address) public recipient;

  /// @notice constructor
  constructor(address _rewardToken) {
    rewardToken = IERC20(_rewardToken);
  }

  /// @notice Get claim recipient address
  /// @param _user The address to claim rewards for
  function getRecipient(address _user) public view returns (address _recipient) {
    _recipient = _user;
    address userRecipient = recipient[_recipient];
    if (userRecipient != address(0)) {
      _recipient = userRecipient;
    }
  }

  /// @notice Claim rewardToken for "_user", without cake pool proxy
  /// @param _user The address to claim rewards for
  function claimForUser(address _user) external returns (uint256) {
    address _recipient = getRecipient(_user);
    uint256 _amount = 10 ether;
    rewardToken.safeTransfer(_recipient, _amount);
    return _amount;
  }
}
