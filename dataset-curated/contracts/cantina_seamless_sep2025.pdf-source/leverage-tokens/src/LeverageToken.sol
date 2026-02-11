// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// Dependency imports
import {ERC20PermitUpgradeable} from
    "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PermitUpgradeable.sol";
import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

// Internal imports
import {ILeverageManager} from "src/interfaces/ILeverageManager.sol";
import {ILeverageToken} from "src/interfaces/ILeverageToken.sol";

/**
 * @dev The LeverageToken contract is an upgradeable ERC20 token that represents a claim to the equity held by the LeverageToken.
 * It is used to represent a user's claim to the equity held by the LeverageToken in the LeverageManager.
 *
 * @custom:contact security@seamlessprotocol.com
 */
contract LeverageToken is
    Initializable,
    ERC20Upgradeable,
    ERC20PermitUpgradeable,
    OwnableUpgradeable,
    ILeverageToken
{
    function initialize(address _leverageManager, string memory _name, string memory _symbol) external initializer {
        __ERC20_init(_name, _symbol);
        __ERC20Permit_init(_name);
        __Ownable_init(_leverageManager);

        emit ILeverageToken.LeverageTokenInitialized(_name, _symbol);
    }

    /// @inheritdoc ILeverageToken
    function convertToAssets(uint256 shares) public view returns (uint256 assets) {
        return ILeverageManager(owner()).convertToAssets(this, shares);
    }

    /// @inheritdoc ILeverageToken
    function convertToShares(uint256 assets) public view returns (uint256 shares) {
        return ILeverageManager(owner()).convertToShares(this, assets);
    }

    /// @inheritdoc ILeverageToken
    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }

    /// @inheritdoc ILeverageToken
    function burn(address from, uint256 amount) external onlyOwner {
        _burn(from, amount);
    }
}
