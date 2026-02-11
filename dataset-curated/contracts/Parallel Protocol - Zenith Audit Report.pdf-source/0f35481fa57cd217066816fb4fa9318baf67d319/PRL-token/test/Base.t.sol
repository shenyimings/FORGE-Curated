// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import { console2 } from "@forge-std/console2.sol";
import { Test, Vm } from "@forge-std/Test.sol";

import { ErrorsLib } from "contracts/libraries/ErrorsLib.sol";

import { SendParam } from "contracts/layerZero/interfaces/IOFT.sol";
import { MessagingFee, MessagingReceipt } from "contracts/layerZero/interfaces/IOFT.sol";

import "./helpers/Deploys.sol";
import "./helpers/Defaults.sol";
import "./helpers/Assertions.sol";
import "./helpers/Utils.sol";
import "./helpers/SigUtils.sol";

/// @notice Base test contract with common logic needed by all tests.
abstract contract Base_Test is Test, Deploys, Assertions, Defaults, Utils {
    //----------------------------------------
    // Set-up
    //----------------------------------------
    function setUp() public virtual override {
        // Deploy MIMO token contract.
        mimo = _deployERC20Mock("Mimo", "Mimo", 18);
        vm.label({ account: address(mimo), newLabel: "Mimo" });

        // Create users for testing.
        users = Users({
            owner: _createUser("Owner", true),
            alice: _createUser("Alice", true),
            bob: _createUser("Bob", true),
            hacker: _createUser("Hacker", true)
        });
    }

    /// @dev Generates a user, labels its address, and funds it with test assets.
    function _createUser(string memory name, bool setTokenBalance) internal returns (Vm.Wallet memory user) {
        user = vm.createWallet(name);
        vm.deal({ account: user.addr, newBalance: INITIAL_BALANCE });
        if (setTokenBalance) {
            mimo.mint(user.addr, INITIAL_BALANCE);
        }
    }

    function _signPermitData(
        uint256 privateKey,
        address spender,
        uint256 amount,
        address token
    )
        internal
        view
        returns (uint256 deadline, uint8 v, bytes32 r, bytes32 s)
    {
        address owner = vm.addr(privateKey);
        deadline = block.timestamp + 1 days;
        SigUtils.Permit memory permit = SigUtils.Permit({
            owner: owner,
            spender: spender,
            value: amount,
            nonce: IERC20Permit(token).nonces(owner),
            deadline: deadline
        });

        bytes32 digest = sigUtils.getTypedDataHash(permit);
        (v, r, s) = vm.sign(privateKey, digest);
    }
}
