// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IPool} from "@aave/contracts/interfaces/IPool.sol";

import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {AaveStrategyVaultScript} from "@script/AaveStrategyVault.s.sol";
import {AuthScript} from "@script/Auth.s.sol";
import {CashStrategyVaultScript} from "@script/CashStrategyVault.s.sol";
import {ERC4626StrategyVaultScript} from "@script/ERC4626StrategyVault.s.sol";
import {SizeMetaVaultScript} from "@script/SizeMetaVault.s.sol";

import {IVault} from "@src//IVault.sol";
import {BaseTest} from "@test/BaseTest.t.sol";
import {PoolMock} from "@test/mocks/PoolMock.t.sol";
import {VaultMock} from "@test/mocks/VaultMock.t.sol";

contract ForkTest is BaseTest {
  address public constant AAVE_POOL_BASE_MAINNET = 0xA238Dd80C259a72e81d7e4664a9801593F98d1c5;
  address public constant AAVE_POOL_CONFIGURATOR_BASE_MAINNET = 0x5731a04B1E775f0fdd454Bf70f3335886e9A96be;
  address public constant AAVE_POOL_ADMIN_BASE_MAINNET = 0x9390B1735def18560c509E2d0bc090E9d6BA257a;
  address public constant USDC_BASE_MAINNET = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
  address public constant MORPHO_SPARK_USDC_VAULT_BASE_MAINNET = 0x7BfA7C4f149E7415b73bdeDfe609237e29CBF34A;
  address public constant EULER_BASE_USDC_VAULT_BASE_MAINNET = 0x0A1a3b5f2041F33522C4efc754a7D096f880eE16;

  IERC4626 public erc4626Vault2;
  IVault public erc4626StrategyVault2;

  function setUp() public virtual override {
    vm.createSelectFork("base");

    FIRST_DEPOSIT_AMOUNT = 10e6;
    admin = address(this);
    erc20Asset = IERC20Metadata(USDC_BASE_MAINNET);
    pool = PoolMock(AAVE_POOL_BASE_MAINNET);
    erc4626Vault = VaultMock(MORPHO_SPARK_USDC_VAULT_BASE_MAINNET);
    erc4626Vault2 = IERC4626(EULER_BASE_USDC_VAULT_BASE_MAINNET);

    // deploy auth
    AuthScript authScript = new AuthScript();
    auth = authScript.deploy(admin);

    // deploy cash strategy vault
    CashStrategyVaultScript cashStrategyVaultScript = new CashStrategyVaultScript();
    _mint(erc20Asset, address(cashStrategyVaultScript), FIRST_DEPOSIT_AMOUNT);
    cashStrategyVault = cashStrategyVaultScript.deploy(auth, erc20Asset, FIRST_DEPOSIT_AMOUNT);

    // deploy erc4626 strategy vault
    ERC4626StrategyVaultScript erc4626StrategyVaultScript = new ERC4626StrategyVaultScript();
    _mint(erc20Asset, address(erc4626StrategyVaultScript), FIRST_DEPOSIT_AMOUNT);
    erc4626StrategyVault = erc4626StrategyVaultScript.deploy(auth, FIRST_DEPOSIT_AMOUNT, erc4626Vault);

    // deploy erc4626 strategy vault 2
    ERC4626StrategyVaultScript erc4626StrategyVaultScript2 = new ERC4626StrategyVaultScript();
    _mint(erc20Asset, address(erc4626StrategyVaultScript2), FIRST_DEPOSIT_AMOUNT);
    erc4626StrategyVault2 = erc4626StrategyVaultScript2.deploy(auth, FIRST_DEPOSIT_AMOUNT, erc4626Vault2);

    // deploy aave strategy vault
    AaveStrategyVaultScript aaveStrategyVaultScript = new AaveStrategyVaultScript();
    _mint(erc20Asset, address(aaveStrategyVaultScript), FIRST_DEPOSIT_AMOUNT);
    aaveStrategyVault = aaveStrategyVaultScript.deploy(auth, erc20Asset, FIRST_DEPOSIT_AMOUNT, pool);

    // deploy size meta vault
    SizeMetaVaultScript sizeMetaVaultScript = new SizeMetaVaultScript();
    IVault[] memory strategies = new IVault[](3);
    strategies[0] = IVault(address(cashStrategyVault));
    strategies[1] = IVault(address(aaveStrategyVault));
    strategies[2] = IVault(address(erc4626StrategyVault));
    _mint(erc20Asset, address(sizeMetaVaultScript), strategies.length * FIRST_DEPOSIT_AMOUNT + 1);
    sizeMetaVault = sizeMetaVaultScript.deploy(auth, erc20Asset, strategies.length * FIRST_DEPOSIT_AMOUNT + 1, strategies);

    _labels();
  }
}
