// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import { Test, console } from "forge-std/Test.sol";

import { IAccessControl } from "@openzeppelin/contracts/access/IAccessControl.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { Constants } from "test/utils/Constants.t.sol";

abstract contract BaseTest is Test, Constants {
    /// VARIABLES ///
    struct Fork {
        uint256 forkId;
        uint256 blockNumber;
    }

    uint256 internal _MAX_UINT256 = type(uint256).max;
    /// @dev Hash of the `_PROXY_INITCODE`.
    /// Equivalent to `keccak256(abi.encodePacked(hex"67363d3d37363d34f03d5260086018f3"))`.
    bytes32 internal constant _PROXY_INITCODE_HASH = 0x21c35dbe1b344a2488cf3321d6ce542f8e9f305544ff09e4993a62319a497c1f;

    mapping(string => address) public users;
    mapping(string => Fork) public forks;

    /// TEST CONTRACTS ///
    ERC20 internal _usdc;
    ERC20 internal _dai;

    /// SETUP FUNCTION ///
    function setUp() public virtual { }

    /// HELPERS ///

    /// @dev Generates a user, labels its address, and funds it with test assets.
    /// @param name The name of the user.
    /// @return The address of the user.
    function createUser(string memory name) public returns (address payable) {
        address payable user = payable(makeAddr(name));
        if (users[name] != address(0)) {
            console.log("User ", name, " already exists");
            return user;
        }
        vm.deal({ account: user, newBalance: 100 ether });
        users[name] = user;
        return user;
    }

    /// @dev Approves a list of contracts to spend the maximum of funds for a user.
    /// @param contractAddresses The list of contracts to approve.
    /// @param userAddresses The users to approve the contracts for.
    function _approveProtocol(address[] calldata contractAddresses, address[] calldata userAddresses) internal {
        for (uint256 i = 0; i < contractAddresses.length; i++) {
            for (uint256 n = 0; n < userAddresses.length; n++) {
                changePrank(userAddresses[n]);
                IERC20(contractAddresses[i]).approve(userAddresses[n], _MAX_UINT256);
            }
        }
        vm.stopPrank();
    }

    /// FORKING UTILS ///

    /// @dev Creates a fork at a given block.
    /// @param network The name of the network, matches an entry in the foundry.toml
    /// @param blockNumber The block number to fork from.
    /// @return The fork id.
    function forkNetworkAt(string memory network, uint256 blockNumber) public returns (uint256) {
        string memory rpcURL = vm.rpcUrl(network);
        uint256 forkId = vm.createSelectFork(rpcURL, blockNumber);
        forks[network] = Fork({ forkId: forkId, blockNumber: blockNumber });
        console.log("Started fork ", network, " at block ", block.number);
        console.log("with id", forkId);
        return forkId;
    }

    /// @dev Creates a fork at the latest block number.
    /// @param network The name of the network, matches an entry in the foundry.toml
    /// @return The fork id.
    function forkNetwork(string memory network) public returns (uint256) {
        string memory rpcURL = vm.rpcUrl(network);
        uint256 forkId = vm.createSelectFork(rpcURL);
        forks[network] = Fork({ forkId: forkId, blockNumber: block.number });
        console.log("Started fork ", network, "at block ", block.number);
        console.log("with id", forkId);
        return forkId;
    }

    function selectNamedFork(string memory network) public {
        vm.selectFork(forks[network].forkId);
    }

    /// @notice Airdrop an asset to an address with a given amount
    /// @dev This function should only be used for ERC20s that have totalSupply storage slot
    /// @param _asset address of the asset to airdrop
    /// @param _to address to airdrop to
    /// @param _amount amount to airdrop
    function airdrop(IERC20 _asset, address _to, uint256 _amount, bool adjust) public {
        uint256 balanceBefore = _asset.balanceOf(_to);
        deal(address(_asset), _to, balanceBefore + _amount, adjust);
    }

    function airdrop(IERC20 _asset, address _to, uint256 _amount) public {
        airdrop(_asset, _to, _amount, true);
    }

    /// @notice Take an asset away from an address with a given amount
    /// @param _asset address of the asset to take away
    /// @param _from address to take away from
    /// @param _amount amount to take away
    function takeAway(IERC20 _asset, address _from, uint256 _amount) public {
        uint256 balanceBefore = _asset.balanceOf(_from);
        if (balanceBefore < _amount) {
            revert("BaseTest:takeAway(): Insufficient balance");
        }
        deal(address(_asset), _from, balanceBefore - _amount);
    }

    function _formatAccessControlError(address addr, bytes32 role) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, addr, role);
        // OpenZeppelin v4 used string error messages instead of revert error selectors
        // return abi.encodePacked(
        //     "AccessControl: account ",
        //     Strings.toHexString(addr),
        //     " is missing role ",
        //     Strings.toHexString(uint256(role), 32)
        // );
    }

    function assertEq(uint64[] memory a, uint64[] memory b) public {
        if (a.length != b.length) {
            revert("BaseTest:assertEq(): Arrays are not the same length");
        }
        for (uint256 i = 0; i < a.length; i++) {
            if (a[i] != b[i]) {
                revert("BaseTest:assertEq(): Arrays are not equal");
            }
        }
    }

    /// @dev Returns the deterministic address for `salt` with `deployer`.
    function _predictDeterministicAddress(bytes32 salt, address deployer) internal pure returns (address deployed) {
        /// @solidity memory-safe-assembly
        // solhint-disable-next-line no-inline-assembly
        assembly {
            let m := mload(0x40) // Cache the free memory pointer.
            mstore(0x00, deployer) // Store `deployer`.
            mstore8(0x0b, 0xff) // Store the prefix.
            mstore(0x20, salt) // Store the salt.
            mstore(0x40, _PROXY_INITCODE_HASH) // Store the bytecode hash.

            mstore(0x14, keccak256(0x0b, 0x55)) // Store the proxy's address.
            mstore(0x40, m) // Restore the free memory pointer.
            // 0xd6 = 0xc0 (short RLP prefix) + 0x16 (length of: 0x94 ++ proxy ++ 0x01).
            // 0x94 = 0x80 + 0x14 (0x14 = the length of an address, 20 bytes, in hex).
            mstore(0x00, 0xd694)
            mstore8(0x34, 0x01) // Nonce of the proxy contract (1).
            deployed := and(keccak256(0x1e, 0x17), 0xffffffffffffffffffffffffffffffffffffffff)
        }
    }
}
