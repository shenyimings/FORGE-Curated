// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import { Test } from "forge-std/Test.sol";
import { console } from "forge-std/console.sol";

import { ProxyAdmin } from "@openzeppelin/contracts-v4/proxy/transparent/ProxyAdmin.sol";
import { TransparentUpgradeableProxy, ITransparentUpgradeableProxy } from "@openzeppelin/contracts-v4/proxy/transparent/TransparentUpgradeableProxy.sol";

import { MockAggregatorV3Interface } from "../../contracts/mocks/MockAggregatorV3Interface.sol";
import { MockCurveStableSwapNG } from "../../contracts/mocks/MockCurveStableSwapNG.sol";
import { MockPriceOracle } from "../../contracts/mocks/MockPriceOracle.sol";
import { MockRateProvider } from "../../contracts/mocks/MockRateProvider.sol";
import { MockAaveV3Pool } from "../../contracts/mocks/MockAaveV3Pool.sol";
import { MockMultiPathConverter } from "../../contracts/mocks/MockMultiPathConverter.sol";
import { MockMultipleRewardDistributor } from "../../contracts/mocks/MockMultipleRewardDistributor.sol";
import { MockERC20 } from "../../contracts/mocks/MockERC20.sol";

import { AaveFundingPool } from "../../contracts/core/pool/AaveFundingPool.sol";
import { FxUSDBasePool } from "../../contracts/core/FxUSDBasePool.sol";
import { FxUSDRegeneracy } from "../../contracts/core/FxUSDRegeneracy.sol";
import { PegKeeper } from "../../contracts/core/PegKeeper.sol";
import { PoolManager } from "../../contracts/core/PoolManager.sol";
import { ReservePool } from "../../contracts/core/ReservePool.sol";
import { EmptyContract } from "../../contracts/helpers/EmptyContract.sol";
import { GaugeRewarder } from "../../contracts/helpers/GaugeRewarder.sol";

abstract contract PoolTestBase is Test {
  MockAggregatorV3Interface internal mockAggregatorV3Interface;
  MockCurveStableSwapNG internal mockCurveStableSwapNG;
  MockPriceOracle internal mockPriceOracle;
  MockRateProvider internal mockRateProvider;
  MockAaveV3Pool internal mockAaveV3Pool;
  MockMultiPathConverter private mockConverter;
  MockMultipleRewardDistributor private mockGauge;

  MockERC20 internal stableToken;
  MockERC20 internal collateralToken;

  address internal admin;
  address internal platform;

  ProxyAdmin internal proxyAdmin;
  GaugeRewarder internal rewarder;
  ReservePool internal reservePool;
  PoolManager internal poolManager;
  PegKeeper internal pegKeeper;
  FxUSDRegeneracy internal fxUSD;
  FxUSDBasePool internal fxBASE;
  AaveFundingPool internal pool;

  function __PoolTestBase_setUp(uint256 TokenRate, uint8 tokenDecimals) internal {
    platform = vm.addr(uint256(23333));
    admin = address(this);

    mockAggregatorV3Interface = new MockAggregatorV3Interface(8, 100000000);
    mockCurveStableSwapNG = new MockCurveStableSwapNG();
    mockPriceOracle = new MockPriceOracle(3000 ether, 2999 ether, 3001 ether);
    mockRateProvider = new MockRateProvider(TokenRate);
    mockAaveV3Pool = new MockAaveV3Pool(50000000000000000000000000);
    mockConverter = new MockMultiPathConverter();
    mockGauge = new MockMultipleRewardDistributor();

    EmptyContract empty = new EmptyContract();
    stableToken = new MockERC20("USDC", "USDC", 6);
    collateralToken = new MockERC20("X", "Y", tokenDecimals);
    proxyAdmin = new ProxyAdmin();

    TransparentUpgradeableProxy FxUSDRegeneracyProxy = new TransparentUpgradeableProxy(
      address(empty),
      address(proxyAdmin),
      new bytes(0)
    );

    TransparentUpgradeableProxy PegKeeperProxy = new TransparentUpgradeableProxy(
      address(empty),
      address(proxyAdmin),
      new bytes(0)
    );
    TransparentUpgradeableProxy PoolManagerProxy = new TransparentUpgradeableProxy(
      address(empty),
      address(proxyAdmin),
      new bytes(0)
    );
    TransparentUpgradeableProxy FxUSDBasePoolProxy = new TransparentUpgradeableProxy(
      address(empty),
      address(proxyAdmin),
      new bytes(0)
    );

    // deploy ReservePool
    reservePool = new ReservePool(admin, address(PoolManagerProxy));

    // deploy PoolManager
    PoolManager PoolManagerImpl = new PoolManager(
      address(FxUSDRegeneracyProxy),
      address(FxUSDBasePoolProxy),
      address(PegKeeperProxy)
    );
    proxyAdmin.upgradeAndCall(
      ITransparentUpgradeableProxy(address(PoolManagerProxy)),
      address(PoolManagerImpl),
      abi.encodeCall(PoolManager.initialize, (admin, 100000000, 10000000, 100000, platform, platform, address(reservePool)))
    );
    poolManager = PoolManager(address(PoolManagerProxy));

    // deploy FxUSDRegeneracy
    FxUSDRegeneracy FxUSDRegeneracyImpl = new FxUSDRegeneracy(
      address(PoolManagerProxy),
      address(stableToken),
      address(PegKeeperProxy)
    );
    proxyAdmin.upgrade(ITransparentUpgradeableProxy(address(FxUSDRegeneracyProxy)), address(FxUSDRegeneracyImpl));
    fxUSD = FxUSDRegeneracy(address(FxUSDRegeneracyProxy));
    fxUSD.initialize("f(x) USD", "fxUSD");
    fxUSD.initializeV2();

    // deploy FxUSDBasePool
    FxUSDBasePool FxUSDBasePoolImpl = new FxUSDBasePool(
      address(PoolManagerProxy),
      address(PegKeeperProxy),
      address(FxUSDRegeneracyProxy),
      address(stableToken),
      encodeChainlinkPriceFeed(address(mockAggregatorV3Interface), 10000000000, 1000000000)
    );
    proxyAdmin.upgrade(ITransparentUpgradeableProxy(address(FxUSDBasePoolProxy)), address(FxUSDBasePoolImpl));
    fxBASE = FxUSDBasePool(address(FxUSDBasePoolProxy));

    // deploy PegKeeper
    PegKeeper PegKeeperImpl = new PegKeeper(address(fxBASE));
    proxyAdmin.upgradeAndCall(
      ITransparentUpgradeableProxy(address(PegKeeperProxy)),
      address(PegKeeperImpl),
      abi.encodeCall(PegKeeper.initialize, (admin, address(mockConverter), address(mockCurveStableSwapNG)))
    );
    pegKeeper = PegKeeper(address(PegKeeperProxy));

    // deploy AaveFundingPool
    pool = new AaveFundingPool(address(poolManager), address(mockAaveV3Pool), address(stableToken));
    pool.initialize(admin, "f(x) wstETH position", "xstETH", address(collateralToken), address(mockPriceOracle));
    pool.updateRebalanceRatios(880000000000000000, 25000000);
    pool.updateLiquidateRatios(920000000000000000, 50000000);

    // deploy GaugeRewarder
    rewarder = new GaugeRewarder(address(mockGauge));

    // initialize
    poolManager.registerPool(address(pool), address(rewarder), uint96(1000000000 * 10 ** tokenDecimals), uint96(1000000000 ether));
    poolManager.updateRateProvider(address(collateralToken), address(mockRateProvider));
    mockCurveStableSwapNG.setCoin(0, address(stableToken));
    mockCurveStableSwapNG.setCoin(1, address(fxUSD));
    mockCurveStableSwapNG.setPriceOracle(0, 1 ether);
  }

  function encodeChainlinkPriceFeed(address feed, uint256 scale, uint256 heartbeat) internal pure returns (bytes32 r) {
    assembly {
      r := shl(96, feed)
      r := or(r, shl(32, scale))
      r := or(r, heartbeat)
    }
  }
}
