// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {BaseScript} from "@script/BaseScript.s.sol";
import {Auth} from "@src/Auth.sol";
import {SizeMetaVault} from "@src/SizeMetaVault.sol";

import {IVault} from "@src//IVault.sol";
import {CryticSizeMetaVaultMock} from "@test/mocks/CryticSizeMetaVaultMock.t.sol";

contract CryticSizeMetaVaultMockScript is BaseScript {
  using SafeERC20 for IERC20Metadata;

  Auth auth;
  IERC20Metadata asset;
  address fundingAccount = address(this);
  uint256 firstDepositAmount;
  IVault[] strategies;

  function setUp() public override {
    super.setUp();

    auth = Auth(vm.envAddress("AUTH"));
    asset = IERC20Metadata(vm.envAddress("ASSET"));
    fundingAccount = msg.sender;
    firstDepositAmount = vm.envUint("FIRST_DEPOSIT_AMOUNT");
    address[] memory strategies_ = vm.envAddress("STRATEGIES", ",");
    strategies = new IVault[](strategies_.length);
    for (uint256 i = 0; i < strategies_.length; i++) {
      strategies[i] = IVault(strategies_[i]);
    }
  }

  function run() public {
    vm.startBroadcast();

    deploy(auth, asset, firstDepositAmount, strategies);

    vm.stopBroadcast();
  }

  function deploy(Auth auth_, IERC20Metadata asset_, uint256 firstDepositAmount_, IVault[] memory strategies_) public returns (CryticSizeMetaVaultMock cryticSizeMetaVaultMock) {
    string memory name = string.concat("Size Crytic ", asset_.name(), " Vault");
    string memory symbol = string.concat("sz", "Crytic", asset_.symbol(), "Mock");
    address implementation = address(new CryticSizeMetaVaultMock());
    bytes memory initializationData = abi.encodeCall(SizeMetaVault.initialize, (auth_, asset_, name, symbol, fundingAccount, firstDepositAmount_, strategies_));
    bytes memory creationCode = abi.encodePacked(type(ERC1967Proxy).creationCode, abi.encode(implementation, initializationData));
    bytes32 salt = keccak256(initializationData);
    cryticSizeMetaVaultMock = CryticSizeMetaVaultMock(create2Deployer.computeAddress(salt, keccak256(creationCode)));
    asset_.forceApprove(address(cryticSizeMetaVaultMock), firstDepositAmount_);
    create2Deployer.deploy(0, salt, abi.encodePacked(type(ERC1967Proxy).creationCode, abi.encode(implementation, initializationData)));
  }
}
