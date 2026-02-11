// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.22;

import { Script, console2 } from "forge-std/Script.sol";
import { BoringVault } from "src/base/BoringVault.sol";
import { TellerWithMultiAssetSupport } from "src/base/Roles/TellerWithMultiAssetSupport.sol";
import { CrossChainTellerBase } from "src/base/Roles/CrossChain/CrossChainTellerBase.sol";
import { MultiChainLayerZeroTellerWithMultiAssetSupport } from
    "src/base/Roles/CrossChain/MultiChainLayerZeroTellerWithMultiAssetSupport.sol";
import { AccountantWithRateProviders } from "src/base/Roles/AccountantWithRateProviders.sol";
import { RolesAuthority, Authority } from "@solmate/auth/authorities/RolesAuthority.sol";
import { AtomicQueue } from "src/atomic-queue/AtomicQueue.sol";
import { AtomicSolverV3 } from "src/atomic-queue/AtomicSolverV3.sol";
import { ERC20 } from "@solmate/tokens/ERC20.sol";
import { SafeTransferLib } from "@solmate/utils/SafeTransferLib.sol";
import { FixedPointMathLib } from "@solmate/utils/FixedPointMathLib.sol";

contract DeployNucleusCrossChain is Script {
    using SafeTransferLib for ERC20;
    using FixedPointMathLib for uint256;

    // Role definitions
    uint8 public constant ADMIN_ROLE = 1;
    uint8 public constant MANAGER_ROLE = 2;
    uint8 public constant MINTER_ROLE = 7;
    uint8 public constant BURNER_ROLE = 8;
    uint8 public constant SOLVER_ROLE = 9;
    uint8 public constant QUEUE_ROLE = 10;
    uint8 public constant CAN_SOLVE_ROLE = 11;

    // LayerZero Endpoint IDs
    uint32 public constant SEPOLIA_EID = 40_161;
    uint32 public constant OP_SEPOLIA_EID = 40_232;

    // LayerZero Endpoint Address (same on both testnets)
    address public constant LZ_ENDPOINT = 0x6EDCE65403992e310A62460808c4b910D972f10f;

    // Token addresses (Sepolia and OP Sepolia)
    address public constant WETH_SEPOLIA = 0xfFf9976782d46CC05630D1f6eBAb18b2324d6B14;
    address public constant USDC_SEPOLIA = 0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238;
    address public constant WETH_OP_SEPOLIA = 0x4200000000000000000000000000000000000006;
    address public constant USDC_OP_SEPOLIA = 0x5fd84259d66Cd46123540766Be93DFE6D43130D7;

    // Deployment addresses
    address public owner;
    address public hexTrust;
    address public solver;
    address public exchangeRateBot;

    // L1 Contracts (Sepolia)
    BoringVault public l1Vault;
    MultiChainLayerZeroTellerWithMultiAssetSupport public l1Teller;
    AccountantWithRateProviders public l1Accountant;
    RolesAuthority public l1Authority;
    AtomicQueue public l1AtomicQueue;
    AtomicSolverV3 public l1AtomicSolver;

    // L2 Contracts (OP Sepolia)
    BoringVault public l2Vault;
    MultiChainLayerZeroTellerWithMultiAssetSupport public l2Teller;
    AccountantWithRateProviders public l2Accountant;
    RolesAuthority public l2Authority;
    AtomicQueue public l2AtomicQueue;
    AtomicSolverV3 public l2AtomicSolver;

    function run() external {
        // Read private key
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        // Set addresses
        owner = vm.addr(deployerPrivateKey);
        hexTrust = vm.envAddress("HEXTRUST_ADDRESS");
        solver = vm.envAddress("SOLVER_ADDRESS");
        exchangeRateBot = vm.envAddress("EXCHANGE_RATE_BOT_ADDRESS");

        console2.log("=== Deployment Configuration ===");
        console2.log("Owner:", owner);
        console2.log("HexTrust Manager:", hexTrust);
        console2.log("Solver:", solver);
        console2.log("Exchange Rate Bot:", exchangeRateBot);

        // Deploy on Sepolia
        console2.log("\n=== Deploying on Sepolia ===");
        _deploySepolia(deployerPrivateKey);

        // Deploy on OP Sepolia
        console2.log("\n=== Deploying on OP Sepolia ===");
        _deployOPSepolia(deployerPrivateKey);

        // Connect cross-chain
        console2.log("\n=== Connecting Cross-Chain ===");
        _connectCrossChain(deployerPrivateKey);

        // Log deployment addresses
        _logDeploymentAddresses();
    }

    function _deploySepolia(uint256 deployerPrivateKey) internal {
        // Switch to Sepolia
        vm.createSelectFork(vm.envString("SEPOLIA_RPC_URL"));
        vm.startBroadcast(deployerPrivateKey);

        // Deploy L1 Vault
        l1Vault = new BoringVault(owner, "Nucleus Vault Sepolia", "nvSEP", 18);
        console2.log("L1 Vault deployed:", address(l1Vault));

        // Deploy L1 Accountant
        l1Accountant = new AccountantWithRateProviders(
            owner,
            address(l1Vault),
            owner, // payoutAddress
            1e18, // startingExchangeRate (1:1)
            WETH_SEPOLIA, // base asset
            1.01e4, // allowedExchangeRateChangeUpper (1% up)
            0.99e4, // allowedExchangeRateChangeLower (1% down)
            24 hours, // minimumUpdateDelayInSeconds
            100 // managementFee (1%)
        );
        console2.log("L1 Accountant deployed:", address(l1Accountant));

        // Deploy L1 Authority
        l1Authority = new RolesAuthority(owner, Authority(address(0)));
        console2.log("L1 Authority deployed:", address(l1Authority));

        // Deploy L1 Teller
        l1Teller = new MultiChainLayerZeroTellerWithMultiAssetSupport(
            owner, address(l1Vault), address(l1Accountant), LZ_ENDPOINT
        );
        console2.log("L1 Teller deployed:", address(l1Teller));

        // Deploy L1 AtomicQueue
        l1AtomicQueue = new AtomicQueue(address(l1Accountant), owner, l1Authority);
        console2.log("L1 AtomicQueue deployed:", address(l1AtomicQueue));

        // Deploy L1 AtomicSolver
        l1AtomicSolver = new AtomicSolverV3(owner, l1Authority);
        console2.log("L1 AtomicSolver deployed:", address(l1AtomicSolver));

        // Setup L1 permissions
        _setupL1Permissions();

        // Add supported assets on L1
        _addL1Assets();

        vm.stopBroadcast();
    }

    function _deployOPSepolia(uint256 deployerPrivateKey) internal {
        // Switch to OP Sepolia
        vm.createSelectFork(vm.envString("OP_SEPOLIA_RPC_URL"));
        vm.startBroadcast(deployerPrivateKey);

        // Deploy L2 Vault
        l2Vault = new BoringVault(owner, "Nucleus Vault OP Sepolia", "nvOPS", 18);
        console2.log("L2 Vault deployed:", address(l2Vault));

        // Deploy L2 Accountant
        l2Accountant = new AccountantWithRateProviders(
            owner,
            address(l2Vault),
            owner, // payoutAddress
            1e18, // startingExchangeRate (1:1)
            WETH_OP_SEPOLIA, // base asset
            1.01e4, // allowedExchangeRateChangeUpper (1% up)
            0.99e4, // allowedExchangeRateChangeLower (1% down)
            24 hours, // minimumUpdateDelayInSeconds
            100 // managementFee (1%)
        );
        console2.log("L2 Accountant deployed:", address(l2Accountant));

        // Deploy L2 Authority
        l2Authority = new RolesAuthority(owner, Authority(address(0)));
        console2.log("L2 Authority deployed:", address(l2Authority));

        // Deploy L2 Teller
        l2Teller = new MultiChainLayerZeroTellerWithMultiAssetSupport(
            owner, address(l2Vault), address(l2Accountant), LZ_ENDPOINT
        );
        console2.log("L2 Teller deployed:", address(l2Teller));

        // Deploy L2 AtomicQueue
        l2AtomicQueue = new AtomicQueue(address(l2Accountant), owner, l2Authority);
        console2.log("L2 AtomicQueue deployed:", address(l2AtomicQueue));

        // Deploy L2 AtomicSolver
        l2AtomicSolver = new AtomicSolverV3(owner, l2Authority);
        console2.log("L2 AtomicSolver deployed:", address(l2AtomicSolver));

        // Setup L2 permissions
        _setupL2Permissions();

        // Add supported assets on L2
        _addL2Assets();

        vm.stopBroadcast();
    }

    function _connectCrossChain(uint256 deployerPrivateKey) internal {
        // Store deployed addresses
        address l1TellerAddr = address(l1Teller);
        address l2TellerAddr = address(l2Teller);

        // Connect L1 to L2
        console2.log("Connecting L1 Teller to L2...");
        vm.createSelectFork(vm.envString("SEPOLIA_RPC_URL"));
        vm.startBroadcast(deployerPrivateKey);

        // Recreate L1 teller instance
        MultiChainLayerZeroTellerWithMultiAssetSupport l1TellerInstance =
            MultiChainLayerZeroTellerWithMultiAssetSupport(l1TellerAddr);

        // Set peer on L1 (points to L2)
        l1TellerInstance.setPeer(OP_SEPOLIA_EID, _addressToBytes32(l2TellerAddr));

        // Add OP Sepolia as allowed chain
        l1TellerInstance.addChain(
            OP_SEPOLIA_EID, // chainSelector
            true, // allowMessagesFrom
            true, // allowMessagesTo
            l2TellerAddr, // targetTeller
            300_000, // messageGasLimit
            200_000 // messageGasMin
        );

        vm.stopBroadcast();

        // Connect L2 to L1
        console2.log("Connecting L2 Teller to L1...");
        vm.createSelectFork(vm.envString("OP_SEPOLIA_RPC_URL"));
        vm.startBroadcast(deployerPrivateKey);

        // Recreate L2 teller instance
        MultiChainLayerZeroTellerWithMultiAssetSupport l2TellerInstance =
            MultiChainLayerZeroTellerWithMultiAssetSupport(l2TellerAddr);

        // Set peer on L2 (points to L1)
        l2TellerInstance.setPeer(SEPOLIA_EID, _addressToBytes32(l1TellerAddr));

        // Add Sepolia as allowed chain
        l2TellerInstance.addChain(
            SEPOLIA_EID, // chainSelector
            true, // allowMessagesFrom
            true, // allowMessagesTo
            l1TellerAddr, // targetTeller
            300_000, // messageGasLimit
            200_000 // messageGasMin
        );

        vm.stopBroadcast();
    }

    function _setupL1Permissions() internal {
        // Set authorities
        l1Vault.setAuthority(l1Authority);
        l1Accountant.setAuthority(l1Authority);
        l1Teller.setAuthority(l1Authority);

        // Setup capabilities
        l1Authority.setRoleCapability(MINTER_ROLE, address(l1Vault), BoringVault.enter.selector, true);
        l1Authority.setRoleCapability(BURNER_ROLE, address(l1Vault), BoringVault.exit.selector, true);
        l1Authority.setRoleCapability(
            MANAGER_ROLE, address(l1Vault), bytes4(keccak256(abi.encodePacked("manage(address,bytes,uint256)"))), true
        );
        l1Authority.setRoleCapability(
            SOLVER_ROLE, address(l1Teller), TellerWithMultiAssetSupport.bulkWithdraw.selector, true
        );
        l1Authority.setRoleCapability(CAN_SOLVE_ROLE, address(l1AtomicSolver), AtomicSolverV3.p2pSolve.selector, true);
        l1Authority.setRoleCapability(QUEUE_ROLE, address(l1AtomicSolver), AtomicSolverV3.finishSolve.selector, true);

        // Set public capabilities
        l1Authority.setPublicCapability(address(l1Teller), TellerWithMultiAssetSupport.deposit.selector, true);
        l1Authority.setPublicCapability(address(l1Teller), TellerWithMultiAssetSupport.depositWithPermit.selector, true);
        l1Authority.setPublicCapability(address(l1Teller), CrossChainTellerBase.bridge.selector, true);
        l1Authority.setPublicCapability(address(l1Teller), CrossChainTellerBase.depositAndBridge.selector, true);
        l1Authority.setPublicCapability(address(l1Teller), CrossChainTellerBase.previewFee.selector, true);

        // Assign roles
        l1Authority.setUserRole(hexTrust, MANAGER_ROLE, true);
        l1Authority.setUserRole(address(l1Teller), MINTER_ROLE, true);
        l1Authority.setUserRole(address(l1Teller), BURNER_ROLE, true);
        l1Authority.setUserRole(address(l1AtomicSolver), SOLVER_ROLE, true);
        l1Authority.setUserRole(address(l1AtomicQueue), QUEUE_ROLE, true);
        l1Authority.setUserRole(solver, CAN_SOLVE_ROLE, true);
        l1Authority.setUserRole(exchangeRateBot, ADMIN_ROLE, true);
    }

    function _setupL2Permissions() internal {
        // Set authorities
        l2Vault.setAuthority(l2Authority);
        l2Accountant.setAuthority(l2Authority);
        l2Teller.setAuthority(l2Authority);

        // Setup capabilities (same as L1)
        l2Authority.setRoleCapability(MINTER_ROLE, address(l2Vault), BoringVault.enter.selector, true);
        l2Authority.setRoleCapability(BURNER_ROLE, address(l2Vault), BoringVault.exit.selector, true);
        l2Authority.setRoleCapability(
            MANAGER_ROLE, address(l2Vault), bytes4(keccak256(abi.encodePacked("manage(address,bytes,uint256)"))), true
        );
        l2Authority.setRoleCapability(
            SOLVER_ROLE, address(l2Teller), TellerWithMultiAssetSupport.bulkWithdraw.selector, true
        );
        l2Authority.setRoleCapability(CAN_SOLVE_ROLE, address(l2AtomicSolver), AtomicSolverV3.p2pSolve.selector, true);
        l2Authority.setRoleCapability(QUEUE_ROLE, address(l2AtomicSolver), AtomicSolverV3.finishSolve.selector, true);

        // Set public capabilities
        l2Authority.setPublicCapability(address(l2Teller), TellerWithMultiAssetSupport.deposit.selector, true);
        l2Authority.setPublicCapability(address(l2Teller), TellerWithMultiAssetSupport.depositWithPermit.selector, true);
        l2Authority.setPublicCapability(address(l2Teller), CrossChainTellerBase.bridge.selector, true);
        l2Authority.setPublicCapability(address(l2Teller), CrossChainTellerBase.depositAndBridge.selector, true);
        l2Authority.setPublicCapability(address(l2Teller), CrossChainTellerBase.previewFee.selector, true);

        // Assign roles
        l2Authority.setUserRole(hexTrust, MANAGER_ROLE, true);
        l2Authority.setUserRole(address(l2Teller), MINTER_ROLE, true);
        l2Authority.setUserRole(address(l2Teller), BURNER_ROLE, true);
        l2Authority.setUserRole(address(l2AtomicSolver), SOLVER_ROLE, true);
        l2Authority.setUserRole(address(l2AtomicQueue), QUEUE_ROLE, true);
        l2Authority.setUserRole(solver, CAN_SOLVE_ROLE, true);
        l2Authority.setUserRole(exchangeRateBot, ADMIN_ROLE, true);
    }

    function _addL1Assets() internal {
        // Add WETH
        l1Teller.addAsset(ERC20(WETH_SEPOLIA));
        l1Accountant.setRateProviderData(ERC20(WETH_SEPOLIA), true, address(0));
        console2.log("Added WETH to L1 Teller");

        // Add USDC
        l1Teller.addAsset(ERC20(USDC_SEPOLIA));
        l1Accountant.setRateProviderData(ERC20(USDC_SEPOLIA), false, address(0));
        console2.log("Added USDC to L1 Teller");
    }

    function _addL2Assets() internal {
        // Add WETH
        l2Teller.addAsset(ERC20(WETH_OP_SEPOLIA));
        l2Accountant.setRateProviderData(ERC20(WETH_OP_SEPOLIA), true, address(0));
        console2.log("Added WETH to L2 Teller");

        // Add USDC
        l2Teller.addAsset(ERC20(USDC_OP_SEPOLIA));
        l2Accountant.setRateProviderData(ERC20(USDC_OP_SEPOLIA), false, address(0));
        console2.log("Added USDC to L2 Teller");
    }

    function _addressToBytes32(address _addr) internal pure returns (bytes32) {
        return bytes32(uint256(uint160(_addr)));
    }

    function _logDeploymentAddresses() internal view {
        console2.log("\n=== Deployment Summary ===");
        console2.log("\nSepolia Contracts:");
        console2.log("L1 Vault:", address(l1Vault));
        console2.log("L1 Teller:", address(l1Teller));
        console2.log("L1 Accountant:", address(l1Accountant));
        console2.log("L1 Authority:", address(l1Authority));
        console2.log("L1 AtomicQueue:", address(l1AtomicQueue));
        console2.log("L1 AtomicSolver:", address(l1AtomicSolver));

        console2.log("\nOP Sepolia Contracts:");
        console2.log("L2 Vault:", address(l2Vault));
        console2.log("L2 Teller:", address(l2Teller));
        console2.log("L2 Accountant:", address(l2Accountant));
        console2.log("L2 Authority:", address(l2Authority));
        console2.log("L2 AtomicQueue:", address(l2AtomicQueue));
        console2.log("L2 AtomicSolver:", address(l2AtomicSolver));

        console2.log("\nCross-Chain Configuration:");
        console2.log("L1 Teller peer (L2):", address(l2Teller));
        console2.log("L2 Teller peer (L1):", address(l1Teller));
        console2.log("LayerZero Endpoint:", LZ_ENDPOINT);
        console2.log("Sepolia EID:", SEPOLIA_EID);
        console2.log("OP Sepolia EID:", OP_SEPOLIA_EID);
    }
}
