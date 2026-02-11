// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {Test} from "forge-std/Test.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {AdapterType} from "@gearbox-protocol/sdk-gov/contracts/AdapterType.sol";

import {IACL} from "@gearbox-protocol/governance/contracts/interfaces/IACL.sol";
import {IAdapter} from "@gearbox-protocol/core-v3/contracts/interfaces/base/IAdapter.sol";
import {ICreditManagerV3} from "@gearbox-protocol/core-v3/contracts/interfaces/ICreditManagerV3.sol";

import {ConvexStakedPositionToken} from
    "@gearbox-protocol/integrations-v3/contracts/helpers/convex/ConvexV1_StakedPositionToken.sol";
import {StakingRewardsPhantomToken} from
    "@gearbox-protocol/integrations-v3/contracts/helpers/sky/StakingRewardsPhantomToken.sol";
import {IBaseRewardPool} from "@gearbox-protocol/integrations-v3/contracts/integrations/convex/IBaseRewardPool.sol";

import {
    UniswapV2Adapter,
    UniswapV2PairStatus
} from "@gearbox-protocol/integrations-v3/contracts/adapters/uniswap/UniswapV2.sol";
import {
    UniswapV3Adapter,
    UniswapV3PoolStatus
} from "@gearbox-protocol/integrations-v3/contracts/adapters/uniswap/UniswapV3.sol";
import {YearnV2Adapter} from "@gearbox-protocol/integrations-v3/contracts/adapters/yearn/YearnV2.sol";
import {ERC4626Adapter} from "@gearbox-protocol/integrations-v3/contracts/adapters/erc4626/ERC4626Adapter.sol";
import {LidoV1Adapter} from "@gearbox-protocol/integrations-v3/contracts/adapters/lido/LidoV1.sol";
import {WstETHV1Adapter} from "@gearbox-protocol/integrations-v3/contracts/adapters/lido/WstETHV1.sol";
import {BalancerV2VaultAdapter} from
    "@gearbox-protocol/integrations-v3/contracts/adapters/balancer/BalancerV2VaultAdapter.sol";
import {
    CamelotV3Adapter,
    CamelotV3PoolStatus
} from "@gearbox-protocol/integrations-v3/contracts/adapters/camelot/CamelotV3Adapter.sol";
import {PendleRouterAdapter} from "@gearbox-protocol/integrations-v3/contracts/adapters/pendle/PendleRouterAdapter.sol";
import {PendlePairStatus} from "@gearbox-protocol/integrations-v3/contracts/interfaces/pendle/IPendleRouterAdapter.sol";
import {CurveV1Adapter2Assets} from "@gearbox-protocol/integrations-v3/contracts/adapters/curve/CurveV1_2.sol";
import {CurveV1Adapter3Assets} from "@gearbox-protocol/integrations-v3/contracts/adapters/curve/CurveV1_3.sol";
import {CurveV1Adapter4Assets} from "@gearbox-protocol/integrations-v3/contracts/adapters/curve/CurveV1_4.sol";
import {CurveV1AdapterStableNG} from "@gearbox-protocol/integrations-v3/contracts/adapters/curve/CurveV1_StableNg.sol";
import {ConvexV1BaseRewardPoolAdapter} from
    "@gearbox-protocol/integrations-v3/contracts/adapters/convex/ConvexV1_BaseRewardPool.sol";
import {ConvexV1BoosterAdapter} from "@gearbox-protocol/integrations-v3/contracts/adapters/convex/ConvexV1_Booster.sol";
import {
    VelodromeV2RouterAdapter,
    VelodromeV2PoolStatus
} from "@gearbox-protocol/integrations-v3/contracts/adapters/velodrome/VelodromeV2RouterAdapter.sol";
import {DaiUsdsAdapter} from "@gearbox-protocol/integrations-v3/contracts/adapters/sky/DaiUsdsAdapter.sol";
import {StakingRewardsAdapter} from "@gearbox-protocol/integrations-v3/contracts/adapters/sky/StakingRewardsAdapter.sol";
import {BalancerV3RouterAdapter} from
    "@gearbox-protocol/integrations-v3/contracts/adapters/balancer/BalancerV3RouterAdapter.sol";
import {
    MellowVaultAdapter,
    MellowUnderlyingStatus
} from "@gearbox-protocol/integrations-v3/contracts/adapters/mellow/MellowVaultAdapter.sol";
import {Mellow4626VaultAdapter} from
    "@gearbox-protocol/integrations-v3/contracts/adapters/mellow/Mellow4626VaultAdapter.sol";

interface IOldAdapter {
    function _gearboxAdapterType() external view returns (AdapterType aType);
}

interface IOldMellowVaultAdapter {
    function isUnderlyingAllowed(address underlying) external view returns (bool);
}

address constant VELODROME_DEFAULT_FACTORY = 0xF1046053aa5682b4F9a81b5481394DA16BE5FF5a;

contract IntegrationCloner is Test {
    address public configurator;

    mapping(address => address) public oldToNewPhantomToken;
    mapping(address => address) public oldToNewAdapter;

    address[] internal _phantomTokens;

    constructor(address _configurator) {
        configurator = _configurator;
    }

    function migratePhantomToken(address oldToken) external returns (address newToken) {
        if (oldToNewPhantomToken[oldToken] != address(0)) return oldToNewPhantomToken[oldToken];

        string memory symbol = ERC20(oldToken).symbol();

        uint8 phantomTokenType = _getPhantomTokenType(symbol);

        if (phantomTokenType == 0) {
            return address(0);
        } else if (phantomTokenType == 1) {
            address pool = ConvexStakedPositionToken(oldToken).pool();
            address lpToken = address(IBaseRewardPool(pool).stakingToken());
            address booster = IBaseRewardPool(pool).operator();

            vm.prank(configurator);
            newToken = address(new ConvexStakedPositionToken(pool, lpToken, booster));
        } else if (phantomTokenType == 2) {
            address pool = StakingRewardsPhantomToken(oldToken).pool();

            vm.prank(configurator);
            newToken = address(new StakingRewardsPhantomToken(pool));
        }

        oldToNewPhantomToken[oldToken] = newToken;
        _phantomTokens.push(newToken);
    }

    function _getPhantomTokenType(string memory symbol) internal pure returns (uint8) {
        if (keccak256(abi.encode(symbol)) == keccak256(abi.encode("stkRLUSD/USDC"))) return 1;
        if (keccak256(abi.encode(symbol)) == keccak256(abi.encode("stkcvxllamathena"))) return 1;
        if (keccak256(abi.encode(symbol)) == keccak256(abi.encode("stkUSDS"))) return 2;

        return 0;
    }

    function migrateAdapter(address oldAdapter, address oldCreditManager, address newCreditManager)
        external
        returns (address newAdapter)
    {
        AdapterType aType = IOldAdapter(oldAdapter)._gearboxAdapterType();

        address targetContract = IAdapter(oldAdapter).targetContract();

        /// UNISWAP V2
        if (aType == AdapterType.UNISWAP_V2_ROUTER) {
            vm.prank(configurator);
            newAdapter = address(new UniswapV2Adapter(newCreditManager, targetContract));

            // uint256 collateralTokensCount = ICreditManagerV3(newCreditManager).collateralTokensCount();

            // for (uint256 i = 0; i < collateralTokensCount; ++i) {
            //     for (uint256 j = i + 1; j < collateralTokensCount; ++j) {
            //         address token0 = ICreditManagerV3(oldCreditManager).getTokenByMask(1 << i);
            //         address token1 = ICreditManagerV3(oldCreditManager).getTokenByMask(1 << j);

            //         if (UniswapV2Adapter(oldAdapter).isPairAllowed(token0, token1)) {
            //             UniswapV2PairStatus[] memory pairs = new UniswapV2PairStatus[](1);
            //             pairs[0] = UniswapV2PairStatus({token0: token0, token1: token1, allowed: true});

            //             vm.prank(configurator);
            //             UniswapV2Adapter(newAdapter).setPairStatusBatch(pairs);
            //         }
            //     }
            // }
        }
        /// UNISWAP V3
        else if (aType == AdapterType.UNISWAP_V3_ROUTER) {
            vm.prank(configurator);
            newAdapter = address(new UniswapV3Adapter(newCreditManager, targetContract));

            // uint256 collateralTokensCount = ICreditManagerV3(newCreditManager).collateralTokensCount();

            // for (uint256 i = 0; i < collateralTokensCount; ++i) {
            //     for (uint256 j = i + 1; j < collateralTokensCount; ++j) {
            //         for (uint256 k = 0; k < 9; ++k) {
            //             address token0 = ICreditManagerV3(oldCreditManager).getTokenByMask(1 << i);
            //             address token1 = ICreditManagerV3(oldCreditManager).getTokenByMask(1 << j);
            //             uint24 fee = _getUniswapV3Fee(k);

            //             if (UniswapV3Adapter(oldAdapter).isPoolAllowed(token0, token1, fee)) {
            //                 UniswapV3PoolStatus[] memory pools = new UniswapV3PoolStatus[](1);
            //                 pools[0] = UniswapV3PoolStatus({token0: token0, token1: token1, fee: fee, allowed: true});

            //                 vm.prank(configurator);
            //                 UniswapV3Adapter(newAdapter).setPoolStatusBatch(pools);
            //             }
            //         }
            //     }
            // }
        }
        /// YEARN V2
        else if (aType == AdapterType.YEARN_V2) {
            vm.prank(configurator);
            newAdapter = address(new YearnV2Adapter(newCreditManager, targetContract));
        }
        /// ERC4626
        else if (aType == AdapterType.ERC4626_VAULT) {
            vm.prank(configurator);
            newAdapter = address(new ERC4626Adapter(newCreditManager, targetContract));
        }
        /// LIDO V1
        else if (aType == AdapterType.LIDO_V1) {
            vm.prank(configurator);
            newAdapter = address(new LidoV1Adapter(newCreditManager, targetContract));
        }
        /// WSTETH V1
        else if (aType == AdapterType.LIDO_WSTETH_V1) {
            vm.prank(configurator);
            newAdapter = address(new WstETHV1Adapter(newCreditManager, targetContract));
        }
        /// BALANCER VAULT
        else if (aType == AdapterType.BALANCER_VAULT) {
            vm.prank(configurator);
            newAdapter = address(new BalancerV2VaultAdapter(newCreditManager, targetContract));

            /// CLONE BALANCER POOLS
            /// event: SetPoolStatus(poolId, newStatus);
            /// function: setPoolStatus(bytes32 poolId, PoolStatus newStatus)
        }
        /// CAMELOT V3
        else if (aType == AdapterType.CAMELOT_V3_ROUTER) {
            vm.prank(configurator);
            newAdapter = address(new CamelotV3Adapter(newCreditManager, targetContract));

            // uint256 collateralTokensCount = ICreditManagerV3(newCreditManager).collateralTokensCount();

            // for (uint256 i = 0; i < collateralTokensCount; ++i) {
            //     for (uint256 j = i + 1; j < collateralTokensCount; ++j) {
            //         address token0 = ICreditManagerV3(oldCreditManager).getTokenByMask(1 << i);
            //         address token1 = ICreditManagerV3(oldCreditManager).getTokenByMask(1 << j);

            //         if (CamelotV3Adapter(oldAdapter).isPoolAllowed(token0, token1)) {
            //             CamelotV3PoolStatus[] memory pools = new CamelotV3PoolStatus[](1);
            //             pools[0] = CamelotV3PoolStatus({token0: token0, token1: token1, allowed: true});

            //             vm.prank(configurator);
            //             CamelotV3Adapter(newAdapter).setPoolStatusBatch(pools);
            //         }
            //     }
            // }
        }
        /// VELODROME V2
        else if (aType == AdapterType.VELODROME_V2_ROUTER) {
            vm.prank(configurator);
            newAdapter = address(new VelodromeV2RouterAdapter(newCreditManager, targetContract));

            // uint256 collateralTokensCount = ICreditManagerV3(newCreditManager).collateralTokensCount();

            // for (uint256 i = 0; i < collateralTokensCount; ++i) {
            //     for (uint256 j = i + 1; j < collateralTokensCount; ++j) {
            //         for (uint256 k = 0; k < 2; ++k) {
            //             address token0 = ICreditManagerV3(oldCreditManager).getTokenByMask(1 << i);
            //             address token1 = ICreditManagerV3(oldCreditManager).getTokenByMask(1 << j);

            //             if (
            //                 VelodromeV2RouterAdapter(oldAdapter).isPoolAllowed(
            //                     token0, token1, k == 0, VELODROME_DEFAULT_FACTORY
            //                 )
            //             ) {
            //                 VelodromeV2PoolStatus[] memory pools = new VelodromeV2PoolStatus[](1);
            //                 pools[0] = VelodromeV2PoolStatus({
            //                     token0: token0,
            //                     token1: token1,
            //                     stable: k == 0,
            //                     factory: VELODROME_DEFAULT_FACTORY,
            //                     allowed: true
            //                 });

            //                 vm.prank(configurator);
            //                 VelodromeV2RouterAdapter(newAdapter).setPoolStatusBatch(pools);
            //             }
            //         }
            //     }
            // }
        }
        /// PENDLE ROUTER
        else if (aType == AdapterType.PENDLE_ROUTER) {
            vm.prank(configurator);
            newAdapter = address(new PendleRouterAdapter(newCreditManager, targetContract));

            PendlePairStatus[] memory pendlePairs = PendleRouterAdapter(oldAdapter).getAllowedPairs();

            vm.prank(configurator);
            PendleRouterAdapter(newAdapter).setPairStatusBatch(pendlePairs);
        }
        /// CURVE V1 2 ASSETS
        else if (aType == AdapterType.CURVE_V1_2ASSETS) {
            address lpToken = CurveV1Adapter2Assets(oldAdapter).lp_token();
            address metapoolBase = CurveV1Adapter2Assets(oldAdapter).metapoolBase();
            bool use256 = CurveV1Adapter2Assets(oldAdapter).use256();

            vm.prank(configurator);
            newAdapter =
                address(new CurveV1Adapter2Assets(newCreditManager, targetContract, lpToken, metapoolBase, use256));
        }
        /// CURVE V1 3 ASSETS
        else if (aType == AdapterType.CURVE_V1_3ASSETS) {
            address lpToken = CurveV1Adapter3Assets(oldAdapter).lp_token();
            address metapoolBase = CurveV1Adapter3Assets(oldAdapter).metapoolBase();
            bool use256 = CurveV1Adapter3Assets(oldAdapter).use256();

            vm.prank(configurator);
            newAdapter =
                address(new CurveV1Adapter3Assets(newCreditManager, targetContract, lpToken, metapoolBase, use256));
        }
        /// CURVE V1 4 ASSETS
        else if (aType == AdapterType.CURVE_V1_4ASSETS) {
            address lpToken = CurveV1Adapter4Assets(oldAdapter).lp_token();
            address metapoolBase = CurveV1Adapter4Assets(oldAdapter).metapoolBase();
            bool use256 = CurveV1Adapter4Assets(oldAdapter).use256();

            vm.prank(configurator);
            newAdapter =
                address(new CurveV1Adapter4Assets(newCreditManager, targetContract, lpToken, metapoolBase, use256));
        } else if (aType == AdapterType.CURVE_STABLE_NG) {
            address lpToken = CurveV1AdapterStableNG(oldAdapter).lp_token();
            address metapoolBase = CurveV1AdapterStableNG(oldAdapter).metapoolBase();
            bool use256 = CurveV1AdapterStableNG(oldAdapter).use256();

            vm.prank(configurator);
            newAdapter =
                address(new CurveV1AdapterStableNG(newCreditManager, targetContract, lpToken, metapoolBase, use256));
        }
        /// CONVEX V1 BASE REWARD POOL
        else if (aType == AdapterType.CONVEX_V1_BASE_REWARD_POOL) {
            address stakedPhantomToken =
                oldToNewPhantomToken[ConvexV1BaseRewardPoolAdapter(oldAdapter).stakedPhantomToken()];

            vm.prank(configurator);
            newAdapter =
                address(new ConvexV1BaseRewardPoolAdapter(newCreditManager, targetContract, stakedPhantomToken));
        }
        /// CONVEX V1 BOOSTER
        else if (aType == AdapterType.CONVEX_V1_BOOSTER) {
            vm.prank(configurator);
            newAdapter = address(new ConvexV1BoosterAdapter(newCreditManager, targetContract));
        }
        /// DAI USDS
        else if (aType == AdapterType.DAI_USDS_EXCHANGE) {
            vm.prank(configurator);
            newAdapter = address(new DaiUsdsAdapter(newCreditManager, targetContract));
        }
        /// STAKING REWARDS
        else if (aType == AdapterType.STAKING_REWARDS) {
            address stakedPhantomToken = oldToNewPhantomToken[StakingRewardsAdapter(oldAdapter).stakedPhantomToken()];

            vm.prank(configurator);
            newAdapter = address(new StakingRewardsAdapter(newCreditManager, targetContract, stakedPhantomToken, 0));
        }
        /// MELLOW LRT VAULT
        else if (aType == AdapterType.MELLOW_LRT_VAULT) {
            vm.prank(configurator);
            newAdapter = address(new MellowVaultAdapter(newCreditManager, targetContract));

            // uint256 collateralTokensCount = ICreditManagerV3(newCreditManager).collateralTokensCount();

            // for (uint256 i = 0; i < collateralTokensCount; ++i) {
            //     address token = ICreditManagerV3(oldCreditManager).getTokenByMask(1 << i);

            //     if (IOldMellowVaultAdapter(oldAdapter).isUnderlyingAllowed(token)) {
            //         MellowUnderlyingStatus[] memory underlyings = new MellowUnderlyingStatus[](1);
            //         underlyings[0] = MellowUnderlyingStatus({underlying: token, allowed: true});

            //         vm.prank(configurator);
            //         MellowVaultAdapter(newAdapter).setUnderlyingStatusBatch(underlyings);
            //     }
            // }
        }
        /// BALANCER V3
        else if (aType == AdapterType.BALANCER_V3_ROUTER) {
            vm.prank(configurator);
            newAdapter = address(new BalancerV3RouterAdapter(newCreditManager, targetContract));

            address[] memory pools = BalancerV3RouterAdapter(oldAdapter).getAllowedPools();

            bool[] memory statuses = new bool[](pools.length);

            for (uint256 i = 0; i < pools.length; ++i) {
                statuses[i] = true;
            }

            vm.prank(configurator);
            BalancerV3RouterAdapter(newAdapter).setPoolStatusBatch(pools, statuses);
        }
        /// MELLOW ERC4626 VAULT
        else if (aType == AdapterType.MELLOW_ERC4626_VAULT) {
            vm.prank(configurator);
            newAdapter = address(new Mellow4626VaultAdapter(newCreditManager, targetContract, targetContract));
        }

        oldToNewAdapter[oldAdapter] = newAdapter;
    }

    function configureAdapters(address[] memory adapters) external {
        for (uint256 i = 0; i < adapters.length; ++i) {
            if (IAdapter(adapters[i]).contractType() == "ADAPTER::CVX_V1_BOOSTER") {
                vm.prank(configurator);
                ConvexV1BoosterAdapter(adapters[i]).updateSupportedPids();
            }
        }
    }

    function phantomTokens() external view returns (address[] memory) {
        return _phantomTokens;
    }

    function _getUniswapV3Fee(uint256 i) internal pure returns (uint24) {
        if (i == 0) return 1;
        if (i == 1) return 50;
        if (i == 2) return 100;
        if (i == 3) return 200;
        if (i == 4) return 20000;
        if (i == 5) return 100;
        if (i == 6) return 500;
        if (i == 7) return 3000;
        if (i == 8) return 10000;

        return 0;
    }
}
