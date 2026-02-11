// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Auth} from "src/core/Auth.sol";
import {TadleImplementations} from "src/core/Implementations.sol";
import {TadleConnectors} from "src/core/Connectors.sol";
import {TadleSandBoxFactory} from "src/core/Factory.sol";
import {TadleSandboxAccount} from "src/proxy/AccountProxy.sol";
import {TadleImplementationV1} from "src/relayers/monad_testnet/implementation/ImplementationV1.sol";
import {TadleDefaultImplementation} from "src/relayers/monad_testnet/implementation/ImplementationDefault.sol";
import {ConnectV1AccountManager} from "src/relayers/monad_testnet/account-manager-v1/main.sol";
import {ConnectV1Airdrop} from "src/relayers/monad_testnet/airdrop/main.sol";
import {ConnectV1NadFun, NadFunResolver} from "src/relayers/monad_testnet/nad-fun/main.sol";
import {ConnectV1Aprioi} from "src/relayers/monad_testnet/aprioi/main.sol";
import {ConnectV1UniswapV3Position, UniswapV3PositionResolver} from "src/relayers/monad_testnet/uniswap-v3/main.sol";
import {ConnectV1UniswapSwapRouter02, UniswapSwapRouter02Resolver} from "src/relayers/monad_testnet/uniswap-swap/main.sol";
import {TadleMemory} from "src/core/TadleMemory.sol";
import {INonfungiblePositionManager} from "src/relayers/monad_testnet/uniswap-v3/helpers.sol";
import {ConnectV1Magma, MagmaResolver} from "src/relayers/monad_testnet/magma/main.sol";
import {ConnectV1WETH, WETHResolver} from "src/relayers/monad_testnet/weth/main.sol";
import {AirdropResolver} from "src/relayers/monad_testnet/airdrop/main.sol";
import {Validator} from "src/core/Validator.sol";

/**
 * @title Deployers
 * @author Tadle Team
 * @notice Utility contract for deploying and configuring Tadle sandbox contracts in test environments
 * @dev This contract provides deployment functions for all core protocol components and test utilities
 * @custom:test-utility Centralizes contract deployment logic for consistent test setup
 * @custom:network Configured for Monad testnet with predefined protocol addresses
 */
contract Deployers is Test {
    // ============ CORE PROTOCOL ADDRESSES ============

    /// @dev NAD Fun protocol address on Monad testnet
    address internal constant NAD_FUN =
        0x822EB1ADD41cf87C3F178100596cf24c9a6442f6;
    /// @dev Aprioi protocol address on Monad testnet
    address internal constant APRIOI =
        0xb2f82D0f38dc453D596Ad40A37799446Cc89274A;
    /// @dev Magma staking manager contract address
    address internal constant MAGMA_STAKE_MANAGER =
        0x2c9C959516e9AAEdB2C748224a41249202ca8BE7;
    /// @dev GMON token address on Monad testnet
    address internal constant GMON = 0xaEef2f6B429Cb59C9B2D7bB2141ADa993E8571c3;

    // ============ NAD NAME SERVICE ADDRESSES ============

    /// @dev NAD Name Service registration contract for domain registration
    address internal constant NAD_NAME_REGISTRATION =
        0x758D80767a751fc1634f579D76e1CcaAb3485c9c;
    /// @dev NAD Name Service pricing contract for domain pricing logic
    address internal constant NAD_NAME_PRICING =
        0x0665C6C7f7e6E87424BAEA5d139cb719D557A850;
    /// @dev NAD Name Service manager contract for domain management
    address internal constant NAD_NAME_MANAGER =
        0x3019BF1dfB84E5b46Ca9D0eEC37dE08a59A41308;

    // ============ UNISWAP PROTOCOL ADDRESSES ============

    /// @dev Uniswap V2/V3 router contract for token swaps
    address internal constant UNISWAP_ROUTER =
        0x4c4eABd5Fb1D1A7234A48692551eAECFF8194CA7;
    /// @dev Wrapped ETH (WETH) contract address on Monad
    address internal constant WETH_ADDR =
        0x760AfE86e5de5fa0Ee542fc7B7B713e1c5425701;
    /// @dev Uniswap V3 NFT Position Manager for liquidity positions
    address internal constant NFT_MANAGER =
        0x3dCc735C74F10FE2B9db2BB55C40fbBbf24490f7;
    /// @dev Uniswap V3 Factory contract for pool creation
    address internal constant UNISWAP_V3_FACTORY =
        0x961235a9020B05C44DF1026D956D1F4D78014276;

    // ============ DEFI PROTOCOL ADDRESSES ============

    /// @dev Ambient Finance DEX contract for concentrated liquidity
    address internal constant AMBIENT_FINANCE =
        0x88B96aF200c8a9c35442C8AC6cd3D22695AaE4F0;
    /// @dev Tadle Odds Market contract for prediction markets
    address internal constant TADLE_ODDS_MARKET =
        0x734D5aB96eEAFE1F8BA36186627FAd08E7fF7026;

    // ============ SYSTEM MANAGEMENT ADDRESSES ============

    /// @dev Report Manager contract for handling system reports and analytics
    address internal constant REPORT_MANAGER =
        0x370CfDbf56B50B1169557078bDC8fcE1477089b8;
    /// @dev Tadle Point Token Market for point-based trading
    address internal constant TADLE_POINT_TOKEN_MARKET =
        0xc026608987c0BfC3E7aFFB8b43c40c7572649E58;
    /// @dev Tadle Token Manager for token lifecycle management
    address internal constant TADLE_TOKEN_MANAGER =
        0x0091E1b230bAb4A7FD6b7Bee8722E18FD7770Cfb;
    /// @dev Tadle System Configuration contract for protocol parameters
    address internal constant TADLE_SYSTEM_CONFIG =
        0xe4478D8085Fad0E0119060f89Fd27b0e6eBbf1C6;

    // ============ SPECIAL ADDRESSES ============

    /// @dev Special address constant representing native ETH/MON in the protocol
    address internal constant ETH_ADDRESS =
        0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    /// @dev MonUSD stablecoin address on Monad testnet
    address internal constant MON_USD =
        0x57c914e3240C837EBE87F096e0B4d9A06E3F489B;
    /// @dev Tether USD (USDT) token address on Monad testnet
    address internal constant USDT = 0x88b8E2161DEDC77EF4ab7585569D2415a1C1055D;
    /// @dev USD Coin (USDC) token address on Monad testnet - primary test token
    address internal constant USDC = 0xf817257fed379853cDe0fa4F97AB987181B1E5Ea;

    address internal constant DAK = 0x0F0BDEbF0F83cD1EE3974779Bcb7315f9808c714;

    // ============ VALIDATOR CONSTANTS ============

    /// @dev Key for token whitelist validation in the account manager
    bytes32 internal constant VALIDATOR_TOKEN_WHITELIST_KEY =
        keccak256("account-manager-token-whitelist");

    // ============ CORE CONTRACT INSTANCES ============

    /// @dev Authentication and authorization contract for access control
    Auth public auth;
    /// @dev Implementation registry contract for managing contract implementations
    TadleImplementations public implementations;
    /// @dev Connector registry contract for managing protocol connectors
    TadleConnectors public connectors;
    /// @dev TadleConnectors contract instance specifically configured for airdrop functionality
    TadleConnectors public airdrop;
    /// @dev Factory contract for creating upgradeable proxy contracts
    TadleSandBoxFactory public factory;
    /// @dev Account proxy contract template for user sandbox accounts
    TadleSandboxAccount public accountProxy;
    /// @dev Version 1 implementation contract with enhanced functionality
    TadleImplementationV1 public implementationV1;
    /// @dev Default implementation contract for basic operations
    TadleDefaultImplementation public defaultImplementation;

    // ============ CONNECTOR INSTANCES ============

    /// @dev Airdrop connector v1 for handling token distribution functionality
    ConnectV1Airdrop public connectV1Airdrop;
    /// @dev Account manager connector v1 for handling account operations
    ConnectV1AccountManager public connectV1AccountManager;

    ConnectV1UniswapSwapRouter02 public connectV1UniswapSwapRouter02;

    // ============ UTILITY CONTRACTS ============

    /// @dev Memory management contract for optimized storage operations
    TadleMemory public tadleMemory;
    /// @dev Validation contract for input validation and security checks
    Validator public validator;

    // ============ TEST ADDRESSES ============

    /// @dev Deployer address for testing - has deployment privileges
    address deployer = vm.addr(1);
    /// @dev Manager address for testing - has administrative privileges
    address manager = vm.addr(2);
    /// @dev User address for testing - represents end users
    address user = vm.addr(3);

    /**
     * @dev Deploys all core contracts for the Tadle sandbox
     * This function sets up the complete contract ecosystem including:
     * - Authentication and authorization system
     * - Factory for proxy creation
     * - Implementation and connector registries
     * - Validator and memory management
     * - Airdrop functionality
     */
    function deployCoreContracts() public {
        // Deploy factory contract as deployer
        vm.startPrank(deployer);
        factory = new TadleSandBoxFactory(address(manager));
        vm.stopPrank();

        // Deploy core contracts as manager
        vm.startPrank(manager);

        // Deploy and initialize Auth contract for authentication and authorization
        Auth authImpl = new Auth();
        address authProxy = factory.createUpgradeableProxy(
            "AuthProxy",
            address(authImpl),
            address(manager),
            keccak256(abi.encode("AuthProxy", "v1")),
            bytes("")
        );

        // Deploy and initialize TadleConnectors for managing connector registry
        TadleConnectors tadleConnectorsImpl = new TadleConnectors();
        address tadleConnectorsProxy = factory.createUpgradeableProxy(
            "TadleConnectors",
            address(tadleConnectorsImpl),
            address(manager),
            keccak256(abi.encode("TadleConnectors", "v1")),
            bytes("")
        );

        // Deploy and initialize TadleImplementations for managing implementation registry
        TadleImplementations tadleImplementationsImpl = new TadleImplementations();
        address tadleImplementationsProxy = factory.createUpgradeableProxy(
            "TadleImplementations",
            address(tadleImplementationsImpl),
            address(manager),
            keccak256(abi.encode("TadleImplementations", "v1")),
            bytes("")
        );

        // Deploy and initialize TadleMemory for memory management
        TadleMemory tadleMemoryImpl = new TadleMemory();
        address tadleMemoryProxy = factory.createUpgradeableProxy(
            "TadleMemory",
            address(tadleMemoryImpl),
            address(manager),
            keccak256(abi.encode("TadleMemory", "v1")),
            bytes("")
        );

        // Deploy and initialize Validator for validation logic
        Validator validatorImpl = new Validator();
        address validatorProxy = factory.createUpgradeableProxy(
            "Validator",
            address(validatorImpl),
            address(manager),
            keccak256(abi.encode("Validator", "v1")),
            bytes("")
        );

        // Set up contract instances from proxy addresses
        auth = Auth(authProxy);
        connectors = TadleConnectors(tadleConnectorsProxy);
        implementations = TadleImplementations(tadleImplementationsProxy);
        tadleMemory = TadleMemory(tadleMemoryProxy);
        validator = Validator(validatorProxy);

        // Initialize all contracts with proper dependencies
        auth.initialize(manager);
        connectors.initialize(address(auth), address(factory));
        implementations.initialize(address(auth));
        validator.initialize(address(auth));
        vm.stopPrank();

        vm.startPrank(deployer);
        // Deploy account proxy and implementation contracts
        accountProxy = new TadleSandboxAccount(address(implementations));
        defaultImplementation = new TadleDefaultImplementation(address(auth));
        implementationV1 = new TadleImplementationV1(
            address(auth),
            address(connectors)
        );

        // Set up airdrop functionality and connector contracts
        airdrop = TadleConnectors(tadleConnectorsProxy);
        connectV1Airdrop = new ConnectV1Airdrop(
            address(airdrop),
            address(manager)
        );
        connectV1AccountManager = new ConnectV1AccountManager(
            address(airdrop),
            address(validator)
        );

        // Deploy additional connector contracts
        connectV1UniswapSwapRouter02 = new ConnectV1UniswapSwapRouter02(
            UNISWAP_ROUTER,
            WETH_ADDR,
            address(tadleMemory)
        );

        vm.stopPrank();

        vm.startPrank(manager);
        // Initialize factory and establish cross-contract relationships
        factory.initialize(address(auth), address(accountProxy));
        auth.setFactory(address(factory));
        implementations.setDefaultImplementation(
            address(defaultImplementation)
        );

        // Configure validator with ETH as whitelisted token
        validator.setValidator(
            VALIDATOR_TOKEN_WHITELIST_KEY,
            ETH_ADDRESS,
            true
        );

        validator.setValidator(VALIDATOR_TOKEN_WHITELIST_KEY, USDC, true);

        // Register implementation with supported function signatures
        bytes4[] memory _signatures = new bytes4[](1);
        _signatures[0] = bytes4(keccak256("cast(string[],bytes[])"));

        implementations.addImplementation(
            address(implementationV1),
            _signatures
        );

        vm.stopPrank();
    }

    /**
     * @notice Creates a new sandbox account for the test user
     * @dev Uses the factory contract to deploy a new proxy account for testing
     * @return account The address of the newly created sandbox account
     * @custom:access Impersonates the test user for account creation
     * @custom:proxy Creates an upgradeable proxy account linked to the user
     */
    function createSandBoxAccount() public returns (address) {
        // Impersonate the user to create their sandbox account
        vm.prank(user, user);
        // Deploy a new sandbox account proxy through the factory
        address account = factory.build(address(user));
        return account;
    }

    /**
     * @notice Deploys and initializes the airdrop system with USDC configuration
     * @dev Sets up airdrop connectors and configures USDC token distribution parameters
     * @custom:setup-phase Configures airdrop functionality for testing
     * @custom:permissions Requires manager privileges for configuration
     * @custom:tokens Configures USDC with 10 tokens per claim and 7-day cooldown
     */
    function deployAndInitializeAirdrop() public {
        // Start impersonating manager for administrative operations
        vm.startPrank(manager);

        // Register airdrop connector with the connectors registry
        string[] memory _names = new string[](1);
        _names[0] = "Airdrop-Gas-v1.0.0"; // Connector name for airdrop functionality
        address[] memory _connectors = new address[](1);
        _connectors[0] = address(connectV1Airdrop); // Airdrop connector contract address
        connectors.addConnectors(_names, _connectors);

        // Configure airdrop amount for level 1 users: 10 USDC (with 6 decimals)
        airdrop.setTokenAmountByLevel(USDC, 1, 10 * 1e6);

        // Configure USDC airdrop parameters:
        // - userAirdropAmount: 10 USDC per claim
        // - userCooldownPeriod: 7 days between claims
        // - isEnabled: true (airdrop is active)
        airdrop.setTokenAirdropConfig(USDC, 10 * 1e6, 7 days, true);

        // Stop impersonating manager
        vm.stopPrank();
    }

    /**
     * @notice Deploys and initializes the account manager system
     * @dev Registers the account manager connector for handling account operations
     * @custom:setup-phase Configures account management functionality for testing
     * @custom:permissions Requires manager privileges for connector registration
     * @custom:functionality Enables deposit, withdrawal, and account management features
     */
    function deployAndInitializeAccountManager() public {
        // Prepare connector registration data
        string[] memory _names = new string[](1);
        _names[0] = "AccountManager-v1.0.0"; // Connector name for account management
        address[] memory _connectors = new address[](1);
        _connectors[0] = address(connectV1AccountManager); // Account manager connector address

        // Register account manager connector with manager privileges
        vm.prank(manager, manager);
        connectors.addConnectors(_names, _connectors);
    }

    function deployAndInitializeUniswapSwapRouter02Connect() public {
        // Prepare connector registration data for Uniswap Swap Router 02
        string[] memory _names = new string[](1);
        _names[0] = "UniswapSwapRouter02-v1.0.0"; // Connector name for Uniswap Swap Router 02 operations
        address[] memory _connectors = new address[](1);
        _connectors[0] = address(connectV1UniswapSwapRouter02); // Uniswap Swap Router 02 connector contract address

        // Register Uniswap Swap Router 02 connector with manager privileges
        vm.prank(manager, manager);
        connectors.addConnectors(_names, _connectors);
    }
}
