// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { Vault } from "../vault/Vault.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

/// @title Cap Token
/// @author kexley, @capLabs
/// @notice Token representing the basket of underlying assets
contract CapToken is UUPSUpgradeable, Vault {
    /// @dev Disable initializers on the implementation
    constructor() {
        _disableInitializers();
    }

    /// @notice Initialize the Cap token
    /// @param _name Name of the cap token
    /// @param _symbol Symbol of the cap token
    /// @param _accessControl Access controller
    /// @param _feeAuction Fee auction address
    /// @param _oracle Oracle address
    /// @param _assets Asset addresses to mint Cap token with
    /// @param _insuranceFund Insurance fund
    function initialize(
        string memory _name,
        string memory _symbol,
        address _accessControl,
        address _feeAuction,
        address _oracle,
        address[] calldata _assets,
        address _insuranceFund
    ) external initializer {
        __Vault_init(_name, _symbol, _accessControl, _feeAuction, _oracle, _assets, _insuranceFund);
        __UUPSUpgradeable_init();
    }

    /// @dev Only admin can upgrade
    function _authorizeUpgrade(address) internal view override checkAccess(bytes4(0)) { }
}
