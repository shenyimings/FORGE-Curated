// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.10;

import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import { IMintableERC20 } from "../../../interfaces/IMintableERC20.sol";
import { MintableERC20StorageUtils } from "../../../storage/MintableERC20StorageUtils.sol";

/// @title MintableERC20
/// @author kexley, @capLabs
/// @notice Removes mint and burn transfer events from ERC20
abstract contract MintableERC20 is IMintableERC20, IERC20Metadata, MintableERC20StorageUtils, Initializable {
    /// @notice Initializes the contract
    /// @param _name The name of the token
    /// @param _symbol The symbol of the token
    /// @param _decimals The decimals of the token
    function __MintableERC20_init(string memory _name, string memory _symbol, uint8 _decimals)
        internal
        onlyInitializing
    {
        MintableERC20Storage storage $ = getMintableERC20Storage();
        $.name = _name;
        $.symbol = _symbol;
        $.decimals = _decimals;
    }

    /// @notice Mints a token to an address
    /// @dev Transfer event deliberately omitted
    /// @param _to The address to mint the token to
    /// @param _amount The amount of tokens to mint
    function _mint(address _to, uint256 _amount) internal {
        MintableERC20Storage storage $ = getMintableERC20Storage();
        $.balances[_to] += _amount;
        $.totalSupply += _amount;
    }

    /// @notice Burns a token from an address
    /// @dev Transfer event deliberately omitted
    /// @param _from The address to burn the token from
    /// @param _amount The amount of tokens to burn
    function _burn(address _from, uint256 _amount) internal {
        MintableERC20Storage storage $ = getMintableERC20Storage();
        $.balances[_from] -= _amount;
        $.totalSupply -= _amount;
    }

    /// @notice Returns the balance of an address
    /// @param _account The address to get the balance of
    /// @return balance The balance of the address
    function balanceOf(address _account) public view virtual override returns (uint256) {
        return getMintableERC20Storage().balances[_account];
    }

    /// @notice Returns the total supply of the token
    /// @return totalSupply The total supply of the token
    function totalSupply() public view virtual returns (uint256) {
        return getMintableERC20Storage().totalSupply;
    }

    /// @notice Returns the name of the token
    /// @return name The name of the token
    function name() public view virtual returns (string memory) {
        return getMintableERC20Storage().name;
    }

    /// @notice Returns the symbol of the token
    /// @return symbol The symbol of the token
    function symbol() public view virtual returns (string memory) {
        return getMintableERC20Storage().symbol;
    }

    /// @notice Returns the decimals of the token
    /// @return decimals The decimals of the token
    function decimals() public view returns (uint8) {
        return getMintableERC20Storage().decimals;
    }

    /// @notice Disabled due to this being a non-transferrable token
    function transfer(address, uint256) public pure returns (bool) {
        revert OperationNotSupported();
    }

    /// @notice Disabled due to this being a non-transferrable token
    function allowance(address, address) public pure returns (uint256) {
        revert OperationNotSupported();
    }

    /// @notice Disabled due to this being a non-transferrable token
    function approve(address, uint256) public pure returns (bool) {
        revert OperationNotSupported();
    }

    /// @notice Disabled due to this being a non-transferrable token
    function transferFrom(address, address, uint256) public pure returns (bool) {
        revert OperationNotSupported();
    }
}
