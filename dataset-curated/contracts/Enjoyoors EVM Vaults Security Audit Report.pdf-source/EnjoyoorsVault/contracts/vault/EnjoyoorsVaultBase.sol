// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.26;

import '../interfaces/IEnjoyoorsVault.sol';
import '../interfaces/IEnjoyoorsWithdrawalApprover.sol';
import '../libraries/Asserts.sol';

/// @title Abstract contract with common storages and base functionality of vaults used in Enjoyoors project
abstract contract EnjoyoorsVaultBase is IEnjoyoorsVault {
  using Asserts for address;

  /// @notice Revert reason if some action (e.g deposit) is performed with not yet listed token
  error NotWhitelisted();

  /**
   * @notice Modifier for `token` listing assertion
   * @param token Token to search in whitelist
   */
  modifier onlyWhitelistedToken(address token) {
    _onlyWhitelistedToken(token);
    _;
  }

  /// @notice Mapping with vault tokens total supplies
  mapping(address token => uint256) public totalSupply;
  /// @notice Mapping with vault tokens amount till max capitalization
  mapping(address token => uint256) public supplyTillLimit;
  /// @notice Mapping with user's token supply in vault
  mapping(address token => mapping(address user => uint256)) public userSupply;
  /// @notice Mapping with tokens, listed in this vault
  mapping(address token => bool) public isWhitelistedToken;
  /// @notice Mapping with tokens minimal allowed deposit amount
  mapping(address token => uint256) public minDeposit;
  /// @notice Contract for withdrawal verifications
  IEnjoyoorsWithdrawalApprover public withdrawalApprover;

  /**
   * @param _withdrawalApprover Address of contract used for verification of withdrawal requests in claiming process
   * @dev Reverts if given address is address(0)
   */
  constructor(address _withdrawalApprover) {
    _withdrawalApprover.assertNotZeroAddress();
    withdrawalApprover = IEnjoyoorsWithdrawalApprover(_withdrawalApprover);
  }

  /**
   * @notice Inner function of `onlyWhitelistedToken` modifier
   * @param token Token to search in whitelist
   */
  function _onlyWhitelistedToken(address token) private view {
    if (!isWhitelistedToken[token]) revert NotWhitelisted();
  }
}
