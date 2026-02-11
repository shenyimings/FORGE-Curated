// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.10;

/**
  * @title Capyfi Whitelist Interface
  */
abstract contract WhitelistAccess {
    /// @notice Indicator that this is a WhitelistAccess contract (for inspection)
    bool public constant isWhitelistAccess = true;

    /**
      * @notice function to check if an account is whitelisted
      * @param account The address to check
      * @return Boolean indicating if the address is whitelisted
      */
    function isWhitelisted(address account) external view virtual returns (bool);

    /**
      * @notice function to check if the whitelist is active
      * @return Boolean indicating if the whitelist is active and should be enforced
      */
    function isActive() external view virtual returns (bool);
}