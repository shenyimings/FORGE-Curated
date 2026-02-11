// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {BaseScript} from "@script/BaseScript.s.sol";
import {Auth} from "@src/Auth.sol";
import {SizeMetaVault} from "@src/SizeMetaVault.sol";

import {IVault} from "@src//IVault.sol";

contract SizeMetaVaultScript is BaseScript {
  using SafeERC20 for IERC20;

  Auth auth;
  IERC20Metadata asset;
  address fundingAccount = address(this);
  uint256 sizeMetaVaultFirstDepositAmount;
  IVault[] strategies;

  function setUp() public override {
    super.setUp();

    auth = Auth(vm.envAddress("AUTH"));
    asset = IERC20Metadata(vm.envAddress("ASSET"));
    fundingAccount = msg.sender;
    sizeMetaVaultFirstDepositAmount = vm.envUint("SIZE_META_VAULT_FIRST_DEPOSIT_AMOUNT");
    address[] memory strategies_ = vm.envAddress("STRATEGIES", ",");
    strategies = new IVault[](strategies_.length);
    for (uint256 i = 0; i < strategies_.length; i++) {
      strategies[i] = IVault(strategies_[i]);
    }
  }

  function run() public {
    vm.startBroadcast();

    deploy(auth, asset, sizeMetaVaultFirstDepositAmount, strategies);

    vm.stopBroadcast();
  }

  function deploy(Auth auth_, IERC20Metadata asset_, uint256 sizeMetaVaultFirstDepositAmount_, IVault[] memory strategies_) public returns (SizeMetaVault sizeMetaVault) {
    string memory name = string.concat("Size Meta ", asset_.name(), " Vault");
    string memory symbol = string.concat("sz", "Meta", asset_.symbol());
    address implementation = address(new SizeMetaVault());
    bytes memory initializationData = abi.encodeCall(SizeMetaVault.initialize, (auth_, asset_, name, symbol, fundingAccount, sizeMetaVaultFirstDepositAmount_, strategies_));
    bytes memory creationCode = abi.encodePacked(type(ERC1967Proxy).creationCode, abi.encode(implementation, initializationData));
    bytes32 salt = keccak256(initializationData);
    sizeMetaVault = SizeMetaVault(create2Deployer.computeAddress(salt, keccak256(creationCode)));
    IERC20(address(asset_)).forceApprove(address(sizeMetaVault), sizeMetaVaultFirstDepositAmount_);
    create2Deployer.deploy(0, salt, abi.encodePacked(type(ERC1967Proxy).creationCode, abi.encode(implementation, initializationData)));
  }
}
