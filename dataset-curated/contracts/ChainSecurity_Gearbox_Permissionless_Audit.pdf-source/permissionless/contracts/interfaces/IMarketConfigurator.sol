// SPDX-License-Identifier: MIT
// Gearbox Protocol. Generalized leverage for DeFi protocols
// (c) Gearbox Foundation, 2024.
pragma solidity ^0.8.23;

import {IVersion} from "@gearbox-protocol/core-v3/contracts/interfaces/base/IVersion.sol";
import {IDeployerTrait} from "./base/IDeployerTrait.sol";
import {Call, DeployParams, MarketFactories} from "./Types.sol";

interface IMarketConfigurator is IVersion, IDeployerTrait {
    // ------ //
    // EVENTS //
    // ------ //

    event SetEmergencyAdmin(address indexed newEmergencyAdmin);

    event GrantRole(bytes32 indexed role, address indexed account);

    event RevokeRole(bytes32 indexed role, address indexed account);

    event EmergencyRevokeRole(bytes32 indexed role, address indexed account);

    event CreateMarket(
        address indexed pool,
        address priceOracle,
        address interestRateModel,
        address rateKeeper,
        address lossPolicy,
        MarketFactories factories
    );

    event ShutdownMarket(address indexed pool);

    event AddToken(address indexed pool, address indexed token);

    event ConfigurePool(address indexed pool, bytes data);

    event EmergencyConfigurePool(address indexed pool, bytes data);

    event CreateCreditSuite(address indexed creditManager, address factory);

    event ShutdownCreditSuite(address indexed creditManager);

    event ConfigureCreditSuite(address indexed creditManager, bytes data);

    event EmergencyConfigureCreditSuite(address indexed creditManager, bytes data);

    event UpdatePriceOracle(address indexed pool, address priceOracle);

    event ConfigurePriceOracle(address indexed pool, bytes data);

    event EmergencyConfigurePriceOracle(address indexed pool, bytes data);

    event UpdateInterestRateModel(address indexed pool, address interestRateModel);

    event ConfigureInterestRateModel(address indexed pool, bytes data);

    event EmergencyConfigureInterestRateModel(address indexed pool, bytes data);

    event UpdateRateKeeper(address indexed pool, address rateKeeper);

    event ConfigureRateKeeper(address indexed pool, bytes data);

    event EmergencyConfigureRateKeeper(address indexed pool, bytes data);

    event UpdateLossPolicy(address indexed pool, address lossPolicy);

    event ConfigureLossPolicy(address indexed pool, bytes data);

    event EmergencyConfigureLossPolicy(address indexed pool, bytes data);

    event AddPeripheryContract(bytes32 indexed domain, address indexed peripheryContract);

    event RemovePeripheryContract(bytes32 indexed domain, address indexed peripheryContract);

    event AuthorizeFactory(address indexed factory, address indexed suite, address indexed target);

    event UnauthorizeFactory(address indexed factory, address indexed suite, address indexed target);

    event UpgradePoolFactory(address indexed pool, address factory);

    event UpgradePriceOracleFactory(address indexed pool, address factory);

    event UpgradeInterestRateModelFactory(address indexed pool, address factory);

    event UpgradeRateKeeperFactory(address indexed pool, address factory);

    event UpgradeLossPolicyFactory(address indexed pool, address factory);

    event UpgradeCreditFactory(address indexed creditManager, address factory);

    event ExecuteHook(address indexed target, bytes callData);

    // ------ //
    // ERRORS //
    // ------ //

    error CallerIsNotAdminException(address caller);

    error CallerIsNotEmergencyAdminException(address caller);

    error CallerIsNotSelfException(address caller);

    error CreditSuiteNotRegisteredException(address creditManager);

    error IncorrectPeripheryContractException(address peripheryContract);

    error MarketNotRegisteredException(address pool);

    error UnauthorizedFactoryException(address factory, address target);

    // --------------- //
    // STATE VARIABLES //
    // --------------- //

    function admin() external view returns (address);
    function emergencyAdmin() external view returns (address);
    function curatorName() external view returns (string memory);

    function acl() external view returns (address);
    function contractsRegister() external view returns (address);
    function treasury() external view returns (address);

    // ---------------- //
    // ROLES MANAGEMENT //
    // ---------------- //

    function setEmergencyAdmin(address newEmergencyAdmin) external;

    function grantRole(bytes32 role, address account) external;

    function revokeRole(bytes32 role, address account) external;

    function emergencyRevokeRole(bytes32 role, address account) external;

    // ----------------- //
    // MARKET MANAGEMENT //
    // ----------------- //

    function previewCreateMarket(uint256 minorVersion, address underlying, string calldata name, string calldata symbol)
        external
        view
        returns (address pool);

    function createMarket(
        uint256 minorVersion,
        address underlying,
        string calldata name,
        string calldata symbol,
        DeployParams calldata interestRateModelParams,
        DeployParams calldata rateKeeperParams,
        DeployParams calldata lossPolicyParams,
        address underlyingPriceFeed
    ) external returns (address pool);

    function shutdownMarket(address pool) external;

    function addToken(address pool, address token, address priceFeed) external;

    function configurePool(address pool, bytes calldata data) external;

    function emergencyConfigurePool(address pool, bytes calldata data) external;

    // ----------------------- //
    // CREDIT SUITE MANAGEMENT //
    // ----------------------- //

    function previewCreateCreditSuite(uint256 minorVersion, address pool, bytes calldata encodedParams)
        external
        view
        returns (address creditManager);

    function createCreditSuite(uint256 minorVersion, address pool, bytes calldata encdodedParams)
        external
        returns (address creditManager);

    function shutdownCreditSuite(address creditManager) external;

    function configureCreditSuite(address creditManager, bytes calldata data) external;

    function emergencyConfigureCreditSuite(address creditManager, bytes calldata data) external;

    // ----------------------- //
    // PRICE ORACLE MANAGEMENT //
    // ----------------------- //

    function updatePriceOracle(address pool) external returns (address priceOracle);

    function configurePriceOracle(address pool, bytes calldata data) external;

    function emergencyConfigurePriceOracle(address pool, bytes calldata data) external;

    // -------------- //
    // IRM MANAGEMENT //
    // -------------- //

    function updateInterestRateModel(address pool, DeployParams calldata params) external returns (address irm);

    function configureInterestRateModel(address pool, bytes calldata data) external;

    function emergencyConfigureInterestRateModel(address pool, bytes calldata data) external;

    // ---------------------- //
    // RATE KEEPER MANAGEMENT //
    // ---------------------- //

    function updateRateKeeper(address pool, DeployParams calldata params) external returns (address rateKeeper);

    function configureRateKeeper(address pool, bytes calldata data) external;

    function emergencyConfigureRateKeeper(address pool, bytes calldata data) external;

    // -–-------------------- //
    // LOSS POLICY MANAGEMENT //
    // -–-------------------- //

    function updateLossPolicy(address pool, DeployParams calldata params) external returns (address lossPolicy);

    function configureLossPolicy(address pool, bytes calldata data) external;

    function emergencyConfigureLossPolicy(address pool, bytes calldata data) external;

    // --------- //
    // PERIPHERY //
    // --------- //

    function getPeripheryContracts(bytes32 domain) external view returns (address[] memory);

    function isPeripheryContract(bytes32 domain, address peripheryContract) external view returns (bool);

    function addPeripheryContract(address peripheryContract) external;

    function removePeripheryContract(address peripheryContract) external;

    // --------- //
    // FACTORIES //
    // --------- //

    function getMarketFactories(address pool) external view returns (MarketFactories memory);

    function getCreditFactory(address creditManager) external view returns (address);

    function getAuthorizedFactory(address target) external view returns (address);

    function getFactoryTargets(address factory, address suite) external view returns (address[] memory);

    function authorizeFactory(address factory, address suite, address target) external;

    function unauthorizeFactory(address factory, address suite, address target) external;

    function upgradePoolFactory(address pool) external;

    function upgradePriceOracleFactory(address pool) external;

    function upgradeInterestRateModelFactory(address pool) external;

    function upgradeRateKeeperFactory(address pool) external;

    function upgradeLossPolicyFactory(address pool) external;

    function upgradeCreditFactory(address creditManager) external;
}
