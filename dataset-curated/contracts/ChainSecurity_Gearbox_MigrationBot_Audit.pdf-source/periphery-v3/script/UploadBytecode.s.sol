// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import {Script} from "forge-std/Script.sol";
import {VmSafe} from "forge-std/Vm.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {
    Bytecode,
    IBytecodeRepository
} from "@gearbox-protocol/permissionless/contracts/interfaces/IBytecodeRepository.sol";

import {PartialLiquidationBotV3} from "@gearbox-protocol/bots-v3/contracts/bots/PartialLiquidationBotV3.sol";

import {AliasedLossPolicyV3} from "@gearbox-protocol/core-v3/contracts/core/AliasedLossPolicyV3.sol";
import {BotListV3} from "@gearbox-protocol/core-v3/contracts/core/BotListV3.sol";
import {DefaultAccountFactoryV3} from "@gearbox-protocol/core-v3/contracts/core/DefaultAccountFactoryV3.sol";
import {GearStakingV3} from "@gearbox-protocol/core-v3/contracts/core/GearStakingV3.sol";
import {PriceOracleV3} from "@gearbox-protocol/core-v3/contracts/core/PriceOracleV3.sol";
import {CreditConfiguratorV3} from "@gearbox-protocol/core-v3/contracts/credit/CreditConfiguratorV3.sol";
import {CreditFacadeV3} from "@gearbox-protocol/core-v3/contracts/credit/CreditFacadeV3.sol";
import {CreditManagerV3} from "@gearbox-protocol/core-v3/contracts/credit/CreditManagerV3.sol";
import {CreditManagerV3_USDT} from "@gearbox-protocol/core-v3/contracts/credit/CreditManagerV3_USDT.sol";
import {GaugeV3} from "@gearbox-protocol/core-v3/contracts/pool/GaugeV3.sol";
import {LinearInterestRateModelV3} from "@gearbox-protocol/core-v3/contracts/pool/LinearInterestRateModelV3.sol";
import {PoolQuotaKeeperV3} from "@gearbox-protocol/core-v3/contracts/pool/PoolQuotaKeeperV3.sol";
import {PoolV3} from "@gearbox-protocol/core-v3/contracts/pool/PoolV3.sol";
import {PoolV3_USDT} from "@gearbox-protocol/core-v3/contracts/pool/PoolV3_USDT.sol";
import {TumblerV3} from "@gearbox-protocol/core-v3/contracts/pool/TumblerV3.sol";

import {BalancerV2VaultAdapter} from
    "@gearbox-protocol/integrations-v3/contracts/adapters/balancer/BalancerV2VaultAdapter.sol";
import {BalancerV3RouterAdapter} from
    "@gearbox-protocol/integrations-v3/contracts/adapters/balancer/BalancerV3RouterAdapter.sol";
import {CamelotV3Adapter} from "@gearbox-protocol/integrations-v3/contracts/adapters/camelot/CamelotV3Adapter.sol";
import {ConvexV1BaseRewardPoolAdapter} from
    "@gearbox-protocol/integrations-v3/contracts/adapters/convex/ConvexV1_BaseRewardPool.sol";
import {ConvexV1BoosterAdapter} from "@gearbox-protocol/integrations-v3/contracts/adapters/convex/ConvexV1_Booster.sol";
import {CurveV1Adapter2Assets} from "@gearbox-protocol/integrations-v3/contracts/adapters/curve/CurveV1_2.sol";
import {CurveV1Adapter3Assets} from "@gearbox-protocol/integrations-v3/contracts/adapters/curve/CurveV1_3.sol";
import {CurveV1Adapter4Assets} from "@gearbox-protocol/integrations-v3/contracts/adapters/curve/CurveV1_4.sol";
import {CurveV1AdapterDeposit} from "@gearbox-protocol/integrations-v3/contracts/adapters/curve/CurveV1_DepositZap.sol";
import {CurveV1AdapterStableNG} from "@gearbox-protocol/integrations-v3/contracts/adapters/curve/CurveV1_StableNG.sol";
import {CurveV1AdapterStETH} from "@gearbox-protocol/integrations-v3/contracts/adapters/curve/CurveV1_stETH.sol";
import {ERC4626Adapter} from "@gearbox-protocol/integrations-v3/contracts/adapters/erc4626/ERC4626Adapter.sol";
import {EqualizerRouterAdapter} from
    "@gearbox-protocol/integrations-v3/contracts/adapters/equalizer/EqualizerRouterAdapter.sol";
import {LidoV1Adapter} from "@gearbox-protocol/integrations-v3/contracts/adapters/lido/LidoV1.sol";
import {WstETHV1Adapter} from "@gearbox-protocol/integrations-v3/contracts/adapters/lido/WstETHV1.sol";
import {Mellow4626VaultAdapter} from
    "@gearbox-protocol/integrations-v3/contracts/adapters/mellow/Mellow4626VaultAdapter.sol";
import {MellowVaultAdapter} from "@gearbox-protocol/integrations-v3/contracts/adapters/mellow/MellowVaultAdapter.sol";
import {PendleRouterAdapter} from "@gearbox-protocol/integrations-v3/contracts/adapters/pendle/PendleRouterAdapter.sol";
import {DaiUsdsAdapter} from "@gearbox-protocol/integrations-v3/contracts/adapters/sky/DaiUsdsAdapter.sol";
import {StakingRewardsAdapter} from "@gearbox-protocol/integrations-v3/contracts/adapters/sky/StakingRewardsAdapter.sol";
import {UniswapV2Adapter} from "@gearbox-protocol/integrations-v3/contracts/adapters/uniswap/UniswapV2.sol";
import {UniswapV3Adapter} from "@gearbox-protocol/integrations-v3/contracts/adapters/uniswap/UniswapV3.sol";
import {VelodromeV2RouterAdapter} from
    "@gearbox-protocol/integrations-v3/contracts/adapters/velodrome/VelodromeV2RouterAdapter.sol";
import {YearnV2Adapter} from "@gearbox-protocol/integrations-v3/contracts/adapters/yearn/YearnV2.sol";
import {UnderlyingDepositZapper} from "@gearbox-protocol/integrations-v3/contracts/zappers/UnderlyingDepositZapper.sol";
import {UnderlyingFarmingZapper} from "@gearbox-protocol/integrations-v3/contracts/zappers/UnderlyingFarmingZapper.sol";
import {WETHDepositZapper} from "@gearbox-protocol/integrations-v3/contracts/zappers/WETHDepositZapper.sol";
import {WETHFarmingZapper} from "@gearbox-protocol/integrations-v3/contracts/zappers/WETHFarmingZapper.sol";
import {WstETHDepositZapper} from "@gearbox-protocol/integrations-v3/contracts/zappers/WstETHDepositZapper.sol";
import {WstETHFarmingZapper} from "@gearbox-protocol/integrations-v3/contracts/zappers/WstETHFarmingZapper.sol";

import {BoundedPriceFeed} from "@gearbox-protocol/oracles-v3/contracts/oracles/BoundedPriceFeed.sol";
import {CompositePriceFeed} from "@gearbox-protocol/oracles-v3/contracts/oracles/CompositePriceFeed.sol";
import {ZeroPriceFeed} from "@gearbox-protocol/oracles-v3/contracts/oracles/ZeroPriceFeed.sol";
import {BPTStablePriceFeed} from "@gearbox-protocol/oracles-v3/contracts/oracles/balancer/BPTStablePriceFeed.sol";
import {BPTWeightedPriceFeed} from "@gearbox-protocol/oracles-v3/contracts/oracles/balancer/BPTWeightedPriceFeed.sol";
import {CurveCryptoLPPriceFeed} from "@gearbox-protocol/oracles-v3/contracts/oracles/curve/CurveCryptoLPPriceFeed.sol";
import {CurveStableLPPriceFeed} from "@gearbox-protocol/oracles-v3/contracts/oracles/curve/CurveStableLPPriceFeed.sol";
import {CurveUSDPriceFeed} from "@gearbox-protocol/oracles-v3/contracts/oracles/curve/CurveUSDPriceFeed.sol";
import {ERC4626PriceFeed} from "@gearbox-protocol/oracles-v3/contracts/oracles/erc4626/ERC4626PriceFeed.sol";
import {WstETHPriceFeed} from "@gearbox-protocol/oracles-v3/contracts/oracles/lido/WstETHPriceFeed.sol";
import {MellowLRTPriceFeed} from "@gearbox-protocol/oracles-v3/contracts/oracles/mellow/MellowLRTPriceFeed.sol";
import {PendleTWAPPTPriceFeed} from "@gearbox-protocol/oracles-v3/contracts/oracles/pendle/PendleTWAPPTPriceFeed.sol";
import {PythPriceFeed} from "@gearbox-protocol/oracles-v3/contracts/oracles/updatable/PythPriceFeed.sol";
import {RedstonePriceFeed} from "@gearbox-protocol/oracles-v3/contracts/oracles/updatable/RedstonePriceFeed.sol";
import {YearnPriceFeed} from "@gearbox-protocol/oracles-v3/contracts/oracles/yearn/YearnPriceFeed.sol";

import {CreditFactory} from "@gearbox-protocol/permissionless/contracts/factories/CreditFactory.sol";
import {InterestRateModelFactory} from
    "@gearbox-protocol/permissionless/contracts/factories/InterestRateModelFactory.sol";
import {LossPolicyFactory} from "@gearbox-protocol/permissionless/contracts/factories/LossPolicyFactory.sol";
import {PoolFactory} from "@gearbox-protocol/permissionless/contracts/factories/PoolFactory.sol";
import {PriceOracleFactory} from "@gearbox-protocol/permissionless/contracts/factories/PriceOracleFactory.sol";
import {RateKeeperFactory} from "@gearbox-protocol/permissionless/contracts/factories/RateKeeperFactory.sol";
import {DefaultDegenNFT} from "@gearbox-protocol/permissionless/contracts/helpers/DefaultDegenNFT.sol";
import {MarketConfiguratorFactory} from
    "@gearbox-protocol/permissionless/contracts/instance/MarketConfiguratorFactory.sol";
import {PriceFeedStore} from "@gearbox-protocol/permissionless/contracts/instance/PriceFeedStore.sol";
import {ACL} from "@gearbox-protocol/permissionless/contracts/market/ACL.sol";
import {ContractsRegister} from "@gearbox-protocol/permissionless/contracts/market/ContractsRegister.sol";
import {Governor} from "@gearbox-protocol/permissionless/contracts/market/Governor.sol";
import {MarketConfigurator} from "@gearbox-protocol/permissionless/contracts/market/MarketConfigurator.sol";
import {TreasurySplitter} from "@gearbox-protocol/permissionless/contracts/market/TreasurySplitter.sol";

contract UploadBytecode is Script {
    VmSafe.Wallet public author;
    address public bytecodeRepository;
    bytes32 public domainSeparator;

    string public bots = "https://github.com/Gearbox-protocol/bots-v3/blob/3d56f6ccfc202e52487ec9651babdd4fe5cb5788";
    string public core = "https://github.com/Gearbox-protocol/core-v3/blob/562ccc19210fe43c170c4451eb35fb786982ca43";
    string public integrations =
        "https://github.com/Gearbox-protocol/integrations-v3/blob/9e56cb66d59ab27bad0c04339d3b401c230e7ae2";
    string public oracles =
        "https://github.com/Gearbox-protocol/oracles-v3/blob/fc8d3a0ab5bd7eb50ce3f6b87dde5cd3d887bafe";
    string public permissionless =
        "https://github.com/Gearbox-protocol/permissionless/blob/f660f1abb176096d1b97b80667a0a019e0aaadc6";

    function setUp() public {
        author = vm.createWallet(vm.envUint("AUTHOR_PRIVATE_KEY"));
        bytecodeRepository = vm.envAddress("BYTECODE_REPOSITORY");
        domainSeparator = IBytecodeRepository(bytecodeRepository).domainSeparatorV4();
    }

    function run() public {
        vm.startBroadcast(author.privateKey);
        _uploadBytecodes(_getAdapterContracts());
        _uploadBytecodes(_getBotContracts());
        _uploadBytecodes(_getCoreContracts());
        _uploadBytecodes(_getDegenNFTContracts());
        _uploadBytecodes(_getInterestRateModelContracts());
        _uploadBytecodes(_getLossPolicyContracts());
        _uploadBytecodes(_getPriceFeedContracts());
        _uploadBytecodes(_getRateKeeperContracts());
        _uploadBytecodes(_getZapperContracts());
        vm.stopBroadcast();
    }

    function _uploadBytecodes(Bytecode[] memory bytecodes) internal {
        for (uint256 i; i < bytecodes.length; ++i) {
            bytecodes[i].author = author.addr;
            bytes32 bytecodeHash = IBytecodeRepository(bytecodeRepository).computeBytecodeHash(bytecodes[i]);
            (uint8 v, bytes32 r, bytes32 s) = vm.sign(author, ECDSA.toTypedDataHash(domainSeparator, bytecodeHash));
            bytecodes[i].authorSignature = abi.encodePacked(r, s, v);
            IBytecodeRepository(bytecodeRepository).uploadBytecode(bytecodes[i]);
        }
    }

    function _getAdapterContracts() internal view returns (Bytecode[] memory bytecodes) {
        bytecodes = new Bytecode[](24);

        bytecodes[0].contractType = "ADAPTER::BALANCER_VAULT";
        bytecodes[0].version = 3_10;
        bytecodes[0].initCode = type(BalancerV2VaultAdapter).creationCode;
        bytecodes[0].source = string.concat(integrations, "/contracts/adapters/balancer/BalancerV2VaultAdapter.sol");

        bytecodes[1].contractType = "ADAPTER::BALANCER_V3_ROUTER";
        bytecodes[1].version = 3_10;
        bytecodes[1].initCode = type(BalancerV3RouterAdapter).creationCode;
        bytecodes[1].source = string.concat(integrations, "/contracts/adapters/balancer/BalancerV3RouterAdapter.sol");

        bytecodes[2].contractType = "ADAPTER::CAMELOT_V3_ROUTER";
        bytecodes[2].version = 3_10;
        bytecodes[2].initCode = type(CamelotV3Adapter).creationCode;
        bytecodes[2].source = string.concat(integrations, "/contracts/adapters/camelot/CamelotV3Adapter.sol");

        bytecodes[3].contractType = "ADAPTER::CVX_V1_BASE_REWARD_POOL";
        bytecodes[3].version = 3_10;
        bytecodes[3].initCode = type(ConvexV1BaseRewardPoolAdapter).creationCode;
        bytecodes[3].source = string.concat(integrations, "/contracts/adapters/convex/ConvexV1_BaseRewardPool.sol");

        bytecodes[4].contractType = "ADAPTER::CVX_V1_BOOSTER";
        bytecodes[4].version = 3_10;
        bytecodes[4].initCode = type(ConvexV1BoosterAdapter).creationCode;
        bytecodes[4].source = string.concat(integrations, "/contracts/adapters/convex/ConvexV1_Booster.sol");

        bytecodes[5].contractType = "ADAPTER::CURVE_V1_2ASSETS";
        bytecodes[5].version = 3_10;
        bytecodes[5].initCode = type(CurveV1Adapter2Assets).creationCode;
        bytecodes[5].source = string.concat(integrations, "/contracts/adapters/curve/CurveV1_2.sol");

        bytecodes[6].contractType = "ADAPTER::CURVE_V1_3ASSETS";
        bytecodes[6].version = 3_10;
        bytecodes[6].initCode = type(CurveV1Adapter3Assets).creationCode;
        bytecodes[6].source = string.concat(integrations, "/contracts/adapters/curve/CurveV1_3.sol");

        bytecodes[7].contractType = "ADAPTER::CURVE_V1_4ASSETS";
        bytecodes[7].version = 3_10;
        bytecodes[7].initCode = type(CurveV1Adapter4Assets).creationCode;
        bytecodes[7].source = string.concat(integrations, "/contracts/adapters/curve/CurveV1_4.sol");

        bytecodes[8].contractType = "ADAPTER::CURVE_STABLE_NG";
        bytecodes[8].version = 3_10;
        bytecodes[8].initCode = type(CurveV1AdapterStableNG).creationCode;
        bytecodes[8].source = string.concat(integrations, "/contracts/adapters/curve/CurveV1_StableNG.sol");

        bytecodes[9].contractType = "ADAPTER::CURVE_V1_STECRV_POOL";
        bytecodes[9].version = 3_10;
        bytecodes[9].initCode = type(CurveV1AdapterStETH).creationCode;
        bytecodes[9].source = string.concat(integrations, "/contracts/adapters/curve/CurveV1_stETH.sol");

        bytecodes[10].contractType = "ADAPTER::CURVE_V1_WRAPPER";
        bytecodes[10].version = 3_10;
        bytecodes[10].initCode = type(CurveV1AdapterDeposit).creationCode;
        bytecodes[10].source = string.concat(integrations, "/contracts/adapters/curve/CurveV1_DepositZap.sol");

        bytecodes[11].contractType = "ADAPTER::ERC4626_VAULT";
        bytecodes[11].version = 3_10;
        bytecodes[11].initCode = type(ERC4626Adapter).creationCode;
        bytecodes[11].source = string.concat(integrations, "/contracts/adapters/erc4626/ERC4626Adapter.sol");

        bytecodes[12].contractType = "ADAPTER::EQUALIZER_ROUTER";
        bytecodes[12].version = 3_10;
        bytecodes[12].initCode = type(EqualizerRouterAdapter).creationCode;
        bytecodes[12].source = string.concat(integrations, "/contracts/adapters/equalizer/EqualizerRouterAdapter.sol");

        bytecodes[13].contractType = "ADAPTER::LIDO_V1";
        bytecodes[13].version = 3_10;
        bytecodes[13].initCode = type(LidoV1Adapter).creationCode;
        bytecodes[13].source = string.concat(integrations, "/contracts/adapters/lido/LidoV1.sol");

        bytecodes[14].contractType = "ADAPTER::LIDO_WSTETH_V1";
        bytecodes[14].version = 3_10;
        bytecodes[14].initCode = type(WstETHV1Adapter).creationCode;
        bytecodes[14].source = string.concat(integrations, "/contracts/adapters/lido/WstETHV1.sol");

        bytecodes[15].contractType = "ADAPTER::MELLOW_ERC4626_VAULT";
        bytecodes[15].version = 3_10;
        bytecodes[15].initCode = type(Mellow4626VaultAdapter).creationCode;
        bytecodes[15].source = string.concat(integrations, "/contracts/adapters/mellow/Mellow4626VaultAdapter.sol");

        bytecodes[16].contractType = "ADAPTER::MELLOW_LRT_VAULT";
        bytecodes[16].version = 3_10;
        bytecodes[16].initCode = type(MellowVaultAdapter).creationCode;
        bytecodes[16].source = string.concat(integrations, "/contracts/adapters/mellow/MellowVaultAdapter.sol");

        bytecodes[17].contractType = "ADAPTER::PENDLE_ROUTER";
        bytecodes[17].version = 3_10;
        bytecodes[17].initCode = type(PendleRouterAdapter).creationCode;
        bytecodes[17].source = string.concat(integrations, "/contracts/adapters/pendle/PendleRouterAdapter.sol");

        bytecodes[18].contractType = "ADAPTER::DAI_USDS_EXCHANGE";
        bytecodes[18].version = 3_10;
        bytecodes[18].initCode = type(DaiUsdsAdapter).creationCode;
        bytecodes[18].source = string.concat(integrations, "/contracts/adapters/sky/DaiUsdsAdapter.sol");

        bytecodes[19].contractType = "ADAPTER::STAKING_REWARDS";
        bytecodes[19].version = 3_10;
        bytecodes[19].initCode = type(StakingRewardsAdapter).creationCode;
        bytecodes[19].source = string.concat(integrations, "/contracts/adapters/sky/StakingRewardsAdapter.sol");

        bytecodes[20].contractType = "ADAPTER::UNISWAP_V2_ROUTER";
        bytecodes[20].version = 3_10;
        bytecodes[20].initCode = type(UniswapV2Adapter).creationCode;
        bytecodes[20].source = string.concat(integrations, "/contracts/adapters/uniswap/UniswapV2.sol");

        bytecodes[21].contractType = "ADAPTER::UNISWAP_V3_ROUTER";
        bytecodes[21].version = 3_10;
        bytecodes[21].initCode = type(UniswapV3Adapter).creationCode;
        bytecodes[21].source = string.concat(integrations, "/contracts/adapters/uniswap/UniswapV3.sol");

        bytecodes[22].contractType = "ADAPTER::VELODROME_V2_ROUTER";
        bytecodes[22].version = 3_10;
        bytecodes[22].initCode = type(VelodromeV2RouterAdapter).creationCode;
        bytecodes[22].source = string.concat(integrations, "/contracts/adapters/velodrome/VelodromeV2RouterAdapter.sol");

        bytecodes[23].contractType = "ADAPTER::YEARN_V2";
        bytecodes[23].version = 3_10;
        bytecodes[23].initCode = type(YearnV2Adapter).creationCode;
        bytecodes[23].source = string.concat(integrations, "/contracts/adapters/yearn/YearnV2.sol");
    }

    function _getBotContracts() internal view returns (Bytecode[] memory bytecodes) {
        bytecodes = new Bytecode[](1);
        bytecodes[0].contractType = "BOT::PARTIAL_LIQUIDATION";
        bytecodes[0].version = 3_10;
        bytecodes[0].initCode = type(PartialLiquidationBotV3).creationCode;
        bytecodes[0].source = string.concat(bots, "/contracts/bots/PartialLiquidationBotV3.sol");
    }

    function _getCoreContracts() internal view returns (Bytecode[] memory bytecodes) {
        bytecodes = new Bytecode[](24);

        bytecodes[0].contractType = "BOT_LIST";
        bytecodes[0].version = 3_10;
        bytecodes[0].initCode = type(BotListV3).creationCode;
        bytecodes[0].source = string.concat(core, "/contracts/core/BotListV3.sol");

        bytecodes[1].contractType = "GEAR_STAKING";
        bytecodes[1].version = 3_10;
        bytecodes[1].initCode = type(GearStakingV3).creationCode;
        bytecodes[1].source = string.concat(core, "/contracts/core/GearStakingV3.sol");

        bytecodes[2].contractType = "PRICE_ORACLE";
        bytecodes[2].version = 3_10;
        bytecodes[2].initCode = type(PriceOracleV3).creationCode;
        bytecodes[2].source = string.concat(core, "/contracts/core/PriceOracleV3.sol");

        bytecodes[3].contractType = "CREDIT_CONFIGURATOR";
        bytecodes[3].version = 3_10;
        bytecodes[3].initCode = type(CreditConfiguratorV3).creationCode;
        bytecodes[3].source = string.concat(core, "/contracts/credit/CreditConfiguratorV3.sol");

        bytecodes[4].contractType = "CREDIT_FACADE";
        bytecodes[4].version = 3_10;
        bytecodes[4].initCode = type(CreditFacadeV3).creationCode;
        bytecodes[4].source = string.concat(core, "/contracts/credit/CreditFacadeV3.sol");

        bytecodes[5].contractType = "CREDIT_MANAGER";
        bytecodes[5].version = 3_10;
        bytecodes[5].initCode = type(CreditManagerV3).creationCode;
        bytecodes[5].source = string.concat(core, "/contracts/credit/CreditManagerV3.sol");

        bytecodes[6].contractType = "CREDIT_MANAGER::USDT";
        bytecodes[6].version = 3_10;
        bytecodes[6].initCode = type(CreditManagerV3_USDT).creationCode;
        bytecodes[6].source = string.concat(core, "/contracts/credit/CreditManagerV3_USDT.sol");

        bytecodes[7].contractType = "POOL_QUOTA_KEEPER";
        bytecodes[7].version = 3_10;
        bytecodes[7].initCode = type(PoolQuotaKeeperV3).creationCode;
        bytecodes[7].source = string.concat(core, "/contracts/pool/PoolQuotaKeeperV3.sol");

        bytecodes[8].contractType = "POOL";
        bytecodes[8].version = 3_10;
        bytecodes[8].initCode = type(PoolV3).creationCode;
        bytecodes[8].source = string.concat(core, "/contracts/pool/PoolV3.sol");

        bytecodes[9].contractType = "POOL::USDT";
        bytecodes[9].version = 3_10;
        bytecodes[9].initCode = type(PoolV3_USDT).creationCode;
        bytecodes[9].source = string.concat(core, "/contracts/pool/PoolV3_USDT.sol");

        bytecodes[10].contractType = "CREDIT_FACTORY";
        bytecodes[10].version = 3_10;
        bytecodes[10].initCode = type(CreditFactory).creationCode;
        bytecodes[10].source = string.concat(permissionless, "/contracts/factories/CreditFactory.sol");

        bytecodes[11].contractType = "INTEREST_RATE_MODEL_FACTORY";
        bytecodes[11].version = 3_10;
        bytecodes[11].initCode = type(InterestRateModelFactory).creationCode;
        bytecodes[11].source = string.concat(permissionless, "/contracts/factories/InterestRateModelFactory.sol");

        bytecodes[12].contractType = "LOSS_POLICY_FACTORY";
        bytecodes[12].version = 3_10;
        bytecodes[12].initCode = type(LossPolicyFactory).creationCode;
        bytecodes[12].source = string.concat(permissionless, "/contracts/factories/LossPolicyFactory.sol");

        bytecodes[13].contractType = "POOL_FACTORY";
        bytecodes[13].version = 3_10;
        bytecodes[13].initCode = type(PoolFactory).creationCode;
        bytecodes[13].source = string.concat(permissionless, "/contracts/factories/PoolFactory.sol");

        bytecodes[14].contractType = "PRICE_ORACLE_FACTORY";
        bytecodes[14].version = 3_10;
        bytecodes[14].initCode = type(PriceOracleFactory).creationCode;
        bytecodes[14].source = string.concat(permissionless, "/contracts/factories/PriceOracleFactory.sol");

        bytecodes[15].contractType = "RATE_KEEPER_FACTORY";
        bytecodes[15].version = 3_10;
        bytecodes[15].initCode = type(RateKeeperFactory).creationCode;
        bytecodes[15].source = string.concat(permissionless, "/contracts/factories/RateKeeperFactory.sol");

        bytecodes[16].contractType = "MARKET_CONFIGURATOR_FACTORY";
        bytecodes[16].version = 3_10;
        bytecodes[16].initCode = type(MarketConfiguratorFactory).creationCode;
        bytecodes[16].source = string.concat(permissionless, "/contracts/instance/MarketConfiguratorFactory.sol");

        bytecodes[17].contractType = "PRICE_FEED_STORE";
        bytecodes[17].version = 3_10;
        bytecodes[17].initCode = type(PriceFeedStore).creationCode;
        bytecodes[17].source = string.concat(permissionless, "/contracts/instance/PriceFeedStore.sol");

        bytecodes[18].contractType = "ACL";
        bytecodes[18].version = 3_10;
        bytecodes[18].initCode = type(ACL).creationCode;
        bytecodes[18].source = string.concat(permissionless, "/contracts/market/ACL.sol");

        bytecodes[19].contractType = "CONTRACTS_REGISTER";
        bytecodes[19].version = 3_10;
        bytecodes[19].initCode = type(ContractsRegister).creationCode;
        bytecodes[19].source = string.concat(permissionless, "/contracts/market/ContractsRegister.sol");

        bytecodes[20].contractType = "GOVERNOR";
        bytecodes[20].version = 3_10;
        bytecodes[20].initCode = type(Governor).creationCode;
        bytecodes[20].source = string.concat(permissionless, "/contracts/market/Governor.sol");

        bytecodes[21].contractType = "MARKET_CONFIGURATOR";
        bytecodes[21].version = 3_10;
        bytecodes[21].initCode = type(MarketConfigurator).creationCode;
        bytecodes[21].source = string.concat(permissionless, "/contracts/market/MarketConfigurator.sol");

        bytecodes[22].contractType = "TREASURY_SPLITTER";
        bytecodes[22].version = 3_10;
        bytecodes[22].initCode = type(TreasurySplitter).creationCode;
        bytecodes[22].source = string.concat(permissionless, "/contracts/market/TreasurySplitter.sol");

        bytecodes[23].contractType = "ACCOUNT_FACTORY::DEFAULT";
        bytecodes[23].version = 3_10;
        bytecodes[23].initCode = type(DefaultAccountFactoryV3).creationCode;
        bytecodes[23].source = string.concat(core, "/contracts/core/DefaultAccountFactoryV3.sol");
    }

    function _getDegenNFTContracts() internal view returns (Bytecode[] memory bytecodes) {
        bytecodes = new Bytecode[](1);
        bytecodes[0].contractType = "DEGEN_NFT::DEFAULT";
        bytecodes[0].version = 3_10;
        bytecodes[0].initCode = type(DefaultDegenNFT).creationCode;
        bytecodes[0].source = string.concat(permissionless, "/contracts/helpers/DefaultDegenNFT.sol");
    }

    function _getInterestRateModelContracts() internal view returns (Bytecode[] memory bytecodes) {
        bytecodes = new Bytecode[](1);
        bytecodes[0].contractType = "IRM::LINEAR";
        bytecodes[0].version = 3_10;
        bytecodes[0].initCode = type(LinearInterestRateModelV3).creationCode;
        bytecodes[0].source = string.concat(core, "/contracts/pool/LinearInterestRateModelV3.sol");
    }

    function _getLossPolicyContracts() internal view returns (Bytecode[] memory bytecodes) {
        bytecodes = new Bytecode[](1);
        bytecodes[0].contractType = "LOSS_POLICY::ALIASED";
        bytecodes[0].version = 3_10;
        bytecodes[0].initCode = type(AliasedLossPolicyV3).creationCode;
        bytecodes[0].source = string.concat(core, "/contracts/core/AliasedLossPolicyV3.sol");
    }

    function _getPriceFeedContracts() internal view returns (Bytecode[] memory bytecodes) {
        bytecodes = new Bytecode[](15);

        bytecodes[0].contractType = "PRICE_FEED::BOUNDED";
        bytecodes[0].version = 3_10;
        bytecodes[0].initCode = type(BoundedPriceFeed).creationCode;
        bytecodes[0].source = string.concat(oracles, "/contracts/oracles/BoundedPriceFeed.sol");

        bytecodes[1].contractType = "PRICE_FEED::COMPOSITE";
        bytecodes[1].version = 3_10;
        bytecodes[1].initCode = type(CompositePriceFeed).creationCode;
        bytecodes[1].source = string.concat(oracles, "/contracts/oracles/CompositePriceFeed.sol");

        bytecodes[2].contractType = "PRICE_FEED::ZERO";
        bytecodes[2].version = 3_10;
        bytecodes[2].initCode = type(ZeroPriceFeed).creationCode;
        bytecodes[2].source = string.concat(oracles, "/contracts/oracles/ZeroPriceFeed.sol");

        bytecodes[3].contractType = "PRICE_FEED::BALANCER_STABLE";
        bytecodes[3].version = 3_10;
        bytecodes[3].initCode = type(BPTStablePriceFeed).creationCode;
        bytecodes[3].source = string.concat(oracles, "/contracts/oracles/balancer/BPTStablePriceFeed.sol");

        bytecodes[4].contractType = "PRICE_FEED::BALANCER_WEIGHTED";
        bytecodes[4].version = 3_10;
        bytecodes[4].initCode = type(BPTWeightedPriceFeed).creationCode;
        bytecodes[4].source = string.concat(oracles, "/contracts/oracles/balancer/BPTWeightedPriceFeed.sol");

        bytecodes[5].contractType = "PRICE_FEED::CURVE_CRYPTO";
        bytecodes[5].version = 3_10;
        bytecodes[5].initCode = type(CurveCryptoLPPriceFeed).creationCode;
        bytecodes[5].source = string.concat(oracles, "/contracts/oracles/curve/CurveCryptoLPPriceFeed.sol");

        bytecodes[6].contractType = "PRICE_FEED::CURVE_STABLE";
        bytecodes[6].version = 3_10;
        bytecodes[6].initCode = type(CurveStableLPPriceFeed).creationCode;
        bytecodes[6].source = string.concat(oracles, "/contracts/oracles/curve/CurveStableLPPriceFeed.sol");

        bytecodes[7].contractType = "PRICE_FEED::CURVE_USD";
        bytecodes[7].version = 3_10;
        bytecodes[7].initCode = type(CurveUSDPriceFeed).creationCode;
        bytecodes[7].source = string.concat(oracles, "/contracts/oracles/curve/CurveUSDPriceFeed.sol");

        bytecodes[8].contractType = "PRICE_FEED::ERC4626";
        bytecodes[8].version = 3_10;
        bytecodes[8].initCode = type(ERC4626PriceFeed).creationCode;
        bytecodes[8].source = string.concat(oracles, "/contracts/oracles/erc4626/ERC4626PriceFeed.sol");

        bytecodes[9].contractType = "PRICE_FEED::WSTETH";
        bytecodes[9].version = 3_10;
        bytecodes[9].initCode = type(WstETHPriceFeed).creationCode;
        bytecodes[9].source = string.concat(oracles, "/contracts/oracles/lido/WstETHPriceFeed.sol");

        bytecodes[10].contractType = "PRICE_FEED::MELLOW_LRT";
        bytecodes[10].version = 3_10;
        bytecodes[10].initCode = type(MellowLRTPriceFeed).creationCode;
        bytecodes[10].source = string.concat(oracles, "/contracts/oracles/mellow/MellowLRTPriceFeed.sol");

        bytecodes[11].contractType = "PRICE_FEED::PENDLE_PT_TWAP";
        bytecodes[11].version = 3_10;
        bytecodes[11].initCode = type(PendleTWAPPTPriceFeed).creationCode;
        bytecodes[11].source = string.concat(oracles, "/contracts/oracles/pendle/PendleTWAPPTPriceFeed.sol");

        bytecodes[12].contractType = "PRICE_FEED::PYTH";
        bytecodes[12].version = 3_10;
        bytecodes[12].initCode = type(PythPriceFeed).creationCode;
        bytecodes[12].source = string.concat(oracles, "/contracts/oracles/updatable/PythPriceFeed.sol");

        bytecodes[13].contractType = "PRICE_FEED::REDSTONE";
        bytecodes[13].version = 3_10;
        bytecodes[13].initCode = type(RedstonePriceFeed).creationCode;
        bytecodes[13].source = string.concat(oracles, "/contracts/oracles/updatable/RedstonePriceFeed.sol");

        bytecodes[14].contractType = "PRICE_FEED::YEARN";
        bytecodes[14].version = 3_10;
        bytecodes[14].initCode = type(YearnPriceFeed).creationCode;
        bytecodes[14].source = string.concat(oracles, "/contracts/oracles/yearn/YearnPriceFeed.sol");
    }

    function _getRateKeeperContracts() internal view returns (Bytecode[] memory bytecodes) {
        bytecodes = new Bytecode[](2);

        bytecodes[0].contractType = "RATE_KEEPER::GAUGE";
        bytecodes[0].version = 3_10;
        bytecodes[0].initCode = type(GaugeV3).creationCode;
        bytecodes[0].source = string.concat(core, "/contracts/pool/GaugeV3.sol");

        bytecodes[1].contractType = "RATE_KEEPER::TUMBLER";
        bytecodes[1].version = 3_10;
        bytecodes[1].initCode = type(TumblerV3).creationCode;
        bytecodes[1].source = string.concat(core, "/contracts/pool/TumblerV3.sol");
    }

    function _getZapperContracts() internal view returns (Bytecode[] memory bytecodes) {
        bytecodes = new Bytecode[](6);

        bytecodes[0].contractType = "ZAPPER::UNDERLYING_DEPOSIT";
        bytecodes[0].version = 3_10;
        bytecodes[0].initCode = type(UnderlyingDepositZapper).creationCode;
        bytecodes[0].source = string.concat(integrations, "/contracts/zappers/UnderlyingDepositZapper.sol");

        bytecodes[1].contractType = "ZAPPER::UNDERLYING_FARMING";
        bytecodes[1].version = 3_10;
        bytecodes[1].initCode = type(UnderlyingFarmingZapper).creationCode;
        bytecodes[1].source = string.concat(integrations, "/contracts/zappers/UnderlyingFarmingZapper.sol");

        bytecodes[2].contractType = "ZAPPER::WETH_DEPOSIT";
        bytecodes[2].version = 3_10;
        bytecodes[2].initCode = type(WETHDepositZapper).creationCode;
        bytecodes[2].source = string.concat(integrations, "/contracts/zappers/WETHDepositZapper.sol");

        bytecodes[3].contractType = "ZAPPER::WETH_FARMING";
        bytecodes[3].version = 3_10;
        bytecodes[3].initCode = type(WETHFarmingZapper).creationCode;
        bytecodes[3].source = string.concat(integrations, "/contracts/zappers/WETHFarmingZapper.sol");

        bytecodes[4].contractType = "ZAPPER::WSTETH_DEPOSIT";
        bytecodes[4].version = 3_10;
        bytecodes[4].initCode = type(WstETHDepositZapper).creationCode;
        bytecodes[4].source = string.concat(integrations, "/contracts/zappers/WstETHDepositZapper.sol");

        bytecodes[5].contractType = "ZAPPER::WSTETH_FARMING";
        bytecodes[5].version = 3_10;
        bytecodes[5].initCode = type(WstETHFarmingZapper).creationCode;
        bytecodes[5].source = string.concat(integrations, "/contracts/zappers/WstETHFarmingZapper.sol");
    }
}
