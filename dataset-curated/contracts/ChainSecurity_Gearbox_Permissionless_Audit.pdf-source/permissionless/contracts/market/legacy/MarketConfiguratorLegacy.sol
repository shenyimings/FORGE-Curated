// SPDX-License-Identifier: BUSL-1.1
// Gearbox Protocol. Generalized leverage for DeFi protocols
// (c) Gearbox Foundation, 2024.
pragma solidity ^0.8.23;

import {Address} from "@openzeppelin/contracts/utils/Address.sol";

import {IVersion} from "@gearbox-protocol/core-v3/contracts/interfaces/base/IVersion.sol";
import {ICreditConfiguratorV3} from "@gearbox-protocol/core-v3/contracts/interfaces/ICreditConfiguratorV3.sol";
import {ICreditFacadeV3} from "@gearbox-protocol/core-v3/contracts/interfaces/ICreditFacadeV3.sol";
import {ICreditManagerV3} from "@gearbox-protocol/core-v3/contracts/interfaces/ICreditManagerV3.sol";
import {IPoolQuotaKeeperV3} from "@gearbox-protocol/core-v3/contracts/interfaces/IPoolQuotaKeeperV3.sol";
import {IPoolV3} from "@gearbox-protocol/core-v3/contracts/interfaces/IPoolV3.sol";

import {DefaultLossPolicy} from "../../helpers/DefaultLossPolicy.sol";

import {IACL} from "../../interfaces/IACL.sol";
import {IContractsRegister} from "../../interfaces/IContractsRegister.sol";
import {Call, MarketFactories} from "../../interfaces/Types.sol";

import {
    AP_MARKET_CONFIGURATOR_LEGACY,
    AP_CROSS_CHAIN_GOVERNANCE_PROXY,
    NO_VERSION_CONTROL,
    ROLE_EMERGENCY_LIQUIDATOR,
    ROLE_PAUSABLE_ADMIN,
    ROLE_UNPAUSABLE_ADMIN
} from "../../libraries/ContractLiterals.sol";

import {MarketConfigurator} from "../MarketConfigurator.sol";

interface IACLLegacy {
    function owner() external view returns (address);
    function pendingOwner() external view returns (address);
    function transferOwnership(address newOwner) external;
    function claimOwnership() external;

    function isPausableAdmin(address account) external view returns (bool);
    function addPausableAdmin(address account) external;
    function removePausableAdmin(address account) external;

    function isUnpausableAdmin(address account) external view returns (bool);
    function addUnpausableAdmin(address account) external;
    function removeUnpausableAdmin(address account) external;
}

interface IContractsRegisterLegacy {
    function getPools() external view returns (address[] memory);
    function addPool(address pool) external;
    function getCreditManagers() external view returns (address[] memory);
    function addCreditManager(address creditManager) external;
}

contract MarketConfiguratorLegacy is MarketConfigurator {
    using Address for address;

    /// @notice Contract version
    uint256 public constant override version = 3_10;

    /// @notice Contract type
    bytes32 public constant override contractType = AP_MARKET_CONFIGURATOR_LEGACY;

    address public immutable crossChainGovernanceProxy;

    address public immutable aclLegacy;
    address public immutable contractsRegisterLegacy;
    address public immutable gearStakingLegacy;

    error AddressIsNotPausableAdminException(address admin);
    error AddressIsNotUnpausableAdminException(address admin);
    error CallerIsNotCrossChainGovernanceProxyException(address caller);
    error CallsToLegacyContractsAreForbiddenException();
    error CollateralTokenIsNotQuotedException(address creditManager, address token);
    error CreditManagerIsMisconfiguredException(address creditManager);

    modifier onlyCrossChainGovernanceProxy() {
        if (msg.sender != crossChainGovernanceProxy) revert CallerIsNotCrossChainGovernanceProxyException(msg.sender);
        _;
    }

    /// @dev There's no way to validate that `pausableAdmins_` and `unpausableAdmins_` are exhaustive
    ///      because the legacy ACL contract doesn't provide needed getters, so don't screw up :)
    constructor(
        address addressProvider_,
        address admin_,
        address emergencyAdmin_,
        string memory curatorName_,
        bool deployGovernor_,
        address aclLegacy_,
        address contractsRegisterLegacy_,
        address gearStakingLegacy_,
        address[] memory pausableAdmins_,
        address[] memory unpausableAdmins_,
        address[] memory emergencyLiquidators_
    ) MarketConfigurator(addressProvider_, admin_, emergencyAdmin_, address(0), curatorName_, deployGovernor_) {
        crossChainGovernanceProxy = _getAddressOrRevert(AP_CROSS_CHAIN_GOVERNANCE_PROXY, NO_VERSION_CONTROL);

        aclLegacy = aclLegacy_;
        contractsRegisterLegacy = contractsRegisterLegacy_;
        gearStakingLegacy = gearStakingLegacy_;

        uint256 num = pausableAdmins_.length;
        for (uint256 i; i < num; ++i) {
            address admin = pausableAdmins_[i];
            if (!IACLLegacy(aclLegacy).isPausableAdmin(admin)) revert AddressIsNotPausableAdminException(admin);
            IACL(acl).grantRole(ROLE_PAUSABLE_ADMIN, admin);
            emit GrantRole(ROLE_PAUSABLE_ADMIN, admin);
        }
        num = unpausableAdmins_.length;
        for (uint256 i; i < num; ++i) {
            address admin = unpausableAdmins_[i];
            if (!IACLLegacy(aclLegacy).isUnpausableAdmin(admin)) revert AddressIsNotUnpausableAdminException(admin);
            IACL(acl).grantRole(ROLE_UNPAUSABLE_ADMIN, admin);
            emit GrantRole(ROLE_UNPAUSABLE_ADMIN, admin);
        }
        num = emergencyLiquidators_.length;
        for (uint256 i; i < num; ++i) {
            address liquidator = emergencyLiquidators_[i];
            IACL(acl).grantRole(ROLE_EMERGENCY_LIQUIDATOR, liquidator);
            emit GrantRole(ROLE_EMERGENCY_LIQUIDATOR, liquidator);
        }

        address[] memory pools = IContractsRegisterLegacy(contractsRegisterLegacy).getPools();
        uint256 numPools = pools.length;
        for (uint256 i; i < numPools; ++i) {
            address pool = pools[i];
            if (!_isV3Contract(pool)) continue;

            address[] memory creditManagers = IPoolV3(pool).creditManagers();
            uint256 numCreditManagers = creditManagers.length;
            if (numCreditManagers == 0) continue;

            address quotaKeeper = _quotaKeeper(pool);
            address priceOracle = _priceOracle(creditManagers[0]);
            address interestRateModel = _interestRateModel(pool);
            address rateKeeper = _rateKeeper(quotaKeeper);
            address lossPolicy = address(new DefaultLossPolicy(acl));

            _createMarket(pool, quotaKeeper, priceOracle, interestRateModel, rateKeeper, lossPolicy);

            for (uint256 j; j < numCreditManagers; ++j) {
                address creditManager = creditManagers[j];
                if (!_isV3Contract(creditManager) || _priceOracle(creditManager) != priceOracle) {
                    revert CreditManagerIsMisconfiguredException(creditManager);
                }

                uint256 numTokens = ICreditManagerV3(creditManager).collateralTokensCount();
                for (uint256 k = 1; k < numTokens; ++k) {
                    address token = ICreditManagerV3(creditManager).getTokenByMask(1 << k);
                    if (!IPoolQuotaKeeperV3(quotaKeeper).isQuotedToken(token)) {
                        revert CollateralTokenIsNotQuotedException(creditManager, token);
                    }
                }

                _createCreditSuite(creditManager);
            }
        }
    }

    function _createMarket(
        address pool,
        address quotaKeeper,
        address priceOracle,
        address interestRateModel,
        address rateKeeper,
        address lossPolicy
    ) internal {
        IContractsRegister(contractsRegister).registerMarket(pool, priceOracle, lossPolicy);
        MarketFactories memory factories = _getLatestMarketFactories(version);
        _marketFactories[pool] = factories;
        _authorizeFactory(factories.poolFactory, pool, pool);
        _authorizeFactory(factories.poolFactory, pool, quotaKeeper);
        _authorizeFactory(factories.priceOracleFactory, pool, priceOracle);
        _authorizeFactory(factories.interestRateModelFactory, pool, interestRateModel);
        _authorizeFactory(factories.rateKeeperFactory, pool, rateKeeper);
        _authorizeFactory(factories.lossPolicyFactory, pool, lossPolicy);

        emit CreateMarket(pool, priceOracle, interestRateModel, rateKeeper, lossPolicy, factories);
    }

    function _createCreditSuite(address creditManager) internal {
        IContractsRegister(contractsRegister).registerCreditSuite(creditManager);

        address factory = _getLatestCreditFactory(version);
        _creditFactories[creditManager] = factory;
        address creditConfigurator = ICreditManagerV3(creditManager).creditConfigurator();
        _authorizeFactory(factory, creditManager, creditConfigurator);
        _authorizeFactory(factory, creditManager, ICreditManagerV3(creditManager).creditFacade());
        address[] memory adapters = ICreditConfiguratorV3(creditConfigurator).allowedAdapters();
        uint256 numAdapters = adapters.length;
        for (uint256 k; k < numAdapters; ++k) {
            _authorizeFactory(factory, creditManager, adapters[k]);
        }

        emit CreateCreditSuite(creditManager, factory);
    }

    // ------------- //
    // CONFIGURATION //
    // ------------- //

    function finalizeMigration() external onlyCrossChainGovernanceProxy {
        // NOTE: on some chains, legacy ACL implements a 2-step ownership transfer
        try IACLLegacy(aclLegacy).pendingOwner() {
            IACLLegacy(aclLegacy).claimOwnership();
        } catch {}

        IACLLegacy(aclLegacy).addPausableAdmin(address(this));
        IACLLegacy(aclLegacy).addUnpausableAdmin(address(this));
    }

    function configureGearStaking(bytes calldata data) external onlyCrossChainGovernanceProxy {
        gearStakingLegacy.functionCall(data);
    }

    // --------- //
    // INTERNALS //
    // --------- //

    function _grantRole(bytes32 role, address account) internal override {
        super._grantRole(role, account);
        if (role == ROLE_PAUSABLE_ADMIN) IACLLegacy(aclLegacy).addPausableAdmin(account);
        else if (role == ROLE_UNPAUSABLE_ADMIN) IACLLegacy(aclLegacy).addUnpausableAdmin(account);
    }

    function _revokeRole(bytes32 role, address account) internal override {
        super._revokeRole(role, account);
        if (role == ROLE_PAUSABLE_ADMIN) IACLLegacy(aclLegacy).removePausableAdmin(account);
        else if (role == ROLE_UNPAUSABLE_ADMIN) IACLLegacy(aclLegacy).removeUnpausableAdmin(account);
    }

    function _registerMarket(address pool, address priceOracle, address lossPolicy) internal override {
        super._registerMarket(pool, priceOracle, lossPolicy);
        IContractsRegisterLegacy(contractsRegisterLegacy).addPool(pool);
    }

    function _registerCreditSuite(address creditManager) internal override {
        super._registerCreditSuite(creditManager);
        IContractsRegisterLegacy(contractsRegisterLegacy).addCreditManager(creditManager);
    }

    function _validateCallTarget(address target, address factory) internal override {
        super._validateCallTarget(target, factory);
        if (target == aclLegacy || target == contractsRegisterLegacy || target == gearStakingLegacy) {
            revert CallsToLegacyContractsAreForbiddenException();
        }
    }

    function _isV3Contract(address contract_) internal view returns (bool) {
        try IVersion(contract_).version() returns (uint256 version_) {
            return version_ >= 300 && version_ < 400;
        } catch {
            return false;
        }
    }

    function _priceOracle(address creditManager) internal view returns (address) {
        return ICreditManagerV3(creditManager).priceOracle();
    }
}
