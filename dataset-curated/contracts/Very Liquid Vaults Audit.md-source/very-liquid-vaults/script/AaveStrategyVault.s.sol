// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IPool} from "@aave/contracts/interfaces/IPool.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {BaseScript} from "@script/BaseScript.s.sol";
import {Auth} from "@src/Auth.sol";
import {AaveStrategyVault} from "@src/strategies/AaveStrategyVault.sol";

contract AaveStrategyVaultScript is BaseScript {
  using SafeERC20 for IERC20Metadata;

  Auth auth;
  IERC20Metadata asset;
  uint256 firstDepositAmount;
  IPool pool;
  address fundingAccount = address(this);

  function setUp() public override {
    super.setUp();

    auth = Auth(vm.envAddress("AUTH"));
    asset = IERC20Metadata(vm.envAddress("ASSET"));
    fundingAccount = msg.sender;
    firstDepositAmount = vm.envUint("FIRST_DEPOSIT_AMOUNT");
    pool = IPool(vm.envAddress("POOL"));
  }

  function run() public {
    vm.startBroadcast();

    deploy(auth, asset, firstDepositAmount, pool);

    vm.stopBroadcast();
  }

  function deploy(Auth auth_, IERC20Metadata asset_, uint256 firstDepositAmount_, IPool pool_) public returns (AaveStrategyVault aaveStrategyVault) {
    string memory name = string.concat("Size Aave ", asset_.name(), " Strategy Vault");
    string memory symbol = string.concat("sz", "Aave", asset_.symbol());
    address implementation = address(new AaveStrategyVault());
    bytes memory initializationData = abi.encodeCall(AaveStrategyVault.initialize, (auth_, asset_, name, symbol, fundingAccount, firstDepositAmount_, pool_));
    bytes memory creationCode = abi.encodePacked(type(ERC1967Proxy).creationCode, abi.encode(implementation, initializationData));
    bytes32 salt = keccak256(initializationData);
    aaveStrategyVault = AaveStrategyVault(create2Deployer.computeAddress(salt, keccak256(creationCode)));
    asset_.forceApprove(address(aaveStrategyVault), firstDepositAmount_);
    create2Deployer.deploy(0, salt, abi.encodePacked(type(ERC1967Proxy).creationCode, abi.encode(implementation, initializationData)));
  }
}
