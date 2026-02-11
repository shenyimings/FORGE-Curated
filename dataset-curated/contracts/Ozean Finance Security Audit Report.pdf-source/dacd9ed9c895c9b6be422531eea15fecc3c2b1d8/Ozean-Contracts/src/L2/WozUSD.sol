// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import {ERC20} from "openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ReentrancyGuard} from "openzeppelin/contracts/security/ReentrancyGuard.sol";
import {OzUSD} from "./OzUSD.sol";

/// @title  Wrapped Ozean USD (WozUSD)
/// @notice A wrapper contract for OzUSD, providing auto-compounding functionality.
/// @dev    The contract wraps ozUSD into wozUSD, which represents shares of ozUSD.
///         This contract is inspired by Lido's wstETH contract:
/// https://vscode.blockscan.com/ethereum/0x7f39c581f595b53c5cb19bd0b3f8da6c935e2ca0
contract WozUSD is ERC20, ReentrancyGuard {
    /// @notice The instance of the ozUSD proxy contract.
    OzUSD public immutable ozUSD;

    constructor(OzUSD _ozUSD) ERC20("Wrapped Ozean USD", "wozUSD") {
        ozUSD = _ozUSD;
    }

    /// @notice Wraps ozUSD into wozUSD (ozUSD shares).
    /// @param  _ozUSDAmount The amount of ozUSD to wrap into wozUSD.
    /// @return wozUSDAmount The amount of wozUSD minted based on the wrapped ozUSD.
    function wrap(uint256 _ozUSDAmount) external nonReentrant returns (uint256 wozUSDAmount) {
        require(_ozUSDAmount > 0, "WozUSD: Can't wrap zero ozUSD");
        ozUSD.transferFrom(msg.sender, address(this), _ozUSDAmount);
        wozUSDAmount = ozUSD.getSharesByPooledUSDX(_ozUSDAmount);
        _mint(msg.sender, wozUSDAmount);
    }

    /// @notice Unwraps wozUSD into ozUSD.
    /// @param  _wozUSDAmount The amount of wozUSD to unwrap into ozUSD.
    /// @return ozUSDAmount The amount of ozUSD returned based on the unwrapped wozUSD.
    function unwrap(uint256 _wozUSDAmount) external nonReentrant returns (uint256 ozUSDAmount) {
        require(_wozUSDAmount > 0, "WozUSD: Can't unwrap zero wozUSD");
        _burn(msg.sender, _wozUSDAmount);
        ozUSDAmount = ozUSD.getPooledUSDXByShares(_wozUSDAmount);
        ozUSD.transfer(msg.sender, ozUSDAmount);
    }

    /// @notice Returns the amount of ozUSD equivalent to 1 wozUSD.
    /// @return uint256 The amount of ozUSD corresponding to 1 wozUSD.
    function ozUSDPerToken() external view returns (uint256) {
        return ozUSD.getPooledUSDXByShares(1 ether);
    }

    /// @notice Returns the amount of wozUSD equivalent to 1 ozUSD.
    /// @return The amount of wozUSD corresponding to 1 ozUSD.
    function tokensPerOzUSD() external view returns (uint256) {
        return ozUSD.getSharesByPooledUSDX(1 ether);
    }
}
