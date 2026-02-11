// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.22;

import { RolesAuthority } from "@solmate/auth/authorities/RolesAuthority.sol";
import { BoringVault } from "src/base/BoringVault.sol";
import { TellerWithMultiAssetSupport } from "src/base/Roles/TellerWithMultiAssetSupport.sol";
import { AtomicQueue } from "src/atomic-queue/AtomicQueue.sol";
import { BaseScript } from "./Base.s.sol";
import { ConfigReader } from "./ConfigReader.s.sol";

contract ConfigureAtomicRoles is BaseScript {
    // Role constants
    uint8 public constant SOLVER_ROLE = 9;
    uint8 public constant QUEUE_ROLE = 10;

    // Addresses (will be overridden by deployWithConfig)
    address public rolesAuthority;
    address public boringVault;
    address public teller;
    address public atomicQueue;
    address public atomicSolver;

    function run() public broadcast {
        _configure();
    }

    function deployWithConfig(ConfigReader.Config memory config) public broadcast returns (address) {
        // Set addresses from config
        rolesAuthority = config.rolesAuthority;
        boringVault = config.boringVault;
        teller = config.teller;
        atomicQueue = config.atomicQueue;
        atomicSolver = config.atomicSolver;

        // Run configuration
        _configure();
        return address(0);
    }

    function _configure() internal {
        RolesAuthority authority = RolesAuthority(rolesAuthority);

        // === ATOMIC QUEUE SETUP ===
        authority.setUserRole(atomicQueue, QUEUE_ROLE, true);
        authority.setRoleCapability(QUEUE_ROLE, teller, TellerWithMultiAssetSupport.bulkWithdraw.selector, true);

        // === ATOMIC SOLVER SETUP ===
        authority.setUserRole(atomicSolver, SOLVER_ROLE, true);

        // Grant manage permissions to SOLVER_ROLE
        authority.setRoleCapability(SOLVER_ROLE, boringVault, bytes4(keccak256("manage(address,bytes,uint256)")), true);
        authority.setRoleCapability(
            SOLVER_ROLE, boringVault, bytes4(keccak256("manage(address[],bytes[],uint256[])")), true
        );

        // === CROSS-CONTRACT PERMISSIONS ===
        // Allow AtomicSolver to call solve on AtomicQueue
        authority.setPublicCapability(
            atomicQueue, bytes4(keccak256("solve(address,address,address[],bytes,address)")), true
        );

        // Allow AtomicQueue to call finishSolve on AtomicSolver
        authority.setPublicCapability(
            atomicSolver, bytes4(keccak256("finishSolve(bytes,address,address,address,uint256,uint256)")), true
        );

        // Allow AtomicSolver to call bulkWithdraw on Teller (for redeem solve)
        authority.setPublicCapability(teller, TellerWithMultiAssetSupport.bulkWithdraw.selector, true);
    }
}
