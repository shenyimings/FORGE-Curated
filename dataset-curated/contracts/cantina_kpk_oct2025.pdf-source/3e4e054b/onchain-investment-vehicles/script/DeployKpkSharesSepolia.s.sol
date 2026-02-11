// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Script, console} from "forge-std/Script.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {KpkShares} from "../src/kpkShares.sol";
import {UnsafeUpgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";

/**
 * @title DeployKpkSharesSepolia
 * @notice Deployment script for kpkShares contract using UUPS proxy pattern on Sepolia testnet
 * @dev This script deploys the kpkShares implementation and a UUPS proxy
 *      Constructor parameters are loaded from a JSON file in the script folder
 *
 * Usage:
 *   forge script script/DeployKpkSharesSepolia.s.sol:DeployKpkSharesSepolia \
 *     --rpc-url $SEPOLIA_RPC_URL \
 *     --broadcast \
 *     --verify \
 *     --sig "run(string)" "vault1"
 *
 */
contract DeployKpkSharesSepolia is Script {
    using stdJson for string;

    /// @notice Sepolia chain ID
    uint256 private constant SEPOLIA_CHAIN_ID = 11155111;

    /// @notice Default JSON file path
    string private constant VAULTS_JSON_PATH = "script/vaults.json";

    /// @notice OPERATOR role identifier
    bytes32 private constant OPERATOR = keccak256("OPERATOR");

    /// @notice DEFAULT_ADMIN_ROLE identifier
    bytes32 private constant DEFAULT_ADMIN_ROLE = 0x00;

    /**
     * @notice Default run function - shows usage information
     * @dev This function is called when no arguments are provided
     */
    function run() external view {
        // Read JSON configuration
        string memory json = vm.readFile(VAULTS_JSON_PATH);

        console.log("==========================================");
        console.log("kpkShares Sepolia Deployment Script");
        console.log("==========================================");
        console.log("Usage:");
        console.log("  forge script script/DeployKpkSharesSepolia.s.sol:DeployKpkSharesSepolia \\");
        console.log("    --rpc-url $SEPOLIA_RPC_URL \\");
        console.log("    --broadcast \\");
        console.log("    --verify \\");
        console.log("    --sig \"run(string)\" \"vaultName\"");
        console.log("");
        console.log("Available vaults:");

        // List available vaults
        string memory vaultsPath = ".sepolia.chain.vaults";
        for (uint256 i = 0; i < 100; i++) {
            string memory currentVaultPath = string.concat(vaultsPath, "[", vm.toString(i), "]");
            if (!json.keyExists(currentVaultPath)) {
                break; // End of array
            }
            string memory vaultName = json.readString(string.concat(currentVaultPath, ".vaultName"));
            console.log("  -", vaultName);
        }
        console.log("==========================================");
        revert("Please specify a vault name using --sig \"run(string)\" \"vaultName\"");
    }

    /**
     * @notice Deploy a specific vault from JSON configuration
     * @param vaultName Name of the vault to deploy (from JSON). Must be non-empty
     */
    function run(string memory vaultName) external {
        // Verify we're on Sepolia
        require(block.chainid == SEPOLIA_CHAIN_ID, "This script is only for Sepolia testnet");

        // Require vault name to be specified
        require(bytes(vaultName).length > 0, "Vault name must be specified");

        // Read JSON configuration
        string memory json = vm.readFile(VAULTS_JSON_PATH);

        // Verify chain ID matches
        uint256 chainId = json.readUint(".sepolia.chain.id");
        require(chainId == SEPOLIA_CHAIN_ID, "Chain ID in JSON does not match Sepolia");

        // Deploy the specified vault
        _deployVault(json, vaultName);
    }

    /**
     * @notice Deploy a specific vault from JSON configuration
     * @param json The JSON string containing vault configurations
     * @param vaultName The name of the vault to deploy
     */
    function _deployVault(string memory json, string memory vaultName) internal {
        // Find vault in the sepolia.chain.vaults array
        uint256 vaultIndex = _findVaultIndex(json, vaultName);
        string memory vaultPath = string.concat(".sepolia.chain.vaults[", vm.toString(vaultIndex), "]");

        // Parse and validate parameters
        KpkShares.ConstructorParams memory params = _parseVaultParams(json, vaultPath);
        _validateParams(params);

        console.log("==========================================");
        console.log("Deploying kpkShares Vault:", vaultName);
        console.log("==========================================");

        // Deploy the contract
        address proxy = _deployContract(params);

        // Setup roles
        address operator = json.readAddress(string.concat(vaultPath, ".operator"));
        address admin = json.readAddress(string.concat(vaultPath, ".admin"));
        _setupRoles(KpkShares(proxy), operator, admin);

        vm.stopBroadcast();

        // Log deployment information
        _logDeployment(vaultName, proxy, params, admin, operator);
    }

    /**
     * @notice Find the index of a vault in the vaults array
     * @param json The JSON string
     * @param vaultName The name of the vault to find
     * @return index The index of the vault in the array
     */
    function _findVaultIndex(string memory json, string memory vaultName) internal view returns (uint256 index) {
        // Read the vaults array
        string memory vaultsPath = ".sepolia.chain.vaults";
        require(json.keyExists(vaultsPath), "Vaults array not found in JSON");

        // Iterate through vaults to find matching vaultName
        // Note: stdJson doesn't have a direct way to get array length, so we'll try indices until we find it
        for (uint256 i = 0; i < 100; i++) {
            string memory currentVaultPath = string.concat(vaultsPath, "[", vm.toString(i), "]");
            if (!json.keyExists(currentVaultPath)) {
                break; // End of array
            }

            string memory currentVaultName = json.readString(string.concat(currentVaultPath, ".vaultName"));
            if (keccak256(bytes(currentVaultName)) == keccak256(bytes(vaultName))) {
                return i;
            }
        }

        revert("Vault not found in JSON configuration");
    }

    /**
     * @notice Parse vault parameters from JSON
     * @param json The JSON string
     * @param vaultPath The path to the vault in JSON
     * @return params The parsed constructor parameters
     */
    function _parseVaultParams(string memory json, string memory vaultPath)
        internal
        view
        returns (KpkShares.ConstructorParams memory params)
    {
        params.asset = json.readAddress(string.concat(vaultPath, ".asset"));
        params.name = json.readString(string.concat(vaultPath, ".name"));
        params.symbol = json.readString(string.concat(vaultPath, ".symbol"));
        params.safe = json.readAddress(string.concat(vaultPath, ".safe"));
        params.subscriptionRequestTtl = uint64(json.readUint(string.concat(vaultPath, ".subscriptionRequestTtl")));
        params.redemptionRequestTtl = uint64(json.readUint(string.concat(vaultPath, ".redemptionRequestTtl")));
        params.feeReceiver = json.readAddress(string.concat(vaultPath, ".feeReceiver"));
        params.managementFeeRate = json.readUint(string.concat(vaultPath, ".managementFeeRate"));
        params.redemptionFeeRate = json.readUint(string.concat(vaultPath, ".redemptionFeeRate"));
        params.performanceFeeRate = json.readUint(string.concat(vaultPath, ".performanceFeeRate"));

        // Performance fee module is optional
        params.performanceFeeModule = address(0);
        string memory perfModulePath = string.concat(vaultPath, ".performanceFeeModule");
        if (json.keyExists(perfModulePath)) {
            address perfModule = json.readAddress(perfModulePath);
            if (perfModule != address(0)) {
                params.performanceFeeModule = perfModule;
            }
        }

        params.admin = vm.addr(vm.envUint("PRIVATE_KEY"));
    }

    /**
     * @notice Validate vault parameters
     * @param params The constructor parameters to validate
     */
    function _validateParams(KpkShares.ConstructorParams memory params) internal pure {
        require(params.asset != address(0), "Asset address cannot be zero");
        require(params.safe != address(0), "Safe address cannot be zero");
        require(params.feeReceiver != address(0), "Fee receiver address cannot be zero");
        require(params.subscriptionRequestTtl > 0, "Subscription TTL must be greater than 0");
        require(params.redemptionRequestTtl > 0, "Redemption TTL must be greater than 0");
        require(params.managementFeeRate <= 2000, "Management fee rate cannot exceed 2000 bps (20%)");
        require(params.redemptionFeeRate <= 2000, "Redemption fee rate cannot excieed 2000 bps (20%)");
        require(params.performanceFeeRate <= 2000, "Performance fee rate cannot exceed 2000 bps (20%)");
    }

    /**
     * @notice Deploy the kpkShares contract
     * @param params The constructor parameters
     * @return proxy The address of the deployed proxy
     */
    function _deployContract(KpkShares.ConstructorParams memory params) internal returns (address proxy) {
        // Use the private key from environment to ensure consistent deployer address
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // Deploy implementation contract
        address implementation = address(new KpkShares());

        // Encode the initializer call
        bytes memory initializerData = abi.encodeCall(KpkShares.initialize, (params));

        // Deploy UUPS proxy
        proxy = UnsafeUpgrades.deployUUPSProxy(implementation, initializerData);
    }

    /**
     * @notice Setup roles on the deployed contract
     * @param proxyContract The deployed proxy contract
     * @param operator The operator address
     * @param admin The admin address
     */
    function _setupRoles(KpkShares proxyContract, address operator, address admin) internal {
        // Get deployer address from the private key (must match the broadcaster)
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployerAddress = vm.addr(deployerPrivateKey);

        // The deployer was set as admin during initialization, so they can grant roles
        // vm.startBroadcast() is already active from _deployContract, so these calls
        // will be made as the deployer (who has DEFAULT_ADMIN_ROLE)
        proxyContract.grantRole(OPERATOR, operator);
        proxyContract.grantRole(DEFAULT_ADMIN_ROLE, admin);
        proxyContract.revokeRole(DEFAULT_ADMIN_ROLE, deployerAddress);
    }

    /**
     * @notice Log deployment information
     * @param vaultName The vault name
     * @param proxy The proxy address
     * @param params The constructor parameters
     * @param admin The admin address
     * @param operator The operator address
     */
    function _logDeployment(
        string memory vaultName,
        address proxy,
        KpkShares.ConstructorParams memory params,
        address admin,
        address operator
    ) internal view {
        console.log("==========================================");
        console.log("kpkShares Deployment Complete");
        console.log("==========================================");
        console.log("Vault Name:", vaultName);
        console.log("Proxy Address:", proxy);
        console.log("Admin:", admin);
        console.log("Operator:", operator);
        console.log("Asset:", params.asset);
        console.log("Name:", params.name);
        console.log("Symbol:", params.symbol);
        console.log("Safe:", params.safe);
        console.log("Subscription TTL:", params.subscriptionRequestTtl);
        console.log("Redemption TTL:", params.redemptionRequestTtl);
        console.log("Fee Receiver:", params.feeReceiver);
        console.log("Management Fee Rate (bps):", params.managementFeeRate);
        console.log("Redemption Fee Rate (bps):", params.redemptionFeeRate);
        console.log("Performance Fee Module:", params.performanceFeeModule);
        console.log("Performance Fee Rate (bps):", params.performanceFeeRate);
        console.log("Chain ID:", block.chainid);
        console.log("==========================================");
    }
}

