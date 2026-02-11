// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.0;

import {BaseTargetFunctions} from "@chimera/BaseTargetFunctions.sol";
import {Ghosts} from "@test/recon/Ghosts.t.sol";
import {Properties} from "@test/recon/Properties.t.sol";
import {console} from "forge-std/console.sol";
// Chimera deps
import {vm} from "@chimera/Hevm.sol";

// Helpers
import {Panic} from "@recon/Panic.sol";

import "src/SizeMetaVault.sol";

abstract contract ERC4626MustNotRevertTargets is BaseTargetFunctions, Properties {
  function erc4626_mustNotRevert_asset() public {
    for (uint256 i = 0; i < vaults.length; i++) {
      try vaults[i].asset() {}
      catch {
        t(false, string.concat(ERC4626_MUST_NOT_REVERT, "asset"));
      }
    }
  }

  function erc4626_mustNotRevert_totalAssets() public {
    for (uint256 i = 0; i < vaults.length; i++) {
      try vaults[i].totalAssets() {}
      catch {
        t(false, string.concat(ERC4626_MUST_NOT_REVERT, "totalAssets"));
      }
    }
  }

  function erc4626_mustNotRevert_convertToShares(uint256 assets) public {
    assets = between(assets, 0, type(uint128).max);
    for (uint256 i = 0; i < vaults.length; i++) {
      try vaults[i].convertToShares(assets) {}
      catch {
        t(false, string.concat(ERC4626_MUST_NOT_REVERT, "convertToShares"));
      }
    }
  }

  function erc4626_mustNotRevert_convertToAssets(uint256 shares) public {
    shares = between(shares, 0, type(uint128).max);
    for (uint256 i = 0; i < vaults.length; i++) {
      try vaults[i].convertToAssets(shares) {}
      catch {
        t(false, string.concat(ERC4626_MUST_NOT_REVERT, "convertToAssets"));
      }
    }
  }

  function erc4626_mustNotRevert_maxDeposit(address receiver) public {
    for (uint256 i = 0; i < vaults.length; i++) {
      try vaults[i].maxDeposit(receiver) {}
      catch {
        t(false, string.concat(ERC4626_MUST_NOT_REVERT, "maxDeposit"));
      }
    }
  }

  function erc4626_mustNotRevert_previewDeposit(uint256 assets) public {
    assets = between(assets, 0, type(uint128).max);
    for (uint256 i = 0; i < vaults.length; i++) {
      try vaults[i].previewDeposit(assets) {}
      catch {
        t(false, string.concat(ERC4626_MUST_NOT_REVERT, "previewDeposit"));
      }
    }
  }

  function erc4626_mustNotRevert_maxMint(address receiver) public {
    for (uint256 i = 0; i < vaults.length; i++) {
      try vaults[i].maxMint(receiver) {}
      catch {
        t(false, string.concat(ERC4626_MUST_NOT_REVERT, "maxMint"));
      }
    }
  }

  function erc4626_mustNotRevert_previewMint(uint256 shares) public {
    shares = between(shares, 0, type(uint128).max);
    for (uint256 i = 0; i < vaults.length; i++) {
      try vaults[i].previewMint(shares) {}
      catch {
        t(false, string.concat(ERC4626_MUST_NOT_REVERT, "previewMint"));
      }
    }
  }

  function erc4626_mustNotRevert_maxWithdraw(address owner) public {
    for (uint256 i = 0; i < vaults.length; i++) {
      try vaults[i].maxWithdraw(owner) {}
      catch {
        t(false, string.concat(ERC4626_MUST_NOT_REVERT, "maxWithdraw"));
      }
    }
  }

  function erc4626_mustNotRevert_previewWithdraw(uint256 assets) public {
    assets = between(assets, 0, type(uint128).max);
    for (uint256 i = 0; i < vaults.length; i++) {
      try vaults[i].previewWithdraw(assets) {}
      catch {
        t(false, string.concat(ERC4626_MUST_NOT_REVERT, "previewWithdraw"));
      }
    }
  }

  function erc4626_mustNotRevert_maxRedeem(address owner) public {
    for (uint256 i = 0; i < vaults.length; i++) {
      try vaults[i].maxRedeem(owner) {}
      catch {
        t(false, string.concat(ERC4626_MUST_NOT_REVERT, "maxRedeem"));
      }
    }
  }

  function erc4626_mustNotRevert_previewRedeem(uint256 shares) public {
    shares = between(shares, 0, type(uint128).max);
    for (uint256 i = 0; i < vaults.length; i++) {
      try vaults[i].previewRedeem(shares) {}
      catch {
        t(false, string.concat(ERC4626_MUST_NOT_REVERT, "previewRedeem"));
      }
    }
  }
}
