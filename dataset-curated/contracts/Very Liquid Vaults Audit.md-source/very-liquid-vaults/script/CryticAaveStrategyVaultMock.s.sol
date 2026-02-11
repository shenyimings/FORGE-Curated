// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {BaseScript} from "@script/BaseScript.s.sol";
import {Auth} from "@src/Auth.sol";
import {AaveStrategyVault} from "@src/strategies/AaveStrategyVault.sol";
import {CryticAaveStrategyVaultMock} from "@test/mocks/CryticAaveStrategyVaultMock.t.sol";
import {PoolMock} from "@test/mocks/PoolMock.t.sol";

contract CryticAaveStrategyVaultMockScript is BaseScript {
  using SafeERC20 for IERC20Metadata;

  Auth auth;
  IERC20Metadata asset;
  PoolMock pool;
  address fundingAccount = address(this);
  uint256 firstDepositAmount;

  function setUp() public override {
    super.setUp();

    auth = Auth(vm.envAddress("AUTH"));
    asset = IERC20Metadata(vm.envAddress("ASSET"));
    pool = PoolMock(vm.envAddress("POOL"));
    fundingAccount = msg.sender;
    firstDepositAmount = vm.envUint("FIRST_DEPOSIT_AMOUNT");
  }

  function run() public {
    vm.startBroadcast();

    deploy(auth, asset, firstDepositAmount, pool);

    vm.stopBroadcast();
  }

  function deploy(Auth auth_, IERC20Metadata asset_, uint256 firstDepositAmount_, PoolMock pool_) public returns (CryticAaveStrategyVaultMock cryticAaveStrategyVaultMock) {
    string memory name = string.concat("Size Crytic Aave ", asset_.name(), " Strategy Mock Vault");
    string memory symbol = string.concat("sz", "Aave", asset_.symbol(), "Mock");
    address implementation = address(new CryticAaveStrategyVaultMock());
    bytes memory initializationData = abi.encodeCall(AaveStrategyVault.initialize, (auth_, asset_, name, symbol, fundingAccount, firstDepositAmount_, pool_));
    bytes memory creationCode = abi.encodePacked(type(ERC1967Proxy).creationCode, abi.encode(implementation, initializationData));
    bytes32 salt = keccak256(initializationData);
    cryticAaveStrategyVaultMock = CryticAaveStrategyVaultMock(create2Deployer.computeAddress(salt, keccak256(creationCode)));
    asset_.forceApprove(address(cryticAaveStrategyVaultMock), firstDepositAmount_);
    create2Deployer.deploy(0, salt, abi.encodePacked(type(ERC1967Proxy).creationCode, abi.encode(implementation, initializationData)));
  }
}
