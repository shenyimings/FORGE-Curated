// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {Distributor} from "src/Distributor.sol";
import {MockERC20} from "test/mocks/MockERC20.sol";
import {MerkleTree} from "test/utils/MerkleTree.sol";

abstract contract SetupDistributor is Test {
    Distributor public distributor;
    MockERC20 public token1;
    MockERC20 public token2;
    MockERC20 public token3;

    address public owner;
    address public manager;
    address public userAlice;
    address public userBob;
    address public userCharlie;

    MerkleTree public merkleTree;

    // Events from Distributor
    event TokenAdded(address indexed token);
    event Claimed(address indexed recipient, address indexed token, uint256 amount);
    event MerkleRootUpdated(
        bytes32 oldRoot, bytes32 indexed newRoot, string oldCid, string newCid, uint256 oldBlock, uint256 newBlock
    );

    function setUp() public virtual {
        // Create addresses
        owner = makeAddr("owner");
        manager = makeAddr("manager");
        userAlice = makeAddr("userAlice");
        userBob = makeAddr("userBob");
        userCharlie = makeAddr("userCharlie");

        // Deploy mock tokens
        token1 = new MockERC20("Token1", "TKN1");
        token2 = new MockERC20("Token2", "TKN2");
        token3 = new MockERC20("Token3", "TKN3");

        // Deploy Distributor
        distributor = new Distributor(owner, manager);

        // Grant MANAGER_ROLE to manager
        bytes32 managerRole = distributor.MANAGER_ROLE();
        vm.prank(owner);
        distributor.grantRole(managerRole, manager);

        // Fund distributor with tokens
        token1.mint(address(distributor), _tokens(1_000_000));
        token2.mint(address(distributor), _tokens(1_000_000));
        token3.mint(address(distributor), _tokens(1_000_000));

        // Deploy MerkleTree helper
        merkleTree = new MerkleTree();
    }

    function _tokens(uint256 amount) internal pure returns (uint256) {
        return amount * 1e18;
    }

    // ==================== Merkle Tree Helpers ====================

    /// @notice Creates leaf data for a claim (matches Distributor contract format)
    function _leafData(address recipient, address token, uint256 amount) internal pure returns (bytes memory) {
        return abi.encode(recipient, token, amount);
    }
}
