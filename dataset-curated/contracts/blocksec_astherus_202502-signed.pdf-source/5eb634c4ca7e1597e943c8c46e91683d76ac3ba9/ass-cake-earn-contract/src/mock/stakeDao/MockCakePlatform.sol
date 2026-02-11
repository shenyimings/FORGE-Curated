// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract MockCakePlatform {

  using SafeERC20 for IERC20;

  /// @notice Recipient per address.
  mapping(address => address) public recipient;

  IERC20 public rewardToken;

  constructor(address _rewardToken) {
    rewardToken = IERC20(_rewardToken);
  }

  /// @notice Claim all rewards for multiple bounties on behalf of a user.
  /// @param ids Array of bounty IDs to claim.
  /// @param _user Address to claim the rewards for.
  function claimAllFor(address _user, uint256[] calldata ids) external {
    address _recipient = recipient[_user];
    if (_recipient == address(0)) _recipient = _user;

    uint256 length = ids.length;
    for (uint256 i = 0; i < length;) {
      uint256 id = ids[i];
      _claim(_user, _recipient, id);
      unchecked {
        ++i;
      }
    }
  }

  /// @notice Set a recipient address for calling user.
  /// @param _recipient Address of the recipient.
  /// @dev Recipient are used when calling claimFor functions. Regular functions will use msg.sender as recipient,
  ///  or recipient parameter provided if called by msg.sender.
  function setRecipient(address _recipient) external {
    recipient[msg.sender] = _recipient;
  }

  ////////////////////////////////////////////////////////////////
  /// --- INTERNAL LOGIC
  ///////////////////////////////////////////////////////////////

  /// @notice Claim rewards for a given bounty.
  /// @param _user Address of the user.
  /// @param _recipient Address of the recipient.
  /// @param _bountyId ID of the bounty.
  /// @return amount of rewards claimed.
  function _claim(address _user, address _recipient, uint256 _bountyId) internal returns (uint256 amount) {
    amount = 10 ether;
    // Transfer reward to user.
    rewardToken.safeTransfer(_recipient, amount);
  }

}

