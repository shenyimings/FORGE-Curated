// SPDX-License-Identifier: BUSL-1.1
// Gearbox Protocol. Generalized leverage for DeFi protocols
// (c) Gearbox Foundation, 2024.
pragma solidity ^0.8.23;

import {IAccountFactory} from "@gearbox-protocol/core-v3/contracts/interfaces/base/IAccountFactory.sol";
import {ICreditConfiguratorV3} from "@gearbox-protocol/core-v3/contracts/interfaces/ICreditConfiguratorV3.sol";
import {ICreditFacadeV3} from "@gearbox-protocol/core-v3/contracts/interfaces/ICreditFacadeV3.sol";
import {ICreditManagerV3} from "@gearbox-protocol/core-v3/contracts/interfaces/ICreditManagerV3.sol";
import {IPoolV3} from "@gearbox-protocol/core-v3/contracts/interfaces/IPoolV3.sol";

import {ICreditFactory} from "../interfaces/factories/ICreditFactory.sol";
import {IFactory} from "../interfaces/factories/IFactory.sol";
import {IContractsRegister} from "../interfaces/IContractsRegister.sol";
import {IMarketConfigurator} from "../interfaces/IMarketConfigurator.sol";
import {Call, DeployParams, DeployResult} from "../interfaces/Types.sol";

import {CallBuilder} from "../libraries/CallBuilder.sol";
import {
    DOMAIN_ACCOUNT_FACTORY,
    DOMAIN_ADAPTER,
    DOMAIN_CREDIT_MANAGER,
    DOMAIN_DEGEN_NFT,
    AP_BOT_LIST,
    AP_CREDIT_CONFIGURATOR,
    AP_CREDIT_FACADE,
    AP_CREDIT_FACTORY,
    AP_INSTANCE_MANAGER_PROXY,
    AP_WETH_TOKEN,
    NO_VERSION_CONTROL
} from "../libraries/ContractLiterals.sol";

import {AbstractFactory} from "./AbstractFactory.sol";

struct CreditManagerParams {
    uint8 maxEnabledTokens;
    uint16 feeInterest;
    uint16 feeLiquidation;
    uint16 liquidationPremium;
    uint16 feeLiquidationExpired;
    uint16 liquidationPremiumExpired;
    uint128 minDebt;
    uint128 maxDebt;
    string name;
    DeployParams accountFactoryParams;
}

struct CreditFacadeParams {
    address degenNFT;
    bool expirable;
    bool migrateBotList;
}

interface IConfigureActions {
    function upgradeCreditConfigurator() external;
    function upgradeCreditFacade(CreditFacadeParams calldata params) external;
    function allowAdapter(DeployParams calldata params) external;
    function forbidAdapter(address adapter) external;
    function configureAdapterFor(address targetContract, bytes calldata data) external;
    function setFees(
        uint16 feeLiquidation,
        uint16 liquidationPremium,
        uint16 feeLiquidationExpired,
        uint16 liquidationPremiumExpired
    ) external;
    function setMaxDebtPerBlockMultiplier(uint8 newMaxDebtLimitPerBlockMultiplier) external;
    function addCollateralToken(address token, uint16 liquidationThreshold) external;
    function rampLiquidationThreshold(
        address token,
        uint16 liquidationThresholdFinal,
        uint40 rampStart,
        uint24 rampDuration
    ) external;
    function forbidToken(address token) external;
    function allowToken(address token) external;
    function setExpirationDate(uint40 newExpirationDate) external;
    function pause() external;
    function unpause() external;
}

interface IEmergencyConfigureActions {
    function forbidAdapter(address adapter) external;
    function forbidToken(address token) external;
    function forbidBorrowing() external;
    function pause() external;
}

contract CreditFactory is AbstractFactory, ICreditFactory {
    /// @notice Contract version
    uint256 public constant override version = 3_10;

    /// @notice Contract type
    bytes32 public constant override contractType = AP_CREDIT_FACTORY;

    /// @notice Address of the bot list contract
    address public immutable botList;

    /// @notice Address of the WETH token
    address public immutable weth;

    error DegenNFTIsNotRegisteredException(address degenNFT);

    error TargetContractIsNotAllowedException(address targetCotnract);

    /// @notice Constructor
    /// @param addressProvider_ Address provider contract address
    constructor(address addressProvider_) AbstractFactory(addressProvider_) {
        botList = _getAddressOrRevert(AP_BOT_LIST, NO_VERSION_CONTROL);
        weth = _tryGetAddress(AP_WETH_TOKEN, NO_VERSION_CONTROL);
    }

    // ---------- //
    // DEPLOYMENT //
    // ---------- //

    function deployCreditSuite(address pool, bytes calldata encodedParams)
        external
        override
        onlyMarketConfigurators
        returns (DeployResult memory)
    {
        (CreditManagerParams memory params, CreditFacadeParams memory facadeParams) =
            abi.decode(encodedParams, (CreditManagerParams, CreditFacadeParams));

        address accountFactory = _deployAccountFactory(msg.sender, params.accountFactoryParams);
        address creditManager = _deployCreditManager(msg.sender, pool, accountFactory, params);
        address creditConfigurator = _deployCreditConfigurator(msg.sender, creditManager);
        address creditFacade = _deployCreditFacade(msg.sender, creditManager, facadeParams);

        IAccountFactory(accountFactory).addCreditManager(creditManager);
        ICreditManagerV3(creditManager).setCreditConfigurator(creditConfigurator);

        return DeployResult({
            newContract: creditManager,
            onInstallOps: CallBuilder.build(
                _authorizeFactory(msg.sender, creditManager, creditConfigurator),
                _authorizeFactory(msg.sender, creditManager, creditFacade),
                _setCreditFacade(creditConfigurator, creditFacade, false),
                _setDebtLimits(creditConfigurator, params.minDebt, params.maxDebt)
            )
        });
    }

    function computeCreditManagerAddress(address marketConfigurator, address pool, bytes calldata encodedParams)
        external
        view
        override
        returns (address)
    {
        (CreditManagerParams memory params,) = abi.decode(encodedParams, (CreditManagerParams, CreditFacadeParams));
        return _computeCreditManagerAddress(marketConfigurator, pool, params);
    }

    // ------------ //
    // CREDIT HOOKS //
    // ------------ //

    function onUpdatePriceOracle(address creditManager, address newPriceOracle, address)
        external
        view
        override
        returns (Call[] memory)
    {
        return CallBuilder.build(_setPriceOracle(_creditConfigurator(creditManager), newPriceOracle));
    }

    function onUpdateLossPolicy(address creditManager, address newLossPolicy, address)
        external
        view
        override
        returns (Call[] memory)
    {
        return CallBuilder.build(_setLossPolicy(_creditConfigurator(creditManager), newLossPolicy));
    }

    // ------------- //
    // CONFIGURATION //
    // ------------- //

    function configure(address creditManager, bytes calldata callData)
        external
        override(AbstractFactory, IFactory)
        onlyMarketConfigurators
        returns (Call[] memory)
    {
        bytes4 selector = bytes4(callData);
        if (selector == IConfigureActions.upgradeCreditConfigurator.selector) {
            address creditConfigurator = _creditConfigurator(creditManager);
            address newCreditConfigurator = _deployCreditConfigurator(msg.sender, creditManager);
            return CallBuilder.build(
                _upgradeCreditConfigurator(creditConfigurator, newCreditConfigurator),
                _unauthorizeFactory(msg.sender, creditManager, creditConfigurator),
                _authorizeFactory(msg.sender, creditManager, newCreditConfigurator)
            );
        } else if (selector == IConfigureActions.upgradeCreditFacade.selector) {
            CreditFacadeParams memory params = abi.decode(callData[4:], (CreditFacadeParams));
            address creditFacade = _creditFacade(creditManager);
            address newCreditFacade = _deployCreditFacade(msg.sender, creditManager, params);
            return CallBuilder.build(
                _setCreditFacade(_creditConfigurator(creditManager), newCreditFacade, true),
                _unauthorizeFactory(msg.sender, creditManager, creditFacade),
                _authorizeFactory(msg.sender, creditManager, newCreditFacade)
            );
        } else if (selector == IConfigureActions.allowAdapter.selector) {
            DeployParams memory params = abi.decode(callData[4:], (DeployParams));
            address adapter = _deployAdapter(msg.sender, creditManager, params);
            return CallBuilder.build(
                _authorizeFactory(msg.sender, creditManager, adapter),
                _allowAdapter(_creditConfigurator(creditManager), adapter)
            );
        } else if (selector == IConfigureActions.forbidAdapter.selector) {
            address adapter = abi.decode(callData[4:], (address));
            return CallBuilder.build(
                _authorizeFactory(msg.sender, creditManager, adapter),
                _forbidAdapter(_creditConfigurator(creditManager), adapter)
            );
        } else if (selector == IConfigureActions.configureAdapterFor.selector) {
            (address targetContract, bytes memory data) = abi.decode(callData[4:], (address, bytes));
            address adapter = ICreditManagerV3(creditManager).contractToAdapter(targetContract);
            if (adapter == address(0)) revert TargetContractIsNotAllowedException(targetContract);
            return CallBuilder.build(Call(adapter, data));
        } else if (
            selector == IConfigureActions.setFees.selector
                || selector == IConfigureActions.setMaxDebtPerBlockMultiplier.selector
                || selector == IConfigureActions.addCollateralToken.selector
                || selector == IConfigureActions.rampLiquidationThreshold.selector
                || selector == IConfigureActions.forbidToken.selector || selector == IConfigureActions.allowToken.selector
                || selector == IConfigureActions.setExpirationDate.selector
        ) {
            return CallBuilder.build(Call(_creditConfigurator(creditManager), callData));
        } else if (selector == IConfigureActions.pause.selector || selector == IConfigureActions.unpause.selector) {
            return CallBuilder.build(Call(_creditFacade(creditManager), callData));
        } else {
            revert ForbiddenConfigurationCallException(selector);
        }
    }

    function emergencyConfigure(address creditManager, bytes calldata callData)
        external
        view
        override(AbstractFactory, IFactory)
        returns (Call[] memory)
    {
        bytes4 selector = bytes4(callData);
        if (selector == IEmergencyConfigureActions.forbidAdapter.selector) {
            address adapter = abi.decode(callData[4:], (address));
            return CallBuilder.build(
                _unauthorizeFactory(msg.sender, creditManager, adapter),
                _forbidAdapter(_creditConfigurator(creditManager), adapter)
            );
        } else if (
            selector == IEmergencyConfigureActions.forbidBorrowing.selector
                || selector == IEmergencyConfigureActions.forbidToken.selector
        ) {
            return CallBuilder.build(Call(_creditConfigurator(creditManager), callData));
        } else if (selector == IEmergencyConfigureActions.pause.selector) {
            return CallBuilder.build(Call(_creditFacade(creditManager), callData));
        } else {
            revert ForbiddenEmergencyConfigurationCallException(selector);
        }
    }

    // --------- //
    // INTERNALS //
    // --------- //

    function _deployAccountFactory(address marketConfigurator, DeployParams memory params) internal returns (address) {
        address decodedAddressProvider = abi.decode(params.constructorParams, (address));
        if (decodedAddressProvider != addressProvider) revert InvalidConstructorParamsException();

        return _deployLatestPatch({
            contractType: _getContractType(DOMAIN_ACCOUNT_FACTORY, params.postfix),
            minorVersion: version,
            constructorParams: params.constructorParams,
            salt: keccak256(abi.encode(params.salt, marketConfigurator))
        });
    }

    function _computeAccountFactoryAddress(address marketConfigurator, DeployParams memory params)
        internal
        view
        returns (address)
    {
        return _computeAddressLatestPatch({
            contractType: _getContractType(DOMAIN_ACCOUNT_FACTORY, params.postfix),
            minorVersion: version,
            constructorParams: params.constructorParams,
            salt: keccak256(abi.encode(params.salt, marketConfigurator)),
            deployer: address(this)
        });
    }

    function _deployCreditManager(
        address marketConfigurator,
        address pool,
        address accountFactory,
        CreditManagerParams memory params
    ) internal returns (address) {
        bytes32 postfix = _getTokenSpecificPostfix(IPoolV3(pool).asset());
        bytes memory constructorParams =
            _buildCreditManagerConstructorParams(marketConfigurator, pool, accountFactory, params);
        return _deployLatestPatch({
            contractType: _getContractType(DOMAIN_CREDIT_MANAGER, postfix),
            minorVersion: version,
            constructorParams: constructorParams,
            salt: bytes32(bytes20(marketConfigurator))
        });
    }

    function _computeCreditManagerAddress(address marketConfigurator, address pool, CreditManagerParams memory params)
        internal
        view
        returns (address)
    {
        address accountFactory = _computeAccountFactoryAddress(marketConfigurator, params.accountFactoryParams);
        bytes32 postfix = _getTokenSpecificPostfix(IPoolV3(pool).asset());
        bytes memory constructorParams =
            _buildCreditManagerConstructorParams(marketConfigurator, pool, accountFactory, params);
        return _computeAddressLatestPatch({
            contractType: _getContractType(DOMAIN_CREDIT_MANAGER, postfix),
            minorVersion: version,
            constructorParams: constructorParams,
            salt: bytes32(bytes20(marketConfigurator)),
            deployer: address(this)
        });
    }

    function _buildCreditManagerConstructorParams(
        address marketConfigurator,
        address pool,
        address accountFactory,
        CreditManagerParams memory params
    ) internal view returns (bytes memory) {
        address contractsRegister = IMarketConfigurator(marketConfigurator).contractsRegister();
        address priceOracle = IContractsRegister(contractsRegister).getPriceOracle(pool);

        return abi.encode(
            pool,
            accountFactory,
            priceOracle,
            params.maxEnabledTokens,
            params.feeInterest,
            params.feeLiquidation,
            params.liquidationPremium,
            params.feeLiquidationExpired,
            params.liquidationPremiumExpired,
            params.name
        );
    }

    function _deployCreditConfigurator(address marketConfigurator, address creditManager) internal returns (address) {
        address acl = IMarketConfigurator(marketConfigurator).acl();
        bytes memory constructorParams = abi.encode(acl, creditManager);

        return _deployLatestPatch({
            contractType: AP_CREDIT_CONFIGURATOR,
            minorVersion: version,
            constructorParams: constructorParams,
            salt: bytes32(bytes20(marketConfigurator))
        });
    }

    function _deployCreditFacade(address marketConfigurator, address creditManager, CreditFacadeParams memory params)
        internal
        returns (address)
    {
        address acl = IMarketConfigurator(marketConfigurator).acl();
        address contractsRegister = IMarketConfigurator(marketConfigurator).contractsRegister();
        address lossPolicy = IContractsRegister(contractsRegister).getLossPolicy(ICreditManagerV3(creditManager).pool());

        if (
            params.degenNFT != address(0)
                && !IMarketConfigurator(marketConfigurator).isPeripheryContract(DOMAIN_DEGEN_NFT, params.degenNFT)
        ) {
            revert DegenNFTIsNotRegisteredException(params.degenNFT);
        }

        address botList_ = botList;
        if (params.migrateBotList) {
            address prevCreditFacade = ICreditManagerV3(creditManager).creditFacade();
            botList_ = ICreditFacadeV3(prevCreditFacade).botList();
        }

        bytes memory constructorParams =
            abi.encode(acl, creditManager, lossPolicy, botList_, weth, params.degenNFT, params.expirable);

        return _deployLatestPatch({
            contractType: AP_CREDIT_FACADE,
            minorVersion: version,
            constructorParams: constructorParams,
            salt: bytes32(bytes20(marketConfigurator))
        });
    }

    function _deployAdapter(address marketConfigurator, address creditManager, DeployParams memory params)
        internal
        returns (address)
    {
        address decodedCreditManager = abi.decode(params.constructorParams, (address));
        if (decodedCreditManager != creditManager) revert InvalidConstructorParamsException();

        return _deployLatestPatch({
            contractType: _getContractType(DOMAIN_ADAPTER, params.postfix),
            minorVersion: version,
            constructorParams: params.constructorParams,
            salt: keccak256(abi.encode(params.salt, marketConfigurator))
        });
    }

    function _creditConfigurator(address creditManager) internal view returns (address) {
        return ICreditManagerV3(creditManager).creditConfigurator();
    }

    function _creditFacade(address creditManager) internal view returns (address) {
        return ICreditManagerV3(creditManager).creditFacade();
    }

    function _upgradeCreditConfigurator(address creditConfigurator, address newCreditConfigurator)
        internal
        pure
        returns (Call memory)
    {
        return Call(
            creditConfigurator, abi.encodeCall(ICreditConfiguratorV3.upgradeCreditConfigurator, (newCreditConfigurator))
        );
    }

    function _setCreditFacade(address creditConfigurator, address creditFacade, bool migrateParams)
        internal
        pure
        returns (Call memory)
    {
        return Call(
            creditConfigurator, abi.encodeCall(ICreditConfiguratorV3.setCreditFacade, (creditFacade, migrateParams))
        );
    }

    function _setPriceOracle(address creditConfigurator, address priceOracle) internal pure returns (Call memory) {
        return Call(creditConfigurator, abi.encodeCall(ICreditConfiguratorV3.setPriceOracle, priceOracle));
    }

    function _setLossPolicy(address creditConfigurator, address lossPolicy) internal pure returns (Call memory) {
        return Call(creditConfigurator, abi.encodeCall(ICreditConfiguratorV3.setLossPolicy, lossPolicy));
    }

    function _allowAdapter(address creditConfigurator, address adapter) internal pure returns (Call memory) {
        return Call(creditConfigurator, abi.encodeCall(ICreditConfiguratorV3.allowAdapter, adapter));
    }

    function _forbidAdapter(address creditConfigurator, address adapter) internal pure returns (Call memory) {
        return Call(creditConfigurator, abi.encodeCall(ICreditConfiguratorV3.forbidAdapter, adapter));
    }

    function _setDebtLimits(address creditConfigurator, uint128 minDebt, uint128 maxDebt)
        internal
        pure
        returns (Call memory)
    {
        return Call(creditConfigurator, abi.encodeCall(ICreditConfiguratorV3.setDebtLimits, (minDebt, maxDebt)));
    }
}
