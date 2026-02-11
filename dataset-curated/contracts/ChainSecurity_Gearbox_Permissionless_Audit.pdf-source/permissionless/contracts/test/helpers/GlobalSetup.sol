// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.23;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {InstanceManagerHelper} from "../../test/helpers/InstanceManagerHelper.sol";
import {CrossChainMultisig, CrossChainCall} from "../../global/CrossChainMultisig.sol";
import {InstanceManager} from "../../instance/InstanceManager.sol";
import {PriceFeedStore} from "../../instance/PriceFeedStore.sol";
import {IBytecodeRepository} from "../../interfaces/IBytecodeRepository.sol";
import {IAddressProvider} from "../../interfaces/IAddressProvider.sol";
import {IInstanceManager} from "../../interfaces/IInstanceManager.sol";

import {IWETH} from "@gearbox-protocol/core-v3/contracts/interfaces/external/IWETH.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {
    AP_ACCOUNT_FACTORY_DEFAULT,
    AP_BOT_LIST,
    AP_GEAR_STAKING,
    AP_PRICE_FEED_STORE,
    AP_INTEREST_RATE_MODEL_FACTORY,
    AP_CREDIT_FACTORY,
    AP_POOL_FACTORY,
    AP_PRICE_ORACLE_FACTORY,
    AP_RATE_KEEPER_FACTORY,
    AP_MARKET_CONFIGURATOR_FACTORY,
    AP_LOSS_POLICY_FACTORY,
    AP_GOVERNOR,
    AP_TREASURY_SPLITTER,
    AP_POOL,
    AP_POOL_QUOTA_KEEPER,
    AP_PRICE_ORACLE,
    AP_MARKET_CONFIGURATOR,
    AP_ACL,
    AP_CONTRACTS_REGISTER,
    AP_INTEREST_RATE_MODEL_LINEAR,
    AP_RATE_KEEPER_TUMBLER,
    AP_RATE_KEEPER_GAUGE,
    AP_LOSS_POLICY_DEFAULT,
    AP_CREDIT_MANAGER,
    AP_CREDIT_FACADE,
    AP_CREDIT_CONFIGURATOR
} from "../../libraries/ContractLiterals.sol";
import {SignedProposal, Bytecode} from "../../interfaces/Types.sol";

import {CreditFactory} from "../../factories/CreditFactory.sol";
import {InterestRateModelFactory} from "../../factories/InterestRateModelFactory.sol";
import {LossPolicyFactory} from "../../factories/LossPolicyFactory.sol";
import {PoolFactory} from "../../factories/PoolFactory.sol";
import {PriceOracleFactory} from "../../factories/PriceOracleFactory.sol";
import {RateKeeperFactory} from "../../factories/RateKeeperFactory.sol";

import {MarketConfigurator} from "../../market/MarketConfigurator.sol";
import {MarketConfiguratorFactory} from "../../instance/MarketConfiguratorFactory.sol";
import {ACL} from "../../market/ACL.sol";
import {ContractsRegister} from "../../market/ContractsRegister.sol";
import {Governor} from "../../market/Governor.sol";
import {TreasurySplitter} from "../../market/TreasurySplitter.sol";

// Core contracts
import {BotListV3} from "@gearbox-protocol/core-v3/contracts/core/BotListV3.sol";
import {GearStakingV3} from "@gearbox-protocol/core-v3/contracts/core/GearStakingV3.sol";
import {PoolV3} from "@gearbox-protocol/core-v3/contracts/pool/PoolV3.sol";
import {PoolQuotaKeeperV3} from "@gearbox-protocol/core-v3/contracts/pool/PoolQuotaKeeperV3.sol";
import {DefaultAccountFactoryV3} from "@gearbox-protocol/core-v3/contracts/core/DefaultAccountFactoryV3.sol";
import {PriceOracleV3} from "@gearbox-protocol/core-v3/contracts/core/PriceOracleV3.sol";
import {LinearInterestRateModelV3} from "@gearbox-protocol/core-v3/contracts/pool/LinearInterestRateModelV3.sol";
import {TumblerV3} from "@gearbox-protocol/core-v3/contracts/pool/TumblerV3.sol";
import {GaugeV3} from "@gearbox-protocol/core-v3/contracts/pool/GaugeV3.sol";
import {DefaultLossPolicy} from "../../helpers/DefaultLossPolicy.sol";
import {CreditManagerV3} from "@gearbox-protocol/core-v3/contracts/credit/CreditManagerV3.sol";
import {CreditFacadeV3} from "@gearbox-protocol/core-v3/contracts/credit/CreditFacadeV3.sol";
import {CreditConfiguratorV3} from "@gearbox-protocol/core-v3/contracts/credit/CreditConfiguratorV3.sol";

// Adapters
import {EqualizerRouterAdapter} from
    "@gearbox-protocol/integrations-v3/contracts/adapters/equalizer/EqualizerRouterAdapter.sol";
import {BalancerV2VaultAdapter} from
    "@gearbox-protocol/integrations-v3/contracts/adapters/balancer/BalancerV2VaultAdapter.sol";
import {CamelotV3Adapter} from "@gearbox-protocol/integrations-v3/contracts/adapters/camelot/CamelotV3Adapter.sol";
import {YearnV2Adapter} from "@gearbox-protocol/integrations-v3/contracts/adapters/yearn/YearnV2.sol";
import {ConvexV1BoosterAdapter} from "@gearbox-protocol/integrations-v3/contracts/adapters/convex/ConvexV1_Booster.sol";
import {ConvexV1BaseRewardPoolAdapter} from
    "@gearbox-protocol/integrations-v3/contracts/adapters/convex/ConvexV1_BaseRewardPool.sol";
import {ZircuitPoolAdapter} from "@gearbox-protocol/integrations-v3/contracts/adapters/zircuit/ZircuitPoolAdapter.sol";
import {WstETHV1Adapter} from "@gearbox-protocol/integrations-v3/contracts/adapters/lido/WstETHV1.sol";
import {LidoV1Adapter} from "@gearbox-protocol/integrations-v3/contracts/adapters/lido/LidoV1.sol";
import {UniswapV3Adapter} from "@gearbox-protocol/integrations-v3/contracts/adapters/uniswap/UniswapV3.sol";
import {UniswapV2Adapter} from "@gearbox-protocol/integrations-v3/contracts/adapters/uniswap/UniswapV2.sol";
import {MellowVaultAdapter} from "@gearbox-protocol/integrations-v3/contracts/adapters/mellow/MellowVaultAdapter.sol";
import {Mellow4626VaultAdapter} from
    "@gearbox-protocol/integrations-v3/contracts/adapters/mellow/Mellow4626VaultAdapter.sol";
import {PendleRouterAdapter} from "@gearbox-protocol/integrations-v3/contracts/adapters/pendle/PendleRouterAdapter.sol";
import {CurveV1Adapter2Assets} from "@gearbox-protocol/integrations-v3/contracts/adapters/curve/CurveV1_2.sol";
import {CurveV1Adapter4Assets} from "@gearbox-protocol/integrations-v3/contracts/adapters/curve/CurveV1_4.sol";
import {CurveV1AdapterStETH} from "@gearbox-protocol/integrations-v3/contracts/adapters/curve/CurveV1_stETH.sol";
import {CurveV1AdapterStableNG} from "@gearbox-protocol/integrations-v3/contracts/adapters/curve/CurveV1_StableNG.sol";
import {CurveV1AdapterDeposit} from "@gearbox-protocol/integrations-v3/contracts/adapters/curve/CurveV1_DepositZap.sol";
import {CurveV1AdapterBase} from "@gearbox-protocol/integrations-v3/contracts/adapters/curve/CurveV1_Base.sol";
import {CurveV1Adapter3Assets} from "@gearbox-protocol/integrations-v3/contracts/adapters/curve/CurveV1_3.sol";
import {ERC4626Adapter} from "@gearbox-protocol/integrations-v3/contracts/adapters/erc4626/ERC4626Adapter.sol";
import {VelodromeV2RouterAdapter} from
    "@gearbox-protocol/integrations-v3/contracts/adapters/velodrome/VelodromeV2RouterAdapter.sol";
import {DaiUsdsAdapter} from "@gearbox-protocol/integrations-v3/contracts/adapters/sky/DaiUsdsAdapter.sol";
import {StakingRewardsAdapter} from "@gearbox-protocol/integrations-v3/contracts/adapters/sky/StakingRewardsAdapter.sol";

import {BPTWeightedPriceFeed} from "@gearbox-protocol/oracles-v3/contracts/oracles/balancer/BPTWeightedPriceFeed.sol";
import {BPTStablePriceFeed} from "@gearbox-protocol/oracles-v3/contracts/oracles/balancer/BPTStablePriceFeed.sol";
import {ZeroPriceFeed} from "@gearbox-protocol/oracles-v3/contracts/oracles/ZeroPriceFeed.sol";
import {YearnPriceFeed} from "@gearbox-protocol/oracles-v3/contracts/oracles/yearn/YearnPriceFeed.sol";
import {BoundedPriceFeed} from "@gearbox-protocol/oracles-v3/contracts/oracles/BoundedPriceFeed.sol";
import {PythPriceFeed} from "@gearbox-protocol/oracles-v3/contracts/oracles/updatable/PythPriceFeed.sol";
import {RedstonePriceFeed} from "@gearbox-protocol/oracles-v3/contracts/oracles/updatable/RedstonePriceFeed.sol";
import {WstETHPriceFeed} from "@gearbox-protocol/oracles-v3/contracts/oracles/lido/WstETHPriceFeed.sol";
import {CompositePriceFeed} from "@gearbox-protocol/oracles-v3/contracts/oracles/CompositePriceFeed.sol";
import {MellowLRTPriceFeed} from "@gearbox-protocol/oracles-v3/contracts/oracles/mellow/MellowLRTPriceFeed.sol";
import {PendleTWAPPTPriceFeed} from "@gearbox-protocol/oracles-v3/contracts/oracles/pendle/PendleTWAPPTPriceFeed.sol";
import {CurveUSDPriceFeed} from "@gearbox-protocol/oracles-v3/contracts/oracles/curve/CurveUSDPriceFeed.sol";
import {CurveCryptoLPPriceFeed} from "@gearbox-protocol/oracles-v3/contracts/oracles/curve/CurveCryptoLPPriceFeed.sol";
import {CurveStableLPPriceFeed} from "@gearbox-protocol/oracles-v3/contracts/oracles/curve/CurveStableLPPriceFeed.sol";
import {ERC4626PriceFeed} from "@gearbox-protocol/oracles-v3/contracts/oracles/erc4626/ERC4626PriceFeed.sol";

import {console} from "forge-std/console.sol";

struct UploadableContract {
    bytes initCode;
    bytes32 contractType;
    uint256 version;
}

struct DeploySystemContractCall {
    bytes32 contractType;
    uint256 version;
    bool saveVersion;
}

// It deploys all the system contracts and related ones
contract GlobalSetup is Test, InstanceManagerHelper {
    UploadableContract[] internal contractsToUpload;

    constructor() {
        _setCoreContracts();
        _setAdapters();
        _setPriceFeeds();
    }

    function _setUpGlobalContracts() internal {
        _setUpInstanceManager();

        CrossChainCall[] memory calls = new CrossChainCall[](1);
        calls[0] = _generateAddAuditorCall(auditor, "Initial Auditor");

        _submitProposalAndSign("Add Auditor", calls);

        uint256 len = contractsToUpload.length;

        calls = new CrossChainCall[](len);

        for (uint256 i = 0; i < len; ++i) {
            bytes32 bytecodeHash = _uploadByteCodeAndSign(
                contractsToUpload[i].initCode, contractsToUpload[i].contractType, contractsToUpload[i].version
            );
            calls[i] = _generateAllowSystemContractCall(bytecodeHash);
        }

        _submitProposalAndSign("Allow system contracts", calls);

        DeploySystemContractCall[10] memory deployCalls = [
            DeploySystemContractCall({contractType: AP_BOT_LIST, version: 3_10, saveVersion: false}),
            DeploySystemContractCall({contractType: AP_GEAR_STAKING, version: 3_10, saveVersion: false}),
            DeploySystemContractCall({contractType: AP_PRICE_FEED_STORE, version: 3_10, saveVersion: false}),
            DeploySystemContractCall({contractType: AP_MARKET_CONFIGURATOR_FACTORY, version: 3_10, saveVersion: false}),
            DeploySystemContractCall({contractType: AP_POOL_FACTORY, version: 3_10, saveVersion: true}),
            DeploySystemContractCall({contractType: AP_CREDIT_FACTORY, version: 3_10, saveVersion: true}),
            DeploySystemContractCall({contractType: AP_PRICE_ORACLE_FACTORY, version: 3_10, saveVersion: true}),
            DeploySystemContractCall({contractType: AP_INTEREST_RATE_MODEL_FACTORY, version: 3_10, saveVersion: true}),
            DeploySystemContractCall({contractType: AP_RATE_KEEPER_FACTORY, version: 3_10, saveVersion: true}),
            DeploySystemContractCall({contractType: AP_LOSS_POLICY_FACTORY, version: 3_10, saveVersion: true})
        ];

        len = deployCalls.length;

        calls = new CrossChainCall[](len);
        for (uint256 i = 0; i < len; ++i) {
            calls[i] = _generateDeploySystemContractCall(
                deployCalls[i].contractType, deployCalls[i].version, deployCalls[i].saveVersion
            );
        }

        _submitProposalAndSign("System contracts", calls);
    }

    function _setCoreContracts() internal {
        contractsToUpload.push(
            UploadableContract({initCode: type(PoolFactory).creationCode, contractType: AP_POOL_FACTORY, version: 3_10})
        );

        contractsToUpload.push(
            UploadableContract({
                initCode: type(CreditFactory).creationCode,
                contractType: AP_CREDIT_FACTORY,
                version: 3_10
            })
        );

        contractsToUpload.push(
            UploadableContract({
                initCode: type(InterestRateModelFactory).creationCode,
                contractType: AP_INTEREST_RATE_MODEL_FACTORY,
                version: 3_10
            })
        );

        contractsToUpload.push(
            UploadableContract({
                initCode: type(PriceFeedStore).creationCode,
                contractType: AP_PRICE_FEED_STORE,
                version: 3_10
            })
        );

        contractsToUpload.push(
            UploadableContract({
                initCode: type(PriceOracleFactory).creationCode,
                contractType: AP_PRICE_ORACLE_FACTORY,
                version: 3_10
            })
        );

        contractsToUpload.push(
            UploadableContract({
                initCode: type(RateKeeperFactory).creationCode,
                contractType: AP_RATE_KEEPER_FACTORY,
                version: 3_10
            })
        );

        contractsToUpload.push(
            UploadableContract({
                initCode: type(MarketConfiguratorFactory).creationCode,
                contractType: AP_MARKET_CONFIGURATOR_FACTORY,
                version: 3_10
            })
        );

        contractsToUpload.push(
            UploadableContract({initCode: type(Governor).creationCode, contractType: AP_GOVERNOR, version: 3_10})
        );

        contractsToUpload.push(
            UploadableContract({
                initCode: type(TreasurySplitter).creationCode,
                contractType: AP_TREASURY_SPLITTER,
                version: 3_10
            })
        );

        contractsToUpload.push(
            UploadableContract({initCode: type(PoolV3).creationCode, contractType: AP_POOL, version: 3_10})
        );

        contractsToUpload.push(
            UploadableContract({
                initCode: type(PoolQuotaKeeperV3).creationCode,
                contractType: AP_POOL_QUOTA_KEEPER,
                version: 3_10
            })
        );

        contractsToUpload.push(
            UploadableContract({
                initCode: type(LinearInterestRateModelV3).creationCode,
                contractType: AP_INTEREST_RATE_MODEL_LINEAR,
                version: 3_10
            })
        );

        contractsToUpload.push(
            UploadableContract({
                initCode: type(TumblerV3).creationCode,
                contractType: AP_RATE_KEEPER_TUMBLER,
                version: 3_10
            })
        );

        contractsToUpload.push(
            UploadableContract({initCode: type(GaugeV3).creationCode, contractType: AP_RATE_KEEPER_GAUGE, version: 3_10})
        );

        contractsToUpload.push(
            UploadableContract({initCode: type(BotListV3).creationCode, contractType: AP_BOT_LIST, version: 3_10})
        );

        contractsToUpload.push(
            UploadableContract({
                initCode: type(GearStakingV3).creationCode,
                contractType: AP_GEAR_STAKING,
                version: 3_10
            })
        );

        contractsToUpload.push(
            UploadableContract({
                initCode: type(DefaultAccountFactoryV3).creationCode,
                contractType: AP_ACCOUNT_FACTORY_DEFAULT,
                version: 3_10
            })
        );

        contractsToUpload.push(
            UploadableContract({
                initCode: type(PriceOracleV3).creationCode,
                contractType: AP_PRICE_ORACLE,
                version: 3_10
            })
        );

        contractsToUpload.push(
            UploadableContract({
                initCode: type(DefaultLossPolicy).creationCode,
                contractType: AP_LOSS_POLICY_DEFAULT,
                version: 3_10
            })
        );

        contractsToUpload.push(
            UploadableContract({
                initCode: type(MarketConfigurator).creationCode,
                contractType: AP_MARKET_CONFIGURATOR,
                version: 3_10
            })
        );

        contractsToUpload.push(
            UploadableContract({initCode: type(ACL).creationCode, contractType: AP_ACL, version: 3_10})
        );

        contractsToUpload.push(
            UploadableContract({
                initCode: type(ContractsRegister).creationCode,
                contractType: AP_CONTRACTS_REGISTER,
                version: 3_10
            })
        );

        contractsToUpload.push(
            UploadableContract({
                initCode: type(LossPolicyFactory).creationCode,
                contractType: AP_LOSS_POLICY_FACTORY,
                version: 3_10
            })
        );

        contractsToUpload.push(
            UploadableContract({
                initCode: type(CreditManagerV3).creationCode,
                contractType: AP_CREDIT_MANAGER,
                version: 3_10
            })
        );

        contractsToUpload.push(
            UploadableContract({
                initCode: type(CreditFacadeV3).creationCode,
                contractType: AP_CREDIT_FACADE,
                version: 3_10
            })
        );

        contractsToUpload.push(
            UploadableContract({
                initCode: type(CreditConfiguratorV3).creationCode,
                contractType: AP_CREDIT_CONFIGURATOR,
                version: 3_10
            })
        );
    }

    function _setAdapters() internal {
        // TODO: set adapters
        contractsToUpload.push(
            UploadableContract({
                initCode: type(EqualizerRouterAdapter).creationCode,
                contractType: "ADAPTER::EQUALIZER_ROUTER",
                version: 3_10
            })
        );

        contractsToUpload.push(
            UploadableContract({
                initCode: type(BalancerV2VaultAdapter).creationCode,
                contractType: "ADAPTER::BALANCER_VAULT",
                version: 3_10
            })
        );

        contractsToUpload.push(
            UploadableContract({
                initCode: type(CamelotV3Adapter).creationCode,
                contractType: "ADAPTER::CAMELOT_V3_ROUTER",
                version: 3_10
            })
        );

        contractsToUpload.push(
            UploadableContract({
                initCode: type(YearnV2Adapter).creationCode,
                contractType: "ADAPTER::YEARN_V2",
                version: 3_10
            })
        );

        contractsToUpload.push(
            UploadableContract({
                initCode: type(ConvexV1BoosterAdapter).creationCode,
                contractType: "ADAPTER::CVX_V1_BOOSTER",
                version: 3_10
            })
        );

        contractsToUpload.push(
            UploadableContract({
                initCode: type(ConvexV1BaseRewardPoolAdapter).creationCode,
                contractType: "ADAPTER::CVX_V1_BASE_REWARD_POOL",
                version: 3_10
            })
        );

        contractsToUpload.push(
            UploadableContract({
                initCode: type(ZircuitPoolAdapter).creationCode,
                contractType: "ADAPTER::ZIRCUIT_POOL",
                version: 3_10
            })
        );

        contractsToUpload.push(
            UploadableContract({
                initCode: type(WstETHV1Adapter).creationCode,
                contractType: "ADAPTER::WSTETH_V1",
                version: 3_10
            })
        );

        contractsToUpload.push(
            UploadableContract({
                initCode: type(LidoV1Adapter).creationCode,
                contractType: "ADAPTER::LIDO_V1",
                version: 3_10
            })
        );

        contractsToUpload.push(
            UploadableContract({
                initCode: type(UniswapV3Adapter).creationCode,
                contractType: "ADAPTER::UNISWAP_V3_ROUTER",
                version: 3_10
            })
        );

        contractsToUpload.push(
            UploadableContract({
                initCode: type(UniswapV2Adapter).creationCode,
                contractType: "ADAPTER::UNISWAP_V2_ROUTER",
                version: 3_10
            })
        );

        contractsToUpload.push(
            UploadableContract({
                initCode: type(MellowVaultAdapter).creationCode,
                contractType: "ADAPTER::MELLOW_VAULT",
                version: 3_10
            })
        );

        contractsToUpload.push(
            UploadableContract({
                initCode: type(Mellow4626VaultAdapter).creationCode,
                contractType: "ADAPTER::MELLOW_4626_VAULT",
                version: 3_10
            })
        );

        contractsToUpload.push(
            UploadableContract({
                initCode: type(PendleRouterAdapter).creationCode,
                contractType: "ADAPTER::PENDLE_ROUTER",
                version: 3_10
            })
        );

        contractsToUpload.push(
            UploadableContract({
                initCode: type(CurveV1Adapter2Assets).creationCode,
                contractType: "ADAPTER::CURVE_V1_2ASSETS",
                version: 3_10
            })
        );

        contractsToUpload.push(
            UploadableContract({
                initCode: type(CurveV1Adapter4Assets).creationCode,
                contractType: "ADAPTER::CURVE_V1_4ASSETS",
                version: 3_10
            })
        );

        contractsToUpload.push(
            UploadableContract({
                initCode: type(CurveV1AdapterStETH).creationCode,
                contractType: "ADAPTER::CURVE_V1_STECRV_POOL",
                version: 3_10
            })
        );

        contractsToUpload.push(
            UploadableContract({
                initCode: type(CurveV1AdapterStableNG).creationCode,
                contractType: "ADAPTER::CURVE_STABLE_NG",
                version: 3_10
            })
        );

        contractsToUpload.push(
            UploadableContract({
                initCode: type(CurveV1AdapterDeposit).creationCode,
                contractType: "ADAPTER::CURVE_V1_WRAPPER",
                version: 3_10
            })
        );

        contractsToUpload.push(
            UploadableContract({
                initCode: type(CurveV1Adapter3Assets).creationCode,
                contractType: "ADAPTER::CURVE_V1_3ASSETS",
                version: 3_10
            })
        );

        contractsToUpload.push(
            UploadableContract({
                initCode: type(ERC4626Adapter).creationCode,
                contractType: "ADAPTER::ERC4626_VAULT",
                version: 3_10
            })
        );

        contractsToUpload.push(
            UploadableContract({
                initCode: type(VelodromeV2RouterAdapter).creationCode,
                contractType: "ADAPTER::VELODROME_V2_ROUTER",
                version: 3_10
            })
        );

        contractsToUpload.push(
            UploadableContract({
                initCode: type(DaiUsdsAdapter).creationCode,
                contractType: "ADAPTER::DAI_USDS_EXCHANGE",
                version: 3_10
            })
        );

        contractsToUpload.push(
            UploadableContract({
                initCode: type(StakingRewardsAdapter).creationCode,
                contractType: "ADAPTER::STAKING_REWARDS",
                version: 3_10
            })
        );
    }

    function _setPriceFeeds() internal {
        // TODO: set price feeds
        // contractsToUpload.push(
        //     UploadableContract({
        //         initCode: type(BPTWeightedPriceFeed).creationCode,
        //         contractType: "PRICE_FEED::BALANCER_WEIGHTED",
        //         version: 3_10
        //     })
        // );

        contractsToUpload.push(
            UploadableContract({
                initCode: type(BPTStablePriceFeed).creationCode,
                contractType: "PRICE_FEED::BALANCER_STABLE",
                version: 3_10
            })
        );

        contractsToUpload.push(
            UploadableContract({
                initCode: type(ZeroPriceFeed).creationCode,
                contractType: "PRICE_FEED::ZERO",
                version: 3_10
            })
        );

        contractsToUpload.push(
            UploadableContract({
                initCode: type(YearnPriceFeed).creationCode,
                contractType: "PRICE_FEED::YEARN",
                version: 3_10
            })
        );

        contractsToUpload.push(
            UploadableContract({
                initCode: type(BoundedPriceFeed).creationCode,
                contractType: "PRICE_FEED::BOUNDED",
                version: 3_10
            })
        );

        contractsToUpload.push(
            UploadableContract({
                initCode: type(PythPriceFeed).creationCode,
                contractType: "PRICE_FEED::PYTH",
                version: 3_10
            })
        );

        contractsToUpload.push(
            UploadableContract({
                initCode: type(RedstonePriceFeed).creationCode,
                contractType: "PRICE_FEED::REDSTONE",
                version: 3_10
            })
        );

        contractsToUpload.push(
            UploadableContract({
                initCode: type(WstETHPriceFeed).creationCode,
                contractType: "PRICE_FEED::WSTETH",
                version: 3_10
            })
        );

        contractsToUpload.push(
            UploadableContract({
                initCode: type(CompositePriceFeed).creationCode,
                contractType: "PRICE_FEED::COMPOSITE",
                version: 3_10
            })
        );

        contractsToUpload.push(
            UploadableContract({
                initCode: type(MellowLRTPriceFeed).creationCode,
                contractType: "PRICE_FEED::MELLOW_LRT",
                version: 3_10
            })
        );

        contractsToUpload.push(
            UploadableContract({
                initCode: type(PendleTWAPPTPriceFeed).creationCode,
                contractType: "PRICE_FEED::PENDLE_PT_TWAP",
                version: 3_10
            })
        );

        contractsToUpload.push(
            UploadableContract({
                initCode: type(CurveUSDPriceFeed).creationCode,
                contractType: "PRICE_FEED::CURVE_USD",
                version: 3_10
            })
        );

        contractsToUpload.push(
            UploadableContract({
                initCode: type(CurveCryptoLPPriceFeed).creationCode,
                contractType: "PRICE_FEED::CURVE_CRYPTO",
                version: 3_10
            })
        );

        contractsToUpload.push(
            UploadableContract({
                initCode: type(CurveStableLPPriceFeed).creationCode,
                contractType: "PRICE_FEED::CURVE_STABLE",
                version: 3_10
            })
        );

        contractsToUpload.push(
            UploadableContract({
                initCode: type(ERC4626PriceFeed).creationCode,
                contractType: "PRICE_FEED::ERC4626",
                version: 3_10
            })
        );
    }

    // function _setupPriceFeedStore() internal {
    //     // _addPriceFeed(CHAINLINK_ETH_USD, 1 days);
    //     // _addPriceFeed(CHAINLINK_USDC_USD, 1 days);

    //     // _allowPriceFeed(WETH, CHAINLINK_ETH_USD);
    //     // _allowPriceFeed(USDC, CHAINLINK_USDC_USD);
    // }
}
