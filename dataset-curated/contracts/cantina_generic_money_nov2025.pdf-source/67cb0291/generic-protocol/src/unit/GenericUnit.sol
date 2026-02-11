// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC165 } from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

import { ERC20Mintable } from "./ERC20Mintable.sol";
import { IGenericShare, IERC7575Share } from "../interfaces/IGenericShare.sol";
import { IController } from "../interfaces/IController.sol";

/**
 * @title GenericUnit
 * @notice A mintable ERC20 token that represents stable unit within the Generic Protocol.
 * @dev This contract extends ERC20Mintable to provide a mintable ERC20 token that adheres to the
 * IERC7575Share interface. It includes functionality to query associated vaults for specific assets.
 * The controller address receives mint/burn privileges upon deployment.
 */
contract GenericUnit is IGenericShare, ERC20Mintable {
    /**
     * @notice Initializes the GenericUnit token with metadata and sets the owner.
     * @dev The owner address gets mint/burn privileges.
     * @param controller Address to be set as the owner
     * @param name ERC20 token name
     * @param symbol ERC20 token symbol
     */
    constructor(
        address controller,
        string memory name,
        string memory symbol
    )
        ERC20Mintable(controller, name, symbol)
    { }

    /**
     * @notice Returns the address of the Vault for the given asset.
     * @dev Vault changes do not emit VaultChange event as this is handled by the Controller.
     * @param asset The address of the asset.
     * @return The address of the associated Vault.
     */
    function vault(address asset) external view returns (address) {
        return IController(owner()).vaultFor(asset);
    }

    /**
     * @notice Checks if the contract supports a specific interface.
     * @dev Returns true for IERC165, IERC20, and IERC7575Share interfaces.
     * @param interfaceId The interface identifier to check
     * @return True if the interface is supported, false otherwise
     */
    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == type(IERC165).interfaceId || interfaceId == type(IERC20).interfaceId
            || interfaceId == type(IERC7575Share).interfaceId;
    }
}
