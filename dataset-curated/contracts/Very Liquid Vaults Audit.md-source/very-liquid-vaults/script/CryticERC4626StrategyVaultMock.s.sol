// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {BaseScript} from "@script/BaseScript.s.sol";
import {Auth} from "@src/Auth.sol";
import {SizeMetaVault} from "@src/SizeMetaVault.sol";
import {ERC4626StrategyVault} from "@src/strategies/ERC4626StrategyVault.sol";
import {CryticERC4626StrategyVaultMock} from "@test/mocks/CryticERC4626StrategyVaultMock.t.sol";
import {VaultMock} from "@test/mocks/VaultMock.t.sol";

contract CryticERC4626StrategyVaultMockScript is BaseScript {
  using SafeERC20 for IERC20Metadata;

  Auth auth;
  address fundingAccount = address(this);
  uint256 firstDepositAmount;
  VaultMock vault;

  function setUp() public override {
    super.setUp();

    auth = Auth(vm.envAddress("AUTH"));
    fundingAccount = msg.sender;
    firstDepositAmount = vm.envUint("FIRST_DEPOSIT_AMOUNT");
    vault = VaultMock(vm.envAddress("VAULT"));
  }

  function run() public {
    vm.startBroadcast();

    deploy(auth, firstDepositAmount, vault);

    vm.stopBroadcast();
  }

  function deploy(Auth auth_, uint256 firstDepositAmount_, VaultMock vault_) public returns (CryticERC4626StrategyVaultMock cryticERC4626StrategyVaultMock) {
    string memory name = string.concat("Size ", vault_.name(), " Strategy Mock Vault");
    string memory symbol = string.concat("sz", vault_.symbol(), "Mock");
    address implementation = address(new CryticERC4626StrategyVaultMock());
    bytes memory initializationData = abi.encodeCall(ERC4626StrategyVault.initialize, (auth_, name, symbol, fundingAccount, firstDepositAmount_, vault_));
    bytes memory creationCode = abi.encodePacked(type(ERC1967Proxy).creationCode, abi.encode(implementation, initializationData));
    bytes32 salt = keccak256(initializationData);
    cryticERC4626StrategyVaultMock = CryticERC4626StrategyVaultMock(create2Deployer.computeAddress(salt, keccak256(creationCode)));
    IERC20Metadata(address(vault_.asset())).forceApprove(address(cryticERC4626StrategyVaultMock), firstDepositAmount_);
    create2Deployer.deploy(0, salt, abi.encodePacked(type(ERC1967Proxy).creationCode, abi.encode(implementation, initializationData)));
  }
}
