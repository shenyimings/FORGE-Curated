// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.29;

import { Test } from "forge-std/Test.sol";

import { ControlledERC7575Vault, IController, IERC20 } from "../../src/vault/ControlledERC7575Vault.sol";

import { DummyController } from "../helper/DummyController.sol";
import { MockERC20 } from "../helper/MockERC20.sol";

contract ControlledERC7575VaultHandler is Test {
    ControlledERC7575Vault public vault;
    MockERC20 public asset = new MockERC20(6);
    DummyController public controller = new DummyController(); // Controller with 1:1 asset to share ratio

    bool public zeroOutputForNonZeroInput;

    constructor() {
        vault = new ControlledERC7575Vault(IERC20(asset), IController(controller));
    }

    function deposit(uint256 assets) external {
        assets = bound(assets, 1, type(uint256).max / 1e12);
        deal(address(asset), address(this), assets);
        asset.approve(address(vault), assets);

        zeroOutputForNonZeroInput = zeroOutputForNonZeroInput || vault.deposit(assets, address(this)) == 0;
    }

    function mint(uint256 shares) external {
        shares = bound(shares, 1, type(uint256).max);
        deal(address(asset), address(this), shares);
        asset.approve(address(vault), shares);

        zeroOutputForNonZeroInput = zeroOutputForNonZeroInput || vault.mint(shares, address(this)) == 0;
    }

    function withdraw(uint256 assets) external {
        assets = bound(assets, 1, type(uint256).max / 1e12);
        zeroOutputForNonZeroInput =
            zeroOutputForNonZeroInput || vault.withdraw(assets, address(this), address(this)) == 0;
    }

    function redeem(uint256 shares) external {
        shares = bound(shares, 1, type(uint256).max);
        zeroOutputForNonZeroInput = zeroOutputForNonZeroInput || vault.redeem(shares, address(this), address(this)) == 0;
    }
}

contract ControlledERC7575VaultInvariantTest is Test {
    ControlledERC7575VaultHandler vault;

    function setUp() public virtual {
        vault = new ControlledERC7575VaultHandler();

        excludeContract(address(vault.vault()));
        excludeContract(address(vault.asset()));
        excludeContract(address(vault.controller()));
    }

    function invariant_zeroOutputForNonZeroInput() public view {
        assertFalse(vault.zeroOutputForNonZeroInput());
    }
}
