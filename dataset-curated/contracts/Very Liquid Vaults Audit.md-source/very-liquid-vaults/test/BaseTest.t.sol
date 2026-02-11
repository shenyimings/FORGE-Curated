// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IAToken} from "@aave/contracts/interfaces/IAToken.sol";

import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {BaseScript} from "@script/BaseScript.s.sol";
import {CashStrategyVaultScript} from "@script/CashStrategyVault.s.sol";
import {SizeMetaVaultScript} from "@script/SizeMetaVault.s.sol";

import {IVault} from "@src//IVault.sol";
import {Auth, GUARDIAN_ROLE, STRATEGIST_ROLE, VAULT_MANAGER_ROLE} from "@src/Auth.sol";
import {SizeMetaVault} from "@src/SizeMetaVault.sol";
import {AaveStrategyVault} from "@src/strategies/AaveStrategyVault.sol";
import {CashStrategyVault} from "@src/strategies/CashStrategyVault.sol";
import {ERC4626StrategyVault} from "@src/strategies/ERC4626StrategyVault.sol";

import {Setup} from "@test/Setup.t.sol";
import {CryticAaveStrategyVaultMock} from "@test/mocks/CryticAaveStrategyVaultMock.t.sol";
import {CryticCashStrategyVaultMock} from "@test/mocks/CryticCashStrategyVaultMock.t.sol";
import {CryticERC4626StrategyVaultMock} from "@test/mocks/CryticERC4626StrategyVaultMock.t.sol";
import {PoolMock} from "@test/mocks/PoolMock.t.sol";
import {USDC} from "@test/mocks/USDC.t.sol";

import {VaultMock} from "@test/mocks/VaultMock.t.sol";
import {Test, console} from "forge-std/Test.sol";

contract BaseTest is Test, Setup, BaseScript {
  bytes32 constant DEFAULT_ADMIN_ROLE = 0x00;

  address internal alice = address(0x10000);
  address internal bob = address(0x20000);
  address internal charlie = address(0x30000);
  address internal admin = address(0x40000);
  address internal strategist = address(0x50000);
  address internal manager = address(0x60000);
  address internal guardian = address(0x70000);

  function setUp() public virtual override {
    super.setUp();

    deploy(admin);

    _labels();

    vm.prank(admin);
    auth.grantRole(STRATEGIST_ROLE, strategist);
    vm.prank(admin);
    auth.grantRole(VAULT_MANAGER_ROLE, manager);
    vm.prank(admin);
    auth.grantRole(GUARDIAN_ROLE, guardian);

    _setupRandomSizeMetaVaultConfiguration(admin, _getRandomUint);
  }

  function _labels() internal {
    vm.label(address(auth), "Auth");
    vm.label(address(sizeMetaVault), "SizeMetaVault");

    vm.label(address(cashStrategyVault), "CashStrategyVault");
    vm.label(address(aaveStrategyVault), "AaveStrategyVault");
    vm.label(address(erc4626StrategyVault), "ERC4626StrategyVault");

    vm.label(address(cryticCashStrategyVault), "CryticCashStrategyVault");
    vm.label(address(cryticAaveStrategyVault), "CryticAaveStrategyVault");
    vm.label(address(cryticERC4626StrategyVault), "CryticERC4626StrategyVault");

    vm.label(address(erc20Asset), "ERC20Asset");
    vm.label(address(pool), "Pool");
    vm.label(address(aToken), "AToken");
    vm.label(address(erc4626Vault), "ERC4626Vault");

    vm.label(address(alice), "alice");
    vm.label(address(bob), "bob");
    vm.label(address(charlie), "charlie");
    vm.label(address(admin), "admin");
    vm.label(address(strategist), "strategist");

    vm.label(address(this), "Test");
    vm.label(address(0), "address(0)");
  }

  function _mint(IERC20Metadata _asset, address _to, uint256 _amount) internal {
    deal(address(_asset), _to, _amount);
  }

  function _burn(IERC20Metadata _asset, address _from, uint256 _amount) internal {
    vm.prank(USDC(address(_asset)).owner());
    USDC(address(_asset)).burn(_from, _amount);
  }

  function _approve(address _user, IERC20Metadata _asset, address _spender, uint256 _amount) internal {
    vm.prank(_user);
    _asset.approve(_spender, _amount);
  }

  function _deposit(address _user, IERC4626 _vault, uint256 _amount) internal {
    _mint(IERC20Metadata(address(_vault.asset())), _user, _amount);
    _approve(_user, IERC20Metadata(address(_vault.asset())), address(_vault), _amount);
    vm.prank(_user);
    _vault.deposit(_amount, _user);
  }

  function _withdraw(address _user, IERC4626 _vault, uint256 _amount) internal {
    vm.prank(_user);
    _vault.withdraw(_amount, _user, _user);
  }

  function _setLiquidityIndex(IERC20Metadata _asset, uint256 _index) internal {
    vm.prank(admin);
    pool.setLiquidityIndex(address(_asset), _index);
  }

  function assertEq(uint256 _a, uint256 _b, uint256 _c) internal pure {
    assertEq(_a, _b);
    assertEq(_a, _c);
  }

  function mem(address[4] memory accounts) internal pure returns (address[] memory ans) {
    ans = new address[](accounts.length);
    for (uint256 i = 0; i < accounts.length; i++) {
      ans[i] = accounts[i];
    }
  }

  function _getRandomUint(uint256 min, uint256 max) internal returns (uint256) {
    return vm.randomUint(min, max);
  }

  function _log(SizeMetaVault _sizeMetaVault) internal view {
    string memory log = "SizeMetaVault\n";
    log = string.concat(log, "  totalAssets             ", vm.toString(_sizeMetaVault.totalAssets()), "\n");
    log = string.concat(log, "  totalSupply             ", vm.toString(_sizeMetaVault.totalSupply()), "\n");
    log = string.concat(log, "  strategies              ", vm.toString(_sizeMetaVault.strategiesCount()), "\n");
    for (uint256 i = 0; i < _sizeMetaVault.strategiesCount(); i++) {
      IVault strategy = _sizeMetaVault.strategies(i);
      string memory label = strategy == cashStrategyVault
        ? "CashStrategyVault     "
        : strategy == aaveStrategyVault ? "AaveStrategyVault     " : strategy == erc4626StrategyVault ? "ERC4626StrategyVault  " : "IVault                ";
      uint256 balance = strategy.balanceOf(address(_sizeMetaVault));
      uint256 assets = strategy.convertToAssets(balance);
      log = string.concat(log, "    ", label, vm.toString(address(strategy)), " ", vm.toString(balance), " ", vm.toString(assets), "\n");
    }
    console.log(log);
  }

  function _setupSimpleConfiguration() internal {
    IVault[] memory strategies = new IVault[](3);
    strategies[0] = cashStrategyVault;
    strategies[1] = aaveStrategyVault;
    strategies[2] = erc4626StrategyVault;
    vm.prank(admin);
    sizeMetaVault.reorderStrategies(strategies);

    uint256 assetsAave = aaveStrategyVault.maxWithdraw(address(sizeMetaVault));
    uint256 assetsErc4626 = erc4626StrategyVault.maxWithdraw(address(sizeMetaVault));

    if (assetsAave > 0) {
      vm.prank(admin);
      sizeMetaVault.rebalance(aaveStrategyVault, cashStrategyVault, assetsAave, type(uint256).max);
    }
    if (assetsErc4626 > 0) {
      vm.prank(admin);
      sizeMetaVault.rebalance(erc4626StrategyVault, cashStrategyVault, assetsErc4626, type(uint256).max);
    }
  }
}
