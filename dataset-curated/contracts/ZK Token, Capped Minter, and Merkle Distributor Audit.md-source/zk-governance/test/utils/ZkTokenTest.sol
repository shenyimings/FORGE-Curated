// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test, console2} from "forge-std/Test.sol";
import {Upgrades} from "@openzeppelin/foundry-upgrades/Upgrades.sol";
import {ZkTokenV1} from "src/ZkTokenV1.sol";
import {IMintableAndDelegatable} from "src/interfaces/IMintableAndDelegatable.sol";
import {ERC1967Utils} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";

contract ZkTokenTest is Test {
  ZkTokenV1 token;
  address proxyAdmin;
  address proxy;

  address proxyOwner = makeAddr("Proxy Owner");
  address admin = makeAddr("Admin");
  address initMintReceiver = makeAddr("Init Mint Receiver");

  uint256 INITIAL_MINT_AMOUNT = 1_000_000_000e18;

  // Placed here for convenience in tests. Must match the constants in the implementation.
  bytes32 public DEFAULT_ADMIN_ROLE = 0x00;
  bytes32 public MINTER_ROLE = keccak256("MINTER_ROLE");
  bytes32 public BURNER_ROLE = keccak256("BURNER_ROLE");
  bytes32 public MINTER_ADMIN_ROLE = keccak256("MINTER_ADMIN_ROLE");
  bytes32 public BURNER_ADMIN_ROLE = keccak256("BURNER_ADMIN_ROLE");

  // As defined internally in ERC20Votes
  uint256 MAX_MINT_SUPPLY = type(uint208).max - INITIAL_MINT_AMOUNT;

  function setUp() public virtual {
    proxy = Upgrades.deployTransparentProxy(
      "ZkTokenV1.sol", proxyOwner, abi.encodeCall(ZkTokenV1.initialize, (admin, initMintReceiver, INITIAL_MINT_AMOUNT))
    );
    vm.label(proxy, "Proxy");

    // The ProxyAdmin is a contract deployed internally by the TransparentUpgradeableProxy contract, which is not
    // exposed publicly, but can be accessed directly at a predictable slot position.
    bytes32 _proxyAdminSlot = vm.load(proxy, ERC1967Utils.ADMIN_SLOT);
    proxyAdmin = address(uint160(uint256(_proxyAdminSlot)));
    vm.label(proxyAdmin, "ProxyAdmin");

    token = ZkTokenV1(proxy);
    vm.label(address(token), "Token");
  }

  // Helper to prevent the fuzzer from selecting the ProxyAdmin for a given address. By definition, the ProxyAdmin
  // address is not allowed to call any "normal" (i.e. non-upgrade-related) methods on the token contract, so this
  // helper should be called on any address selected by the fuzzer that will call a method on the token contract.
  function _assumeNotProxyAdmin(address _account) public view {
    vm.assume(_account != proxyAdmin);
  }
}
