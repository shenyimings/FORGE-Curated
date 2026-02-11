// SPDX-License-Identifier: MIT
pragma solidity >=0.8.19;

import { Script } from "forge-std/Script.sol";

abstract contract BaseScript is Script {
    /// @dev Included to enable compilation of the script without a $MNEMONIC environment variable.
    string internal constant TEST_MNEMONIC = "test test test test test test test test test test test junk";

    /// @dev Needed for the deterministic deployments.
    bytes32 internal constant ZERO_SALT = bytes32(0);

    /// @dev The address of the contract deployer.
    address internal deployer;

    /// @dev Used to derive the deployer's address.
    string internal mnemonic;

    /// @dev Used to toggle between mnemonic and ledger handling.
    bool internal ledger;

    constructor() {
        mnemonic = vm.envOr("MNEMONIC", TEST_MNEMONIC);
        (deployer,) = deriveRememberKey({ mnemonic: mnemonic, index: 0 });
        ledger = vm.envOr("CALL_WITH_LEDGER", false);
    }

    modifier broadcaster() {
        if (ledger) {
            deployer = msg.sender;
        }

        vm.startBroadcast(deployer);
        _;
        vm.stopBroadcast();
    }
}
