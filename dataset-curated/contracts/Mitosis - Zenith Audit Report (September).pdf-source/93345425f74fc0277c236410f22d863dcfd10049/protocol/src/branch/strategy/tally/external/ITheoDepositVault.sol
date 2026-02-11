// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface ITheoDepositVault {
  struct Withdrawal {
    // Maximum of 65535 rounds. Assuming 1 round is 7 days, maximum is 1256 years.
    uint16 round;
    // Number of shares withdrawn
    uint128 shares;
  }

  function withdrawals(address user) external view returns (Withdrawal memory);

  /**
   * @notice Returns the vault's total balance, including the amounts locked into a position
   * @return total balance of the vault, including the amounts locked in third party protocols
   */
  function totalBalance() external view returns (uint256);

  /**
   * @notice Returns the asset balance held on the vault for the account not
   *              accounting for current round deposits
   * @param account is the address to lookup balance for
   * @return the amount of `asset` custodied by the vault for the user
   */
  function accountVaultBalance(address account) external view returns (uint256);

  /**
   * @notice Getter for returning the account's share balance including unredeemed shares
   * @param account is the account to lookup share balance for
   * @return the share balance
   */
  function shares(address account) external view returns (uint256);

  /**
   * @notice Getter for returning the account's share balance split between account and vault holdings
   * @param account is the account to lookup share balance for
   * @return heldByAccount is the shares held by account
   * @return heldByVault is the shares held on the vault (unredeemedShares)
   */
  function shareBalances(address account) external view returns (uint256 heldByAccount, uint256 heldByVault);

  /**
   * @notice Returns the pricePerShare value of the vault token at the current round.
   */
  function pricePerShare() external view returns (uint256 pricePerShare);

  /**
   * @notice Returns the pricePerShare value of the vault token at the time of each round's closure.
   */
  function roundPricePerShare(uint256 round) external view returns (uint256 assetPerShare);

  /**
   * @notice Returns the token decimals
   */
  function decimals() external view returns (uint8);

  function totalSupply() external view returns (uint256);

  function cap() external view returns (uint256);

  function totalPending() external view returns (uint256);

  function round() external view returns (uint256);
}
