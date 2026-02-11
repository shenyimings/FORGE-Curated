// SPDX-License-Identifier: MIT
pragma solidity >=0.8.21;

import {
    IERC20,
    IERC4626,
    ERC20,
    ERC4626,
    Math
} from "openzeppelin-contracts/token/ERC20/extensions/ERC4626.sol";

contract VaultMock0 is ERC4626 {
   constructor(IERC20 asset) ERC4626(asset) ERC20("VaultMock0", "V0") {}

   function maxDeposit(address owner) public view virtual override returns (uint256) {
        return type(uint256).max;
    }

   function getTotalSupply(address vault) external view returns (uint256) {
      return IERC20(vault).totalSupply();
   }

   function getConvertToShares(address vault, uint256 assets) external view returns (uint256) {
        return IERC4626(vault).convertToShares(assets);
   }

   function getConvertToAssets(address vault, uint256 shares) external view returns (uint256) {
        return IERC4626(vault).convertToAssets(shares);
   }

   function convertToAssets(uint256 shares, Math.Rounding rounding) external view returns (uint256) {
        return _convertToAssets(shares, rounding);
   }

   function convertToShares(uint256 assets, Math.Rounding rounding) external view returns (uint256) {
        return _convertToAssets(assets, rounding);
   }

}