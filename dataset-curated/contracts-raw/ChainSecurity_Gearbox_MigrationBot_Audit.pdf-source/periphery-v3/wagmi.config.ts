import { defineConfig, Plugin } from "@wagmi/cli";
import { foundry, FoundryConfig } from "@wagmi/cli/plugins";

const namingPlugin = (suffix = "V310", trim = "V3") => (config: FoundryConfig = {}): Plugin => {
  const plugin = foundry(config);
  return {
    ...plugin,
    contracts: async () => {
      const contracts = await plugin.contracts();
      return contracts.map((contract) => {
        return {
          ...contract,
          name: contract.name.replaceAll(trim, "").concat(suffix),
        };
      });
    },
  };
};

export default defineConfig([
  {
    out: "./compressors.generated.ts",
    plugins: [
      foundry({
        artifacts: "out",
        forge: {
          build: false,
          clean: false,
          rebuild: false,
        },
        include: [
          "ICreditAccountCompressor.sol/**.json",
          "ICreditSuiteCompressor.sol/**.json",
          "IGaugeCompressor.sol/**.json",
          "IMarketCompressor.sol/**.json",
          "IPeripheryCompressor.sol/**.json",
          "IPriceFeedCompressor.sol/**.json",
          "IRewardsCompressor.sol/**.json",
          "ITokenCompressor.sol/**.json",
        ],
      }),
    ],
  },
  {
    out: "./adapters.generated.ts",
    plugins: [
      foundry({
        artifacts: "out",
        forge: {
          build: false,
          clean: false,
          rebuild: false,
        },
        include: [
          "IAaveV2_LendingPoolAdapter.sol/**.json",
          "IAaveV2_WrappedATokenAdapter.sol/**.json",
          "IBalancerV2VaultAdapter.sol/**.json",
          "IBalancerV3RouterAdapter.sol/**.json",
          "ICamelotV3Adapter.sol/**.json",
          "ICompoundV2_CTokenAdapter.sol/**.json",
          "IConvexV1BaseRewardPoolAdapter.sol/**.json",
          "IConvexV1BoosterAdapter.sol/**.json",
          "ICurveV1Adapter.sol/**.json",
          "ICurveV1_2AssetsAdapter.sol/**.json",
          "ICurveV1_3AssetsAdapter.sol/**.json",
          "ICurveV1_4AssetsAdapter.sol/**.json",
          "ICurveV1_StableNGAdapter.sol/**.json",
          "IEqualizerRouterAdapter.sol/**.json",
          "IERC4626Adapter.sol/**.json",
          "ILidoV1Adapter.sol/**.json",
          "IwstETHV1Adapter.sol/**.json",
          "IMellowVaultAdapter.sol/**.json",
          "IPendleRouterAdapter.sol/**.json",
          "IDaiUsdsAdapter.sol/**.json",
          "IStakingRewardsAdapter.sol/**.json",
          "IUniswapV2Adapter.sol/**.json",
          "IUniswapV3Adapter.sol/**.json",
          "IVelodromeV2RouterAdapter.sol/**.json",
          "IYearnV2Adapter.sol/**.json",
        ],
      }),
    ],
  },
  {
    out: "./v310.generated.ts",
    plugins: [
      namingPlugin()({
        artifacts: "out",
        forge: {
          build: false,
          clean: false,
          rebuild: false,
        },
        include: [
          "IAddressProvider.sol/IAddressProvider.json",
          "IBotListV3.sol/IBotListV3.json",
          "ICreditConfiguratorV3.sol/ICreditConfiguratorV3.json",
          "ICreditFacadeV3.sol/ICreditFacadeV3.json",
          "ICreditFacadeV3Multicall.sol/ICreditFacadeV3Multicall.json",
          "ICreditManagerV3.sol/ICreditManagerV3.json",
          "IGaugeV3.sol/IGaugeV3.json",
          "ILossPolicy.sol/ILossPolicy.json",
          "IMarketConfigurator.sol/IMarketConfigurator.json",
          "IPoolQuotaKeeperV3.sol/IPoolQuotaKeeperV3.json",
          "IPoolV3.sol/IPoolV3.json",
          "IPriceOracleV3.sol/IPriceOracleV3.json",
          "ITumblerV3.sol/ITumblerV3.json",
        ],
        exclude: [
          "base/IAddressProvider.sol/IAddressProvider.json"
        ]
      }),
    ],
  }
]);
