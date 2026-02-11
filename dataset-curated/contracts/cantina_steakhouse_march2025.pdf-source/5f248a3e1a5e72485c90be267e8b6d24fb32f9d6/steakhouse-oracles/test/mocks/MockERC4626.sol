// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/interfaces/IERC20Metadata.sol";

contract MockERC4626 is ERC4626 {
    uint256 private _mockAssets;
    uint256 private _mockShares;

    constructor(
        IERC20 asset_,
        string memory name_,
        string memory symbol_
    ) ERC20(name_, symbol_) ERC4626(asset_) {}

    function setConvertToAssets(uint256 shares, uint256 assets) external {
        _mockShares = shares;
        _mockAssets = assets;
    }

    function convertToAssets(uint256 shares) public view virtual override returns (uint256) {
        if (_mockShares == 0) return 0;
        return (shares * _mockAssets) / _mockShares;
    }

    function mint(address account, uint256 amount) external {
        _mint(account, amount);
    }

    function burn(address account, uint256 amount) external {
        _burn(account, amount);
    }
} 