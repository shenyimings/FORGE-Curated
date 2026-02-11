// SPDX-License-Identifier: MIT
// Gearbox Protocol. Generalized leverage for DeFi protocols
// (c) Gearbox Foundation, 2025.
pragma solidity ^0.8.23;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/security/Pausable.sol";

import {IPoolQuotaKeeperV3} from "@gearbox-protocol/core-v3/contracts/interfaces/IPoolQuotaKeeperV3.sol";
import {IPoolV3} from "@gearbox-protocol/core-v3/contracts/interfaces/IPoolV3.sol";
import {IRateKeeper} from "@gearbox-protocol/core-v3/contracts/interfaces/base/IRateKeeper.sol";
import {RAY} from "@gearbox-protocol/core-v3/contracts/libraries/Constants.sol";

import {IACL} from "@gearbox-protocol/permissionless/contracts/interfaces/IACL.sol";
import {IContractsRegister} from "@gearbox-protocol/permissionless/contracts/interfaces/IContractsRegister.sol";
import {IMarketConfigurator} from "@gearbox-protocol/permissionless/contracts/interfaces/IMarketConfigurator.sol";
import {
    ROLE_EMERGENCY_LIQUIDATOR,
    ROLE_PAUSABLE_ADMIN,
    ROLE_UNPAUSABLE_ADMIN
} from "@gearbox-protocol/permissionless/contracts/libraries/ContractLiterals.sol";

import {ICreditSuiteCompressor} from "../interfaces/ICreditSuiteCompressor.sol";
import {IMarketCompressor} from "../interfaces/IMarketCompressor.sol";
import {IPriceFeedCompressor} from "../interfaces/IPriceFeedCompressor.sol";
import {ITokenCompressor} from "../interfaces/ITokenCompressor.sol";

import {BaseLib} from "../libraries/BaseLib.sol";
import {
    AP_MARKET_COMPRESSOR,
    AP_TOKEN_COMPRESSOR,
    AP_PRICE_FEED_COMPRESSOR,
    AP_CREDIT_SUITE_COMPRESSOR
} from "../libraries/Literals.sol";

import {GaugeSerializer} from "../serializers/core/GaugeSerializer.sol";
import {LinearInterestRateModelSerializer} from "../serializers/core/LinearInterestRateModelSerializer.sol";

import {BaseParams, BaseState} from "../types/BaseState.sol";
import {CreditSuiteData} from "../types/CreditSuiteData.sol";
import {MarketFilter} from "../types/Filters.sol";
import {
    CreditManagerDebtParams,
    MarketData,
    PoolState,
    QuotaKeeperState,
    QuotaTokenParams,
    Rate,
    RateKeeperState
} from "../types/MarketData.sol";
import {PriceOracleState} from "../types/PriceOracleState.sol";
import {TokenData} from "../types/TokenData.sol";

import {BaseCompressor} from "./BaseCompressor.sol";

contract MarketCompressor is BaseCompressor, IMarketCompressor {
    using BaseLib for address;

    uint256 public constant override version = 3_10;
    bytes32 public constant override contractType = AP_MARKET_COMPRESSOR;

    address internal immutable _gaugeSerializer;
    address internal immutable _linearInterestRateModelSerializer;

    constructor(address addressProvider_) BaseCompressor(addressProvider_) {
        _gaugeSerializer = address(new GaugeSerializer());
        _linearInterestRateModelSerializer = address(new LinearInterestRateModelSerializer());
    }

    function getMarkets(MarketFilter memory filter) external view override returns (MarketData[] memory result) {
        Pool[] memory pools = _getPools(filter);
        result = new MarketData[](pools.length);
        for (uint256 i; i < pools.length; ++i) {
            result[i] = getMarketData(pools[i].addr, pools[i].configurator);
        }
    }

    function getMarketData(address pool) external view override returns (MarketData memory result) {
        // NOTE: After migration to v3.1.x governance system, pool's market configurator will be the owner of its ACL.
        // Before that, however, there's no way to recover it unless it is provided directly or with market filter.
        return getMarketData(pool, Ownable(IPoolV3(pool).acl()).owner());
    }

    function getMarketData(address pool, address configurator)
        public
        view
        override
        returns (MarketData memory result)
    {
        result.acl = IMarketConfigurator(configurator).acl();
        result.contractsRegister = IMarketConfigurator(configurator).contractsRegister();
        result.treasury = IMarketConfigurator(configurator).treasury();

        result.pool = getPoolState(pool);
        result.quotaKeeper = getQuotaKeeperState(result.pool.quotaKeeper);
        result.rateKeeper = getRateKeeperState(result.quotaKeeper.rateKeeper);
        result.interestRateModel = getInterestRateModelState(result.pool.interestRateModel);

        address tokenCompressor = _getLatestAddress(AP_TOKEN_COMPRESSOR, 3_10);
        address[] memory tokens = _getTokens(pool);
        result.tokens = ITokenCompressor(tokenCompressor).getTokens(tokens);

        address creditSuiteCompressor = _getLatestAddress(AP_CREDIT_SUITE_COMPRESSOR, 3_10);
        address[] memory creditManagers = IContractsRegister(result.contractsRegister).getCreditManagers(pool);
        result.creditManagers = new CreditSuiteData[](creditManagers.length);
        for (uint256 i; i < creditManagers.length; ++i) {
            result.creditManagers[i] =
                ICreditSuiteCompressor(creditSuiteCompressor).getCreditSuiteData(creditManagers[i]);
        }

        address priceFeedCompressor = _getLatestAddress(AP_PRICE_FEED_COMPRESSOR, 3_10);
        result.priceOracle =
            IPriceFeedCompressor(priceFeedCompressor).getPriceOracleState(_getPriceOracle(pool, configurator), tokens);
        result.lossPolicy = getLossPolicyState(_getLossPolicy(pool, configurator));

        result.configurator = configurator;
        result.pausableAdmins = IACL(result.acl).getRoleHolders(ROLE_PAUSABLE_ADMIN);
        result.unpausableAdmins = IACL(result.acl).getRoleHolders(ROLE_UNPAUSABLE_ADMIN);
        result.emergencyLiquidators = IACL(result.acl).getRoleHolders(ROLE_EMERGENCY_LIQUIDATOR);
    }

    function getPoolState(address pool) public view override returns (PoolState memory result) {
        result.underlying = IPoolV3(pool).underlyingToken();
        result.baseParams = pool.getBaseParams(_appendPostfix("POOL", result.underlying), address(0));

        result.symbol = IPoolV3(pool).symbol();
        result.name = IPoolV3(pool).name();
        result.decimals = IPoolV3(pool).decimals();
        result.totalSupply = IPoolV3(pool).totalSupply();

        result.quotaKeeper = IPoolV3(pool).poolQuotaKeeper();
        result.interestRateModel = IPoolV3(pool).interestRateModel();

        result.availableLiquidity = IPoolV3(pool).availableLiquidity();
        result.expectedLiquidity = IPoolV3(pool).expectedLiquidity();
        result.baseInterestIndex = IPoolV3(pool).baseInterestIndex();
        result.baseInterestRate = IPoolV3(pool).baseInterestRate();
        result.dieselRate = IPoolV3(pool).convertToAssets(RAY);
        result.supplyRate = IPoolV3(pool).supplyRate();
        result.withdrawFee = IPoolV3(pool).withdrawFee();

        result.totalBorrowed = IPoolV3(pool).totalBorrowed();
        result.totalDebtLimit = IPoolV3(pool).totalDebtLimit();
        address[] memory creditManagers = IPoolV3(pool).creditManagers();
        result.creditManagerDebtParams = new CreditManagerDebtParams[](creditManagers.length);
        for (uint256 i; i < creditManagers.length; ++i) {
            result.creditManagerDebtParams[i] = CreditManagerDebtParams({
                creditManager: creditManagers[i],
                borrowed: IPoolV3(pool).creditManagerBorrowed(creditManagers[i]),
                limit: IPoolV3(pool).creditManagerDebtLimit(creditManagers[i]),
                available: IPoolV3(pool).creditManagerBorrowable(creditManagers[i])
            });
        }

        result.baseInterestIndexLU = IPoolV3(pool).baseInterestIndexLU();
        result.expectedLiquidityLU = IPoolV3(pool).expectedLiquidityLU();
        result.quotaRevenue = IPoolV3(pool).quotaRevenue();
        result.lastBaseInterestUpdate = IPoolV3(pool).lastBaseInterestUpdate();
        result.lastQuotaRevenueUpdate = IPoolV3(pool).lastQuotaRevenueUpdate();

        result.isPaused = Pausable(pool).paused();
    }

    function getQuotaKeeperState(address quotaKeeper) public view override returns (QuotaKeeperState memory result) {
        result.baseParams = quotaKeeper.getBaseParams("POOL_QUOTA_KEEPER", address(0));

        result.rateKeeper = IPoolQuotaKeeperV3(quotaKeeper).gauge();

        address[] memory tokens = IPoolQuotaKeeperV3(quotaKeeper).quotedTokens();
        result.quotas = new QuotaTokenParams[](tokens.length);
        for (uint256 i; i < tokens.length; ++i) {
            result.quotas[i].token = tokens[i];
            (
                result.quotas[i].rate,
                result.quotas[i].cumulativeIndexLU,
                result.quotas[i].quotaIncreaseFee,
                result.quotas[i].totalQuoted,
                result.quotas[i].limit,
                result.quotas[i].isActive
            ) = IPoolQuotaKeeperV3(quotaKeeper).getTokenQuotaParams(tokens[i]);
        }

        result.creditManagers = IPoolQuotaKeeperV3(quotaKeeper).creditManagers();

        result.lastQuotaRateUpdate = IPoolQuotaKeeperV3(quotaKeeper).lastQuotaRateUpdate();
    }

    function getRateKeeperState(address rateKeeper) public view override returns (RateKeeperState memory result) {
        result.baseParams = rateKeeper.getBaseParams("RATE_KEEPER::GAUGE", _gaugeSerializer);

        address quotaKeeper = IPoolV3(IRateKeeper(rateKeeper).pool()).poolQuotaKeeper();
        address[] memory tokens = IPoolQuotaKeeperV3(quotaKeeper).quotedTokens();
        uint16[] memory rates = IRateKeeper(rateKeeper).getRates(tokens);
        result.rates = new Rate[](tokens.length);
        for (uint256 i; i < tokens.length; ++i) {
            result.rates[i].token = tokens[i];
            result.rates[i].rate = rates[i];
        }
    }

    function getInterestRateModelState(address interestRateModel) public view override returns (BaseState memory) {
        return interestRateModel.getBaseState("IRM::LINEAR", _linearInterestRateModelSerializer);
    }

    function getLossPolicyState(address lossPolicy) public view override returns (BaseState memory) {
        return lossPolicy.getBaseState("LOSS_POLICY::DEFAULT", address(0));
    }
}
