// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC165 } from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

import { ERC20Mintable } from "./ERC20Mintable.sol";

/**
 * @title GenericUnitL2
 * @notice A Layer 2 mirror of the GenericUnit token with minting capabilities and interface support detection
 * @dev This contract extends ERC20Mintable to provide a mintable ERC20 token that serves as a mirror
 * of the GenericUnit token deployed on other chains. It includes interface support checking for IERC165 and IERC20
 * standards. The coordinator address receives mint/burn privileges upon deployment.
 */
contract GenericUnitL2 is ERC20Mintable {
    /**
     * @notice Initializes the GenericUnit L2 token with metadata and sets the owner.
     * @dev The owner address gets mint/burn privileges.
     * @param coordinator Address to be set as the owner
     * @param name ERC20 token name
     * @param symbol ERC20 token symbol
     */
    constructor(
        address coordinator,
        string memory name,
        string memory symbol
    )
        ERC20Mintable(coordinator, name, symbol)
    { }

    /**
     * @notice Checks if the contract supports a specific interface.
     * @dev Returns true for IERC165 and IERC20 interfaces.
     * @param interfaceId The interface identifier to check
     * @return True if the interface is supported, false otherwise
     */
    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == type(IERC165).interfaceId || interfaceId == type(IERC20).interfaceId;
    }
}
