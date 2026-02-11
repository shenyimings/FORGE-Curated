// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import { Script } from "forge-std/Script.sol";

abstract contract BaseScript is Script {
    /// @dev Included to enable compilation of the script without a $MNEMONIC environment variable.
    string internal constant TEST_MNEMONIC = "test test test test test test test test test test test junk";

    /// @dev Needed for the deterministic deployments.
    bytes32 internal constant ZERO_SALT = bytes32(0);

    /// @dev The address of the transaction broadcaster.
    address internal broadcaster;

    /// @dev Private key used for broadcasting transactions when provided via $DEPLOYER_PRIVATE_KEY.
    uint256 internal broadcasterKey;

    /// @dev Used to derive the broadcaster's address if no explicit key/address is provided.
    string internal mnemonic;

    /// @dev Initializes the transaction broadcaster like this:
    ///
    /// - If $DEPLOYER_PRIVATE_KEY is defined, derive the broadcaster from it.
    /// - Else if $ETH_FROM is defined, use the provided address.
    /// - Otherwise, derive the broadcaster address from $MNEMONIC.
    /// - If $MNEMONIC is not defined, default to a test mnemonic.
    ///
    /// The use case for $ETH_FROM is to specify the broadcaster key and its address via the command line.
    constructor() {
        uint256 key = vm.envOr({ name: "DEPLOYER_PRIVATE_KEY", defaultValue: uint256(0) });
        if (key != 0) {
            broadcasterKey = key;
            broadcaster = vm.addr(key);
        } else {
            address from = vm.envOr({ name: "ETH_FROM", defaultValue: address(0) });
            if (from != address(0)) {
                broadcaster = from;
            } else {
                mnemonic = vm.envOr({ name: "MNEMONIC", defaultValue: TEST_MNEMONIC });
                (broadcaster,) = deriveRememberKey({ mnemonic: mnemonic, index: 0 });
            }
        }
    }

    modifier broadcast() {
        _startBroadcast();
        _;
        _stopBroadcast();
    }

    function _startBroadcast() internal {
        if (broadcasterKey != 0) {
            vm.startBroadcast(broadcasterKey);
        } else {
            vm.startBroadcast(broadcaster);
        }
    }

    function _stopBroadcast() internal {
        vm.stopBroadcast();
    }
}
