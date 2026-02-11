// SPDX-License-Identifier: BUSL-1.1
// Gearbox Protocol. Generalized leverage for DeFi protocols
// (c) Gearbox Foundation, 2024.
pragma solidity ^0.8.23;

import {SafeERC20} from "@1inch/solidity-utils/contracts/libraries/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {ICreditManagerV3} from "@gearbox-protocol/core-v3/contracts/interfaces/ICreditManagerV3.sol";
import {IPoolQuotaKeeperV3} from "@gearbox-protocol/core-v3/contracts/interfaces/IPoolQuotaKeeperV3.sol";
import {IPoolV3} from "@gearbox-protocol/core-v3/contracts/interfaces/IPoolV3.sol";
import {IPriceOracleV3} from "@gearbox-protocol/core-v3/contracts/interfaces/IPriceOracleV3.sol";

import {DefaultIRM} from "../helpers/DefaultIRM.sol";

import {IFactory} from "../interfaces/factories/IFactory.sol";
import {IMarketFactory} from "../interfaces/factories/IMarketFactory.sol";
import {IPoolFactory} from "../interfaces/factories/IPoolFactory.sol";
import {IAddressProvider} from "../interfaces/IAddressProvider.sol";
import {IMarketConfigurator} from "../interfaces/IMarketConfigurator.sol";
import {Call, DeployResult} from "../interfaces/Types.sol";

import {CallBuilder} from "../libraries/CallBuilder.sol";
import {AP_POOL_FACTORY, AP_POOL_QUOTA_KEEPER, DOMAIN_POOL} from "../libraries/ContractLiterals.sol";

import {AbstractFactory} from "./AbstractFactory.sol";
import {AbstractMarketFactory} from "./AbstractMarketFactory.sol";

interface IConfigureActions {
    function setTotalDebtLimit(uint256 limit) external;
    function setCreditManagerDebtLimit(address creditManager, uint256 limit) external;
    function setTokenLimit(address token, uint96 limit) external;
    function setTokenQuotaIncreaseFee(address token, uint16 fee) external;
    function pause() external;
    function unpause() external;
}

interface IEmergencyConfigureActions {
    function setCreditManagerDebtLimitToZero(address creditManager) external;
    function setTokenLimitToZero(address token) external;
    function pause() external;
}

contract PoolFactory is AbstractMarketFactory, IPoolFactory {
    using SafeERC20 for IERC20;

    /// @notice Contract version
    uint256 public constant override version = 3_10;

    /// @notice Contract type
    bytes32 public constant override contractType = AP_POOL_FACTORY;

    /// @notice Address of the default IRM
    address public immutable defaultInterestRateModel;

    /// @notice Thrown when trying to shutdown a credit suite with non-zero outstanding debt
    error CantShutdownCreditSuiteWithNonZeroDebtException(address creditManager);

    /// @notice Thrown when trying to shutdown a market with non-zero outstanding debt
    error CantShutdownMarketWithNonZeroDebtException(address pool);

    /// @notice Thrown when trying to deploy a pool without funding factory to mint dead shares
    error InsufficientFundsForDeploymentException();

    /// @notice Thrown when to set non-zero quota limit for a token with zero price feed
    error ZeroPriceFeedException(address token);

    /// @notice Constructor
    /// @param addressProvider_ Address provider contract address
    constructor(address addressProvider_) AbstractFactory(addressProvider_) {
        defaultInterestRateModel = address(new DefaultIRM());
    }

    // ---------- //
    // DEPLOYMENT //
    // ---------- //

    function deployPool(address underlying, string calldata name, string calldata symbol)
        external
        override
        onlyMarketConfigurators
        returns (DeployResult memory)
    {
        address pool = _deployPool(msg.sender, underlying, name, symbol);
        address quotaKeeper = _deployQuotaKeeper(msg.sender, pool);

        // NOTE: should use batching to avoid getting frontrun
        if (IERC20(underlying).balanceOf(address(this)) < 1e5) revert InsufficientFundsForDeploymentException();
        IERC20(underlying).forceApprove(pool, 1e5);
        IPoolV3(pool).deposit(1e5, address(0xdead));

        return DeployResult({
            newContract: pool,
            onInstallOps: CallBuilder.build(
                _authorizeFactory(msg.sender, pool, pool),
                _authorizeFactory(msg.sender, pool, quotaKeeper),
                _setQuotaKeeper(pool, quotaKeeper)
            )
        });
    }

    function computePoolAddress(
        address marketConfigurator,
        address underlying,
        string calldata name,
        string calldata symbol
    ) external view override returns (address) {
        return _computePoolAddress(marketConfigurator, underlying, name, symbol);
    }

    // ------------ //
    // MARKET HOOKS //
    // ------------ //

    function onCreateMarket(address pool, address, address interestRateModel, address rateKeeper, address, address)
        external
        view
        override(AbstractMarketFactory, IMarketFactory)
        returns (Call[] memory)
    {
        return CallBuilder.build(
            _setInterestRateModel(pool, interestRateModel), _setRateKeeper(_quotaKeeper(pool), rateKeeper)
        );
    }

    function onShutdownMarket(address pool)
        external
        view
        override(AbstractMarketFactory, IMarketFactory)
        returns (Call[] memory)
    {
        if (IPoolV3(pool).totalBorrowed() != 0) {
            revert CantShutdownMarketWithNonZeroDebtException(pool);
        }

        return CallBuilder.build(_setTotalDebtLimit(pool, 0));
    }

    function onCreateCreditSuite(address creditManager)
        external
        view
        override(AbstractMarketFactory, IMarketFactory)
        returns (Call[] memory)
    {
        address pool = ICreditManagerV3(creditManager).pool();

        return CallBuilder.build(
            _setCreditManagerDebtLimit(pool, creditManager, 0), _addCreditManager(_quotaKeeper(pool), creditManager)
        );
    }

    function onShutdownCreditSuite(address creditManager)
        external
        view
        override(AbstractMarketFactory, IMarketFactory)
        returns (Call[] memory)
    {
        address pool = ICreditManagerV3(creditManager).pool();

        if (IPoolV3(pool).creditManagerBorrowed(creditManager) != 0) {
            revert CantShutdownCreditSuiteWithNonZeroDebtException(creditManager);
        }

        return CallBuilder.build(_setCreditManagerDebtLimit(pool, creditManager, 0));
    }

    function onUpdateInterestRateModel(address pool, address newInterestRateModel, address)
        external
        pure
        override(AbstractMarketFactory, IMarketFactory)
        returns (Call[] memory)
    {
        return CallBuilder.build(_setInterestRateModel(pool, newInterestRateModel));
    }

    function onUpdateRateKeeper(address pool, address newRateKeeper, address)
        external
        view
        override(AbstractMarketFactory, IMarketFactory)
        returns (Call[] memory)
    {
        return CallBuilder.build(_setRateKeeper(_quotaKeeper(pool), newRateKeeper));
    }

    // ------------- //
    // CONFIGURATION //
    // ------------- //

    function configure(address pool, bytes calldata callData)
        external
        view
        override(AbstractFactory, IFactory)
        returns (Call[] memory)
    {
        bytes4 selector = bytes4(callData);
        if (
            selector == IConfigureActions.setTotalDebtLimit.selector
                || selector == IConfigureActions.setCreditManagerDebtLimit.selector
                || selector == IConfigureActions.pause.selector || selector == IConfigureActions.unpause.selector
        ) {
            return CallBuilder.build(Call(pool, callData));
        } else if (selector == IConfigureActions.setTokenLimit.selector) {
            (address token, uint96 limit) = abi.decode(callData[4:], (address, uint96));
            if (limit != 0 && IPriceOracleV3(_priceOracle(pool)).getPrice(token) == 0) {
                revert ZeroPriceFeedException(token);
            }
            return CallBuilder.build(_setTokenLimit(_quotaKeeper(pool), token, limit));
        } else if (selector == IConfigureActions.setTokenQuotaIncreaseFee.selector) {
            return CallBuilder.build(Call(_quotaKeeper(pool), callData));
        } else {
            revert ForbiddenConfigurationCallException(selector);
        }
    }

    function emergencyConfigure(address pool, bytes calldata callData)
        external
        view
        override(AbstractFactory, IFactory)
        returns (Call[] memory)
    {
        bytes4 selector = bytes4(callData);
        if (selector == IEmergencyConfigureActions.setCreditManagerDebtLimitToZero.selector) {
            address creditManager = abi.decode(callData[4:], (address));
            return CallBuilder.build(_setCreditManagerDebtLimit(pool, creditManager, 0));
        } else if (selector == IEmergencyConfigureActions.setTokenLimitToZero.selector) {
            address token = abi.decode(callData[4:], (address));
            return CallBuilder.build(_setTokenLimit(_quotaKeeper(pool), token, 0));
        } else if (selector == IEmergencyConfigureActions.pause.selector) {
            return CallBuilder.build(Call(pool, callData));
        } else {
            revert ForbiddenEmergencyConfigurationCallException(selector);
        }
    }

    // --------- //
    // INTERNALS //
    // --------- //

    function _deployPool(address marketConfigurator, address underlying, string calldata name, string calldata symbol)
        internal
        returns (address)
    {
        bytes memory constructorParams = _buildPoolConstructorParams(marketConfigurator, underlying, name, symbol);
        bytes32 postfix = _getTokenSpecificPostfix(underlying);
        bytes32 salt = bytes32(bytes20(marketConfigurator));
        return _deployLatestPatch({
            contractType: _getContractType(DOMAIN_POOL, postfix),
            minorVersion: version,
            constructorParams: constructorParams,
            salt: salt
        });
    }

    function _computePoolAddress(
        address marketConfigurator,
        address underlying,
        string calldata name,
        string calldata symbol
    ) internal view returns (address) {
        bytes memory constructorParams = _buildPoolConstructorParams(marketConfigurator, underlying, name, symbol);
        bytes32 postfix = _getTokenSpecificPostfix(underlying);
        bytes32 salt = bytes32(bytes20(marketConfigurator));
        return _computeAddressLatestPatch({
            contractType: _getContractType(DOMAIN_POOL, postfix),
            minorVersion: version,
            constructorParams: constructorParams,
            salt: salt,
            deployer: address(this)
        });
    }

    function _buildPoolConstructorParams(
        address marketConfigurator,
        address underlying,
        string calldata name,
        string calldata symbol
    ) internal view returns (bytes memory) {
        address acl = IMarketConfigurator(marketConfigurator).acl();
        address contractsRegister = IMarketConfigurator(marketConfigurator).contractsRegister();
        address treasury = IMarketConfigurator(marketConfigurator).treasury();

        return abi.encode(
            acl, contractsRegister, underlying, treasury, defaultInterestRateModel, type(uint256).max, name, symbol
        );
    }

    function _deployQuotaKeeper(address marketConfigurator, address pool) internal returns (address) {
        return _deployLatestPatch({
            contractType: AP_POOL_QUOTA_KEEPER,
            minorVersion: version,
            constructorParams: abi.encode(pool),
            salt: bytes32(bytes20(marketConfigurator))
        });
    }

    function _setQuotaKeeper(address pool, address quotaKeeper) internal pure returns (Call memory) {
        return Call(pool, abi.encodeCall(IPoolV3.setPoolQuotaKeeper, quotaKeeper));
    }

    function _setInterestRateModel(address pool, address interestRateModel) internal pure returns (Call memory) {
        return Call(pool, abi.encodeCall(IPoolV3.setInterestRateModel, (interestRateModel)));
    }

    function _setTotalDebtLimit(address pool, uint256 limit) internal pure returns (Call memory) {
        return Call(pool, abi.encodeCall(IPoolV3.setTotalDebtLimit, (limit)));
    }

    function _setCreditManagerDebtLimit(address pool, address creditManager, uint256 limit)
        internal
        pure
        returns (Call memory)
    {
        return Call(pool, abi.encodeCall(IPoolV3.setCreditManagerDebtLimit, (creditManager, limit)));
    }

    function _setRateKeeper(address quotaKeeper, address rateKeeper) internal pure returns (Call memory) {
        return Call(quotaKeeper, abi.encodeCall(IPoolQuotaKeeperV3.setGauge, (rateKeeper)));
    }

    function _addCreditManager(address quotaKeeper, address creditManager) internal pure returns (Call memory) {
        return Call(quotaKeeper, abi.encodeCall(IPoolQuotaKeeperV3.addCreditManager, (creditManager)));
    }

    function _setTokenLimit(address quotaKeeper, address token, uint96 limit) internal pure returns (Call memory) {
        return Call(quotaKeeper, abi.encodeCall(IPoolQuotaKeeperV3.setTokenLimit, (token, limit)));
    }
}
