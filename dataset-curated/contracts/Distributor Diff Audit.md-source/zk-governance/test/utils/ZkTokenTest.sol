// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test, console2} from "forge-std/Test.sol";
import {ZkTokenV1} from "src/ZkTokenV1.sol";
import {IMintableAndDelegatable} from "src/interfaces/IMintableAndDelegatable.sol";

contract ZkTokenTest is Test {
  ZkTokenV1 token;
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
    token = new ZkTokenV1();
    token.initialize(admin, initMintReceiver, INITIAL_MINT_AMOUNT);
    vm.label(address(token), "ZkToken");
  }
}
