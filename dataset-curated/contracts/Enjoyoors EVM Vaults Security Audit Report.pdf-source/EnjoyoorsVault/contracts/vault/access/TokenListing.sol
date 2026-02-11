// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.26;

import '@openzeppelin/contracts/access/AccessControl.sol';

import '../EnjoyoorsVaultBase.sol';
import '../../libraries/Asserts.sol';

/// @title Abstract contract for token whitelist management
abstract contract TokenListing is AccessControl, EnjoyoorsVaultBase {
  using Asserts for address;

  /// @notice Hash of role with token listing params rights
  bytes32 public constant TOKEN_LISTER_ROLE = keccak256('TOKEN_LISTER_ROLE');

  /// @notice Emitted in case of new token successful listing
  /// @param newToken Address of added token
  event NewTokenListed(address newToken);

  /// @notice Revert reason if attempt to list already listed token occurs
  error AlreadyWhitelisted();

  /**
   * @notice Requires `TOKEN_LISTER_ROLE` rights. Whitelists new token
   * @param token New token to whitelist
   */
  function listToken(address token) external onlyRole(TOKEN_LISTER_ROLE) {
    token.assertNotZeroAddress();

    if (isWhitelistedToken[token]) revert AlreadyWhitelisted();
    isWhitelistedToken[token] = true;
    emit NewTokenListed(token);
  }
}
