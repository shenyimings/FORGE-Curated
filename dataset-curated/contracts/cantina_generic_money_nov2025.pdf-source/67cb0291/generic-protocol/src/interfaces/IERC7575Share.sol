// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.0;

import { IERC165 } from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title IERC7575 Share
 * @dev Interface for ERC-7575 share functionality.
 * The share token MUST return the constant value true if `0xf815c03d` is passed through the interfaceID argument.
 */
interface IERC7575Share is IERC20, IERC165 {
    /**
     * @notice Emitted when a vault is updated for a specific asset.
     * @param asset The address of the asset.
     * @param vault The address of the new vault.
     */
    event VaultUpdate(address indexed asset, address vault);

    /**
     * @notice Returns the address of the Vault for the given asset.
     * @param asset The address of the asset.
     * @return The address of the associated Vault.
     */
    function vault(address asset) external view returns (address);
}
