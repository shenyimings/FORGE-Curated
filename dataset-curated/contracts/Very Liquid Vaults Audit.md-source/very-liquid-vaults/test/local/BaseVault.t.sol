// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {UUPSUpgradeable} from "@openzeppelin-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";

import {ERC4626Upgradeable} from "@openzeppelin-upgradeable/contracts/token/ERC20/extensions/ERC4626Upgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin-upgradeable/contracts/utils/PausableUpgradeable.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Create2} from "@openzeppelin/contracts/utils/Create2.sol";
import {DEFAULT_ADMIN_ROLE, GUARDIAN_ROLE, VAULT_MANAGER_ROLE} from "@src/Auth.sol";
import {BaseVault} from "@src/utils/BaseVault.sol";
import {BaseTest} from "@test/BaseTest.t.sol";
import {BaseVaultMock} from "@test/mocks/BaseVaultMock.t.sol";

import {BaseVaultMockMaxDeposit0} from "@test/mocks/BaseVaultMockMaxDeposit0.t.sol";

contract BaseVaultTest is BaseTest {
  using SafeERC20 for IERC20Metadata;

  function test_BaseVault_initialize() public view {
    assertEq(baseVault.asset(), address(erc20Asset));
    assertEq(baseVault.name(), "Size Base USD Coin Mock Vault");
    assertEq(baseVault.symbol(), "szBaseUSDCMock");
    assertEq(baseVault.decimals(), erc20Asset.decimals(), 6);
  }

  function test_BaseVault_upgrade() public {
    BaseVaultMock newBaseVault = new BaseVaultMock();
    vm.prank(alice);
    vm.expectRevert(abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, alice, DEFAULT_ADMIN_ROLE));
    UUPSUpgradeable(address(baseVault)).upgradeToAndCall(address(newBaseVault), "");

    vm.prank(admin);
    UUPSUpgradeable(address(baseVault)).upgradeToAndCall(address(newBaseVault), "");
  }

  function test_BaseVault_initialize_invalidInitialization_reverts() public {
    BaseVaultMock newBaseVault = new BaseVaultMock();
    vm.expectRevert(Initializable.InvalidInitialization.selector);
    newBaseVault.initialize(auth, IERC20(address(0)), "Test", "TST", address(this), FIRST_DEPOSIT_AMOUNT);
  }

  function test_BaseVault_pause_success() public {
    assertFalse(baseVault.paused());

    vm.prank(admin);
    auth.grantRole(GUARDIAN_ROLE, admin);

    vm.prank(admin);
    baseVault.pause();

    assertTrue(baseVault.paused());
  }

  function test_BaseVault_pause_unauthorized_reverts() public {
    vm.prank(alice);
    vm.expectRevert(abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, alice, GUARDIAN_ROLE));
    baseVault.pause();
  }

  function test_BaseVault_unpause_success() public {
    vm.prank(admin);
    auth.grantRole(GUARDIAN_ROLE, admin);

    vm.prank(admin);
    baseVault.pause();
    assertTrue(baseVault.paused());

    vm.prank(admin);
    baseVault.unpause();

    assertFalse(baseVault.paused());
  }

  function test_BaseVault_unpause_unauthorized_reverts() public {
    vm.prank(admin);
    auth.grantRole(VAULT_MANAGER_ROLE, admin);

    vm.prank(admin);
    baseVault.pause();

    vm.prank(alice);
    vm.expectRevert(abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, alice, VAULT_MANAGER_ROLE));
    baseVault.unpause();
  }

  function test_BaseVault_deposit_whenPaused_reverts() public {
    uint256 amount = 100e6;
    _mint(erc20Asset, alice, amount);
    _approve(alice, erc20Asset, address(baseVault), amount);

    vm.prank(admin);
    auth.grantRole(GUARDIAN_ROLE, admin);

    vm.prank(admin);
    baseVault.pause();

    vm.prank(alice);
    vm.expectRevert(abi.encodeWithSelector(ERC4626Upgradeable.ERC4626ExceededMaxDeposit.selector, alice, amount, 0));
    baseVault.deposit(amount, alice);
  }

  function test_BaseVault_deposit_when_auth_paused_reverts() public {
    uint256 amount = 100e6;
    _mint(erc20Asset, alice, amount);
    _approve(alice, erc20Asset, address(baseVault), amount);

    vm.prank(admin);
    auth.pause();

    vm.prank(alice);
    vm.expectRevert(abi.encodeWithSelector(ERC4626Upgradeable.ERC4626ExceededMaxDeposit.selector, alice, amount, 0));
    baseVault.deposit(amount, alice);

    vm.prank(admin);
    auth.unpause();

    vm.prank(alice);
    baseVault.deposit(amount, alice);
    assertEq(baseVault.balanceOf(alice), amount);
  }

  function test_BaseVault_transfer_whenPaused_reverts() public {
    uint256 amount = 100e6;
    _mint(erc20Asset, alice, amount);
    _approve(alice, erc20Asset, address(baseVault), amount);

    vm.prank(alice);
    baseVault.deposit(amount, alice);

    vm.prank(admin);
    auth.grantRole(GUARDIAN_ROLE, admin);

    vm.prank(admin);
    baseVault.pause();

    vm.prank(alice);
    vm.expectRevert(abi.encodeWithSelector(PausableUpgradeable.EnforcedPause.selector));
    baseVault.transfer(bob, amount);
  }

  function test_BaseVault_transfer_whenAuthPaused_reverts() public {
    uint256 amount = 100e6;
    _mint(erc20Asset, alice, amount);
    _approve(alice, erc20Asset, address(baseVault), amount);

    vm.prank(alice);
    baseVault.deposit(amount, alice);

    vm.prank(admin);
    auth.pause();

    vm.prank(alice);
    vm.expectRevert(abi.encodeWithSelector(PausableUpgradeable.EnforcedPause.selector));
    baseVault.transfer(bob, amount);
  }

  function test_BaseVault_deposit_withdraw_basic() public {
    uint256 depositAmount = 100e6;
    _mint(erc20Asset, alice, depositAmount);
    _approve(alice, erc20Asset, address(baseVault), depositAmount);

    vm.prank(alice);
    baseVault.deposit(depositAmount, alice);

    assertEq(baseVault.balanceOf(alice), depositAmount);
    assertEq(baseVault.totalAssets(), FIRST_DEPOSIT_AMOUNT + depositAmount);
    assertEq(erc20Asset.balanceOf(address(baseVault)), FIRST_DEPOSIT_AMOUNT + depositAmount);
    assertEq(erc20Asset.balanceOf(alice), 0);

    uint256 withdrawAmount = 30e6;
    vm.prank(alice);
    baseVault.withdraw(withdrawAmount, alice, alice);

    assertEq(baseVault.balanceOf(alice), depositAmount - withdrawAmount);
    assertEq(baseVault.totalAssets(), FIRST_DEPOSIT_AMOUNT + depositAmount - withdrawAmount);
    assertEq(erc20Asset.balanceOf(address(baseVault)), FIRST_DEPOSIT_AMOUNT + depositAmount - withdrawAmount);
    assertEq(erc20Asset.balanceOf(alice), withdrawAmount);
  }

  function test_BaseVault_firstDeposit_reverts_when_maxDeposit_is_0() public {
    string memory name = string.concat("Size Base ", erc20Asset.name(), " Mock Vault");
    string memory symbol = string.concat("sz", "Base", erc20Asset.symbol(), "Mock");
    address implementation = address(new BaseVaultMockMaxDeposit0());
    uint256 firstDepositAmount = 42e6;
    bytes memory initializationData = abi.encodeCall(BaseVault.initialize, (auth, erc20Asset, name, symbol, address(this), firstDepositAmount));
    bytes memory creationCode = abi.encodePacked(type(ERC1967Proxy).creationCode, abi.encode(implementation, initializationData));
    bytes32 salt = keccak256(initializationData);
    BaseVaultMockMaxDeposit0 baseVaultMockMaxDeposit0 = BaseVaultMockMaxDeposit0(Create2.computeAddress(salt, keccak256(creationCode)));

    _mint(erc20Asset, address(this), firstDepositAmount);

    erc20Asset.forceApprove(address(baseVaultMockMaxDeposit0), firstDepositAmount);
    vm.expectRevert(abi.encodeWithSelector(ERC4626Upgradeable.ERC4626ExceededMaxDeposit.selector, address(baseVaultMockMaxDeposit0), firstDepositAmount, 0));
    Create2.deploy(0, salt, abi.encodePacked(type(ERC1967Proxy).creationCode, abi.encode(implementation, initializationData)));
  }

  function test_BaseVault_setTotalAssetsCap() public {
    uint256 totalAssetsCap = 1000e6;
    vm.prank(alice);
    vm.expectRevert(abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, alice, VAULT_MANAGER_ROLE));
    baseVault.setTotalAssetsCap(totalAssetsCap);

    assertEq(baseVault.totalAssetsCap(), type(uint256).max);

    vm.prank(manager);
    baseVault.setTotalAssetsCap(totalAssetsCap);
    assertEq(baseVault.totalAssetsCap(), totalAssetsCap);
  }

  function test_BaseVault_deposit_reverts_when_totalAssetsCap_is_reached() public {
    uint256 totalAssetsCap = 1000e6;
    vm.prank(manager);
    baseVault.setTotalAssetsCap(totalAssetsCap);

    _mint(erc20Asset, address(baseVault), totalAssetsCap);

    uint256 depositAmount = 100e6;
    _mint(erc20Asset, alice, depositAmount);
    _approve(alice, erc20Asset, address(baseVault), depositAmount);

    vm.prank(alice);
    vm.expectRevert(abi.encodeWithSelector(ERC4626Upgradeable.ERC4626ExceededMaxDeposit.selector, alice, depositAmount, 0));
    baseVault.deposit(depositAmount, alice);
  }

  function test_BaseVault_paused() public {
    uint256 amount = 100e6;
    _deposit(alice, baseVault, amount);

    vm.prank(admin);
    baseVault.pause();

    assertEq(baseVault.maxDeposit(alice), 0);
    assertEq(baseVault.maxMint(alice), 0);
    assertEq(baseVault.maxWithdraw(alice), 0);
    assertEq(baseVault.maxRedeem(alice), 0);

    vm.prank(admin);
    baseVault.unpause();

    assertEq(baseVault.maxDeposit(alice), type(uint256).max);
    assertEq(baseVault.maxMint(alice), type(uint256).max);
    assertEq(baseVault.maxWithdraw(alice), amount);
    assertEq(baseVault.maxRedeem(alice), amount);

    vm.prank(admin);
    auth.pause();

    assertEq(baseVault.maxDeposit(alice), 0);
    assertEq(baseVault.maxMint(alice), 0);
    assertEq(baseVault.maxWithdraw(alice), 0);
    assertEq(baseVault.maxRedeem(alice), 0);
  }
}
