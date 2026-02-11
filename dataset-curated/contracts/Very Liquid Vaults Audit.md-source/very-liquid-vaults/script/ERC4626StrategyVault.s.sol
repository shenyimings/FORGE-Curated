// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {BaseScript} from "@script/BaseScript.s.sol";
import {Auth} from "@src/Auth.sol";
import {ERC4626StrategyVault} from "@src/strategies/ERC4626StrategyVault.sol";

contract ERC4626StrategyVaultScript is BaseScript {
  using SafeERC20 for IERC20Metadata;

  Auth auth;
  address fundingAccount = address(this);
  uint256 firstDepositAmount;
  IERC4626 vault;

  function setUp() public override {
    super.setUp();

    auth = Auth(vm.envAddress("AUTH"));
    fundingAccount = msg.sender;
    firstDepositAmount = vm.envUint("FIRST_DEPOSIT_AMOUNT");
    vault = IERC4626(vm.envAddress("VAULT"));
  }

  function run() public {
    vm.startBroadcast();

    deploy(auth, firstDepositAmount, vault);

    vm.stopBroadcast();
  }

  function deploy(Auth auth_, uint256 firstDepositAmount_, IERC4626 vault_) public returns (ERC4626StrategyVault erc4626StrategyVault) {
    string memory name = string.concat("Size ", vault_.name(), " Strategy Vault");
    string memory symbol = string.concat("sz", vault_.symbol());
    address implementation = address(new ERC4626StrategyVault());
    bytes memory initializationData = abi.encodeCall(ERC4626StrategyVault.initialize, (auth_, name, symbol, fundingAccount, firstDepositAmount_, vault_));
    bytes memory creationCode = abi.encodePacked(type(ERC1967Proxy).creationCode, abi.encode(implementation, initializationData));
    bytes32 salt = keccak256(initializationData);
    erc4626StrategyVault = ERC4626StrategyVault(create2Deployer.computeAddress(salt, keccak256(creationCode)));
    IERC20Metadata(address(vault_.asset())).forceApprove(address(erc4626StrategyVault), firstDepositAmount_);
    create2Deployer.deploy(0, salt, abi.encodePacked(type(ERC1967Proxy).creationCode, abi.encode(implementation, initializationData)));
  }
}
