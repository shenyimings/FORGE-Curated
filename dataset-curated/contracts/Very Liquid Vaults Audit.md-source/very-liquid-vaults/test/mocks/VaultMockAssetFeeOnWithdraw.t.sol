// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract VaultMockAssetFeeOnWithdraw is ERC4626, Ownable {
  using SafeERC20 for IERC20;

  uint256 public constant ASSET_FEE_PERCENT = 0.1e18;
  uint256 public constant PERCENT = 1e18;

  constructor(address _owner, IERC20 _asset, string memory _name, string memory _symbol) ERC4626(_asset) ERC20(_name, _symbol) Ownable(_owner) {}

  function _withdraw(address caller, address receiver, address owner, uint256 assets, uint256 shares) internal override {
    if (caller != owner) _spendAllowance(owner, caller, shares);

    // If asset() is ERC-777, `transfer` can trigger a reentrancy AFTER the transfer happens through the
    // `tokensReceived` hook. On the other hand, the `tokensToSend` hook, that is triggered before the transfer,
    // calls the vault, which is assumed not malicious.
    //
    // Conclusion: we need to do the transfer after the burn so that any reentrancy would happen after the
    // shares are burned and after the assets are transferred, which is a valid state.
    _burn(owner, shares);
    // asset fee on withdraw
    assets = assets * (PERCENT - ASSET_FEE_PERCENT) / PERCENT;
    SafeERC20.safeTransfer(IERC20(asset()), receiver, assets);

    emit Withdraw(caller, receiver, owner, assets, shares);
  }
}
