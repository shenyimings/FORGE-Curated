// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import {AP_PRICE_FEED_STORE} from "@gearbox-protocol/permissionless/contracts/libraries/ContractLiterals.sol";
import {LibString} from "@solady/utils/LibString.sol";
import {BitMask} from "@gearbox-protocol/core-v3/contracts/libraries/BitMask.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {PoolV3} from "@gearbox-protocol/core-v3/contracts/pool/PoolV3.sol";
import {GearStakingV3} from "@gearbox-protocol/core-v3/contracts/core/GearStakingV3.sol";
import {PriceOracleV3} from "@gearbox-protocol/core-v3/contracts/core/PriceOracleV3.sol";
import {PoolQuotaKeeperV3} from "@gearbox-protocol/core-v3/contracts/pool/PoolQuotaKeeperV3.sol";
import {TumblerV3} from "@gearbox-protocol/core-v3/contracts/pool/TumblerV3.sol";
import {IPoolV3} from "@gearbox-protocol/core-v3/contracts/interfaces/IPoolV3.sol";
import {
    IPoolQuotaKeeperV3, TokenQuotaParams
} from "@gearbox-protocol/core-v3/contracts/interfaces/IPoolQuotaKeeperV3.sol";
import {IAdapter} from "@gearbox-protocol/core-v3/contracts/interfaces/base/IAdapter.sol";

import {IACL} from "@gearbox-protocol/governance/contracts/interfaces/IACL.sol";

import {ICreditManagerV3} from "@gearbox-protocol/core-v3/contracts/interfaces/ICreditManagerV3.sol";
import {CreditFacadeV3} from "@gearbox-protocol/core-v3/contracts/credit/CreditFacadeV3.sol";
import {CreditConfiguratorV3} from "@gearbox-protocol/core-v3/contracts/credit/CreditConfiguratorV3.sol";
import {IPriceFeed} from "@gearbox-protocol/core-v3/contracts/interfaces/base/IPriceFeed.sol";

import {IMarketConfiguratorFactory} from
    "@gearbox-protocol/permissionless/contracts/interfaces/IMarketConfiguratorFactory.sol";
import {
    IMarketConfigurator,
    DeployParams
} from "@gearbox-protocol/permissionless/contracts/interfaces/IMarketConfigurator.sol";
import {IContractsRegister} from "@gearbox-protocol/permissionless/contracts/interfaces/IContractsRegister.sol";
import {IPriceFeedStore} from "@gearbox-protocol/permissionless/contracts/interfaces/IPriceFeedStore.sol";
import {IAddressProvider} from "@gearbox-protocol/permissionless/contracts/interfaces/IAddressProvider.sol";

import {
    CreditManagerParams,
    CreditFacadeParams
} from "@gearbox-protocol/permissionless/contracts/interfaces/factories/ICreditConfigureActions.sol";

import {PriceFeedCloner} from "./PriceFeedCloner.sol";
import {IntegrationCloner} from "./IntegrationCloner.sol";

interface IAddressProviderV3Legacy {
    function getAddressOrRevert(bytes32 key, uint256 _version) external view returns (address result);
}

interface IOldContractsRegister {
    function getPools() external view returns (address[] memory pools);
}

interface IOldCreditConfigurator {
    function emergencyLiquidators() external view returns (address[] memory emergencyLiquidators);
}

contract MarketCloner is Test {
    using LibString for bytes32;
    using BitMask for uint256;

    address mcFactory;
    address addressProvider;
    address marketConfigurator;

    address newPool;
    address newPoolQuotaKeeper;
    address newTumbler;
    address newPriceOracle;

    address oldPriceOracle;

    mapping(address oldCreditManager => address newCreditManager) oldToNewCreditManager;

    PriceFeedCloner pfCloner;
    IntegrationCloner intCloner;

    function _setUpCloner(address _mcFactory, address _addressProvider) internal {
        mcFactory = _mcFactory;
        addressProvider = _addressProvider;
    }

    function _cloneMarket(address pool) internal {
        if (IPoolV3(pool).creditManagers().length == 0) {
            revert("MarketCloner: no credit managers in pool, nothing to clone");
        }

        oldPriceOracle = _getPriceOracle(pool);

        marketConfigurator =
            IMarketConfiguratorFactory(mcFactory).createMarketConfigurator(address(this), address(this), "test", false);

        pfCloner = new PriceFeedCloner(marketConfigurator);

        pfCloner.deployZeroPriceFeed();

        intCloner = new IntegrationCloner(marketConfigurator);

        _createMarket(pool);

        _migratePoolTokens(pool);

        address[] memory creditManagers = IPoolV3(pool).creditManagers();

        for (uint256 i = 0; i < creditManagers.length; ++i) {
            _migrateCreditManager(creditManagers[i], i);
        }

        vm.roll(block.number + 1);
    }

    function _createMarket(address oldPool) internal {
        address underlying = IPoolV3(oldPool).asset();

        deal(underlying, address(marketConfigurator), 1e18);

        newPool = IMarketConfigurator(marketConfigurator).previewCreateMarket(3_10, underlying, "test", "dtest");

        DeployParams memory interestRateModelParams = DeployParams({
            postfix: "LINEAR",
            salt: 0,
            constructorParams: abi.encode(100, 200, 100, 100, 200, 300, false)
        });
        DeployParams memory rateKeeperParams =
            DeployParams({postfix: "TUMBLER", salt: 0, constructorParams: abi.encode(newPool, 0)});
        DeployParams memory lossPolicyParams =
            DeployParams({postfix: "ALIASED", salt: 0, constructorParams: abi.encode(newPool, addressProvider)});

        address underlyingPriceFeed = PriceOracleV3(oldPriceOracle).priceFeeds(underlying);

        _addUnderlyingToPriceFeedStore(underlying, underlyingPriceFeed);

        newPool = IMarketConfigurator(marketConfigurator).createMarket(
            3_10,
            underlying,
            "test",
            "dtest",
            interestRateModelParams,
            rateKeeperParams,
            lossPolicyParams,
            underlyingPriceFeed
        );

        address contractsRegister = IMarketConfigurator(marketConfigurator).contractsRegister();

        newPriceOracle = IContractsRegister(contractsRegister).getPriceOracle(newPool);

        newPoolQuotaKeeper = IPoolV3(newPool).poolQuotaKeeper();
        newTumbler = IPoolQuotaKeeperV3(newPoolQuotaKeeper).gauge();
    }

    function _addUnderlyingToPriceFeedStore(address underlying, address underlyingPriceFeed) internal {
        address priceFeedStore = IAddressProvider(addressProvider).getAddressOrRevert(AP_PRICE_FEED_STORE, 0);

        address owner = Ownable(priceFeedStore).owner();

        uint32 stalenessPeriod;

        try IPriceFeed(underlyingPriceFeed).skipPriceCheck() returns (bool skipCheck) {
            if (skipCheck) {
                stalenessPeriod = 0;
            } else {
                stalenessPeriod = 86400;
            }
        } catch {
            stalenessPeriod = 86400;
        }

        vm.prank(owner);
        try IPriceFeedStore(priceFeedStore).addPriceFeed(underlyingPriceFeed, stalenessPeriod, "test") {} catch {}

        vm.prank(owner);
        try IPriceFeedStore(priceFeedStore).allowPriceFeed(underlying, underlyingPriceFeed) {} catch {}
    }

    function _getPriceOracle(address pool) internal view returns (address) {
        address[] memory creditManagers = IPoolV3(pool).creditManagers();

        address creditManager = creditManagers[0];

        return ICreditManagerV3(creditManager).priceOracle();
    }

    function _migratePoolTokens(address oldPool) internal {
        address[] memory quotedTokens =
            IPoolQuotaKeeperV3(IPoolQuotaKeeperV3(IPoolV3(oldPool).poolQuotaKeeper())).quotedTokens();

        for (uint256 j = 0; j < quotedTokens.length; ++j) {
            address token = quotedTokens[j];

            (address priceFeed, uint32 stalenessPeriod) = pfCloner.migratePriceFeed(oldPriceOracle, token, false);

            (address reservePriceFeed, uint32 reserveStalenessPeriod) =
                pfCloner.migratePriceFeed(oldPriceOracle, token, true);

            if (intCloner.migratePhantomToken(token) != address(0)) {
                address newPhantomToken = intCloner.oldToNewPhantomToken(token);

                vm.prank(marketConfigurator);
                PriceOracleV3(newPriceOracle).setPriceFeed(newPhantomToken, priceFeed, stalenessPeriod);

                if (reservePriceFeed != address(0)) {
                    vm.prank(marketConfigurator);
                    PriceOracleV3(newPriceOracle).setReservePriceFeed(
                        newPhantomToken, reservePriceFeed, reserveStalenessPeriod
                    );
                }

                address poolQuotaKeeper = IPoolV3(oldPool).poolQuotaKeeper();

                (,,,, uint96 limit,) = IPoolQuotaKeeperV3(poolQuotaKeeper).getTokenQuotaParams(token);

                vm.prank(marketConfigurator);
                TumblerV3(newTumbler).addToken(newPhantomToken);

                vm.prank(marketConfigurator);
                IPoolQuotaKeeperV3(newPoolQuotaKeeper).setTokenLimit(newPhantomToken, limit);
            } else {
                vm.prank(marketConfigurator);
                PriceOracleV3(newPriceOracle).setPriceFeed(token, priceFeed, stalenessPeriod);

                if (reservePriceFeed != address(0)) {
                    vm.prank(marketConfigurator);
                    PriceOracleV3(newPriceOracle).setReservePriceFeed(token, reservePriceFeed, reserveStalenessPeriod);
                }

                address poolQuotaKeeper = IPoolV3(oldPool).poolQuotaKeeper();

                (,,,, uint96 limit,) = IPoolQuotaKeeperV3(poolQuotaKeeper).getTokenQuotaParams(token);

                vm.prank(marketConfigurator);
                TumblerV3(newTumbler).addToken(token);

                vm.prank(marketConfigurator);
                IPoolQuotaKeeperV3(newPoolQuotaKeeper).setTokenLimit(token, limit);
            }

            vm.prank(marketConfigurator);
            TumblerV3(newTumbler).updateRates();
        }
    }

    function _migrateCreditManager(address oldCreditManager, uint256 i) internal {
        address newCreditManager = _deployCreditManager(oldCreditManager, i);

        oldToNewCreditManager[oldCreditManager] = newCreditManager;

        _addTokensToCM(oldCreditManager, newCreditManager);

        _migrateAdapters(oldCreditManager, newCreditManager);
    }

    function _deployCreditManager(address oldCreditManager, uint256 i) internal returns (address) {
        address oldCreditFacade = ICreditManagerV3(oldCreditManager).creditFacade();

        DeployParams memory accountFactoryParams =
            DeployParams({postfix: "DEFAULT", salt: bytes32(i), constructorParams: abi.encode(addressProvider)});

        CreditManagerParams memory creditManagerParams;

        {
            (
                uint16 feeInterest,
                uint16 feeLiquidation,
                uint16 liquidationDiscount,
                uint16 feeLiquidationExpired,
                uint16 liquidationDiscountExpired
            ) = ICreditManagerV3(oldCreditManager).fees();

            (uint128 minDebt, uint128 maxDebt) = CreditFacadeV3(oldCreditFacade).debtLimits();

            if (minDebt < maxDebt * ICreditManagerV3(oldCreditManager).maxEnabledTokens() / 100) {
                maxDebt = minDebt * 100 / ICreditManagerV3(oldCreditManager).maxEnabledTokens();
            }

            uint8 maxEnabledTokens = ICreditManagerV3(oldCreditManager).maxEnabledTokens();

            creditManagerParams = CreditManagerParams({
                maxEnabledTokens: maxEnabledTokens,
                feeInterest: feeInterest,
                feeLiquidation: feeLiquidation,
                liquidationPremium: 10000 - liquidationDiscount,
                feeLiquidationExpired: feeLiquidationExpired,
                liquidationPremiumExpired: 10000 - liquidationDiscountExpired,
                minDebt: minDebt,
                maxDebt: maxDebt,
                name: "Credit Manager",
                accountFactoryParams: accountFactoryParams
            });
        }

        CreditFacadeParams memory facadeParams =
            CreditFacadeParams({degenNFT: address(0), expirable: false, migrateBotList: false});

        bytes memory creditSuiteParams = abi.encode(creditManagerParams, facadeParams);

        return IMarketConfigurator(marketConfigurator).createCreditSuite(3_10, address(newPool), creditSuiteParams);
    }

    function _addTokensToCM(address oldCreditManager, address newCreditManager) internal {
        uint256 collateralTokensCount = ICreditManagerV3(oldCreditManager).collateralTokensCount();

        address creditConfigurator = ICreditManagerV3(newCreditManager).creditConfigurator();

        address[] memory phantomTokens = intCloner.phantomTokens();
        uint16[] memory ptLt = new uint16[](phantomTokens.length);
        uint256 k = 0;

        for (uint256 i = 1; i < collateralTokensCount; ++i) {
            (address token, uint16 lt) = ICreditManagerV3(oldCreditManager).collateralTokenByMask(1 << i);

            if (intCloner.oldToNewPhantomToken(token) != address(0)) {
                ptLt[k] = lt;
                k++;
                continue;
            }

            vm.prank(marketConfigurator);
            CreditConfiguratorV3(creditConfigurator).addCollateralToken(token, lt);
        }

        for (uint256 i = 0; i < phantomTokens.length; ++i) {
            vm.prank(marketConfigurator);
            CreditConfiguratorV3(creditConfigurator).addCollateralToken(phantomTokens[i], ptLt[i]);
        }
    }

    function _migrateAdapters(address oldCreditManager, address newCreditManager) internal {
        address creditConfigurator = ICreditManagerV3(oldCreditManager).creditConfigurator();

        address[] memory allowedAdapters = CreditConfiguratorV3(creditConfigurator).allowedAdapters();

        creditConfigurator = ICreditManagerV3(newCreditManager).creditConfigurator();

        for (uint256 i = 0; i < allowedAdapters.length; ++i) {
            address newAdapter = intCloner.migrateAdapter(allowedAdapters[i], oldCreditManager, newCreditManager);

            vm.prank(marketConfigurator);
            CreditConfiguratorV3(creditConfigurator).allowAdapter(newAdapter);
        }

        allowedAdapters = CreditConfiguratorV3(creditConfigurator).allowedAdapters();

        intCloner.configureAdapters(allowedAdapters);
    }

    function _getNewPhantomToken(address oldPhantomToken) internal view returns (address) {
        return intCloner.oldToNewPhantomToken(oldPhantomToken);
    }
}
