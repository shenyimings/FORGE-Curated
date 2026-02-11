// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.29;

import "./TestSingleSidedLPStrategy.sol";
import "../src/utils/Constants.sol";
import "../src/withdraws/GenericERC20.sol";
import "../src/withdraws/EtherFi.sol";
import "../src/withdraws/Ethena.sol";
import "../src/interfaces/ITradingModule.sol";
import "../src/withdraws/AbstractWithdrawRequestManager.sol";
import "./TestWithdrawRequestImpl.sol";

contract Test_LP_Convex_USDC_USDT is TestSingleSidedLPStrategy {
    function setMarketVariables() internal override {
        lpToken = ERC20(0x4f493B7dE8aAC7d55F71853688b1F7C8F0243C85);
        rewardPool = 0x83644fa70538e5251D125205186B14A76cA63606;
        asset = USDC;
        w = ERC20(rewardPool);
        curveInterface = CurveInterface.StableSwapNG;
        primaryIndex = 0;
        maxPoolShare = 100e18;
        dyAmount = 1e6;

        defaultDeposit = 10_000e6;
        defaultBorrow = 90_000e6;
    }
    
}

contract Test_LP_Convex_OETH_ETH is TestSingleSidedLPStrategy {
    function setMarketVariables() internal override {
        lpToken = ERC20(0x94B17476A93b3262d87B9a326965D1E91f9c13E7);
        rewardPool = 0x24b65DC1cf053A8D96872c323d29e86ec43eB33A;
        asset = ERC20(address(WETH));
        curveInterface = CurveInterface.V1;
        primaryIndex = 0;
        maxPoolShare = 100e18;
        dyAmount = 1e9;
        w = ERC20(rewardPool);

        defaultDeposit = 10e18;
        defaultBorrow = 90e18;

        (AggregatorV2V3Interface ethOracle, /* */) = TRADING_MODULE.priceOracles(ETH_ADDRESS);
        MockOracle oETHOracle = new MockOracle(ethOracle.latestAnswer() * 1e18 / 1e8);
        // TODO: there is no oETH oracle on mainnet
        vm.prank(owner);
        TRADING_MODULE.setPriceOracle(
            address(0x856c4Efb76C1D1AE02e20CEB03A2A6a08b0b8dC3),
            AggregatorV2V3Interface(address(oETHOracle))
        );
        maxExitValuationSlippage = 0.005e18;
    }
}

contract Test_LP_Convex_weETH_WETH is TestSingleSidedLPStrategy {
    function setMarketVariables() internal override {
        lpToken = ERC20(0xDB74dfDD3BB46bE8Ce6C33dC9D82777BCFc3dEd5);
        rewardPool = 0x5411CC583f0b51104fA523eEF9FC77A29DF80F58;
        asset = ERC20(address(WETH));
        stakeTokenIndex = 1;

        managers[0] = new GenericERC20WithdrawRequestManager(address(asset));
        managers[1] = new EtherFiWithdrawRequestManager();
        withdrawRequests[1] = new TestEtherFiWithdrawRequest();

        curveInterface = CurveInterface.StableSwapNG;
        primaryIndex = 0;
        maxPoolShare = 100e18;
        dyAmount = 1e9;
        w = ERC20(rewardPool);

        defaultDeposit = 10e18;
        defaultBorrow = 90e18;

        maxExitValuationSlippage = 0.005e18;

        tradeBeforeRedeemParams[0] = TradeParams({
            tradeType: TradeType.EXACT_IN_SINGLE,
            dexId: uint8(DexId.UNISWAP_V3),
            tradeAmount: 0,
            minPurchaseAmount: 0,
            exchangeData: abi.encode(UniV3SingleData({
                fee: 100
            }))
        });
    }

    function postDeploySetup() internal override {
        super.postDeploySetup();

        vm.startPrank(owner);
        TRADING_MODULE.setTokenPermissions(
            address(y),
            address(weETH),
            ITradingModule.TokenPermissions(
            { allowSell: true, dexFlags: uint32(1 << uint8(DexId.UNISWAP_V3)), tradeTypeFlags: 5 }
        ));
        vm.stopPrank();
    }
}

contract Test_LP_Curve_USDe_USDC is TestSingleSidedLPStrategy {
    function setMarketVariables() internal override {
        lpToken = ERC20(0x02950460E2b9529D0E00284A5fA2d7bDF3fA4d72);
        curveGauge = 0x04E80Db3f84873e4132B221831af1045D27f140F;
        w = ERC20(curveGauge);
        asset = ERC20(address(USDC));
        curveInterface = CurveInterface.StableSwapNG;
        primaryIndex = 1;
        maxPoolShare = 100e18;
        dyAmount = 1e6;

        defaultDeposit = 10_000e6;
        defaultBorrow = 90_000e6;

        maxExitValuationSlippage = 0.005e18;

        tradeBeforeDepositParams[0] = TradeParams({
            tradeType: TradeType.EXACT_IN_SINGLE,
            dexId: uint8(DexId.UNISWAP_V3),
            tradeAmount: 0,
            minPurchaseAmount: 0,
            exchangeData: abi.encode(UniV3SingleData({
                fee: 100
            }))
        });

        tradeBeforeRedeemParams[0] = TradeParams({
            tradeType: TradeType.EXACT_IN_SINGLE,
            dexId: uint8(DexId.UNISWAP_V3),
            tradeAmount: 0,
            minPurchaseAmount: 0,
            exchangeData: abi.encode(UniV3SingleData({
                fee: 100
            }))
        });
    }

    function postDeploySetup() internal override {
        super.postDeploySetup();

        vm.startPrank(owner);
        TRADING_MODULE.setTokenPermissions(
            address(y),
            address(asset),
            ITradingModule.TokenPermissions(
            { allowSell: true, dexFlags: uint32(1 << uint8(DexId.UNISWAP_V3)), tradeTypeFlags: 5 }
        ));
        TRADING_MODULE.setTokenPermissions(
            address(y),
            address(USDe),
            ITradingModule.TokenPermissions(
            { allowSell: true, dexFlags: uint32(1 << uint8(DexId.UNISWAP_V3)), tradeTypeFlags: 5 }
        ));
        vm.stopPrank();
    }
}

contract Test_LP_Curve_sDAI_sUSDe is TestSingleSidedLPStrategy {

    function getDepositData(address /* user */, uint256 depositAmount) internal pure override returns (bytes memory) {
        TradeParams[] memory depositTrades = new TradeParams[](2);
        uint256 sDAIAmount = depositAmount / 2;
        uint256 sUSDeAmount = depositAmount - sDAIAmount;
        bytes memory sDAI_StakeData = abi.encode(StakingTradeParams({
            tradeType: TradeType.EXACT_IN_SINGLE,
            dexId: uint8(DexId.CURVE_V2),
            minPurchaseAmount: 0,
            exchangeData: abi.encode(CurveV2SingleData({
                pool: 0xbEbc44782C7dB0a1A60Cb6fe97d0b483032FF1C7,
                fromIndex: 1,
                toIndex: 0
            })),
            stakeData: bytes("")
        }));
        bytes memory sUSDe_StakeData = abi.encode(StakingTradeParams({
            tradeType: TradeType.EXACT_IN_SINGLE,
            dexId: uint8(DexId.CURVE_V2),
            minPurchaseAmount: 0,
            exchangeData: abi.encode(CurveV2SingleData({
                pool: 0x02950460E2b9529D0E00284A5fA2d7bDF3fA4d72,
                fromIndex: 1,
                toIndex: 0
            })),
            stakeData: bytes("")
        }));

        depositTrades[0] = TradeParams({
            tradeType: TradeType.STAKE_TOKEN,
            dexId: 0,
            tradeAmount: sDAIAmount,
            minPurchaseAmount: 0,
            exchangeData: sDAI_StakeData
        });
        depositTrades[1] = TradeParams({
            tradeType: TradeType.STAKE_TOKEN,
            dexId: 0,
            tradeAmount: sUSDeAmount,
            minPurchaseAmount: 0,
            exchangeData: sUSDe_StakeData
        });

        return abi.encode(DepositParams({
            minPoolClaim: 0,
            depositTrades: depositTrades
        }));
    }

    function getRedeemData(address /* user */, uint256 /* redeemAmount */) internal override returns (bytes memory) {
        // TODO: There is no way to trade out of this position, therefore we cannot flash liquidate
        vm.skip(true);
        return bytes("");
    }

    function setMarketVariables() internal override {
        lpToken = ERC20(0x167478921b907422F8E88B43C4Af2B8BEa278d3A);
        curveGauge = 0x330Cfd12e0E97B0aDF46158D2A81E8Bd2985c6cB;
        w = ERC20(curveGauge);
        asset = ERC20(address(USDC));
        curveInterface = CurveInterface.StableSwapNG;
        primaryIndex = 1;
        usdOracleToken = address(sUSDe);
        maxPoolShare = 100e18;
        dyAmount = 1e6;

        defaultDeposit = 10_000e6;
        defaultBorrow = 90_000e6;

        maxExitValuationSlippage = 0.005e18;

        managers[0] = new GenericERC4626WithdrawRequestManager(address(sDAI));
        managers[1] = new EthenaWithdrawRequestManager();
        withdrawRequests[0] = new TestGenericERC4626WithdrawRequest();
        withdrawRequests[1] = new TestEthenaWithdrawRequest();

        tradeBeforeRedeemParams[0] = TradeParams({
            tradeType: TradeType.EXACT_IN_SINGLE,
            dexId: uint8(DexId.CURVE_V2),
            tradeAmount: 0,
            minPurchaseAmount: 0,
            exchangeData: abi.encode(CurveV2SingleData({
                pool: 0xbEbc44782C7dB0a1A60Cb6fe97d0b483032FF1C7,
                fromIndex: 0,
                toIndex: 1
            }))
        });

        tradeBeforeRedeemParams[1] = TradeParams({
            tradeType: TradeType.EXACT_IN_SINGLE,
            dexId: uint8(DexId.CURVE_V2),
            tradeAmount: 0,
            minPurchaseAmount: 0,
            exchangeData: abi.encode(CurveV2SingleData({
                pool: 0x02950460E2b9529D0E00284A5fA2d7bDF3fA4d72,
                fromIndex: 0,
                toIndex: 1
            }))
        });

        vm.startPrank(owner);
        MockOracle sDAIOracle = new MockOracle(1156574190016110658);
        TRADING_MODULE.setPriceOracle(address(sDAI), AggregatorV2V3Interface(address(sDAIOracle)));
        vm.stopPrank();

    }

    function postDeploySetup() internal override {
        super.postDeploySetup();

        vm.startPrank(owner);
        TRADING_MODULE.setTokenPermissions(
            address(y),
            address(asset),
            ITradingModule.TokenPermissions(
            { allowSell: true, dexFlags: uint32(1 << uint8(DexId.CURVE_V2)), tradeTypeFlags: 5 }
        ));
        TRADING_MODULE.setTokenPermissions(
            address(y),
            address(sUSDe),
            ITradingModule.TokenPermissions(
            { allowSell: true, dexFlags: uint32(1 << uint8(DexId.CURVE_V2)), tradeTypeFlags: 5 }
        ));
        TRADING_MODULE.setTokenPermissions(
            address(y),
            address(USDe),
            ITradingModule.TokenPermissions(
            { allowSell: true, dexFlags: uint32(1 << uint8(DexId.CURVE_V2)), tradeTypeFlags: 5 }
        ));
        TRADING_MODULE.setTokenPermissions(
            address(y),
            address(DAI),
            ITradingModule.TokenPermissions(
            { allowSell: true, dexFlags: uint32(1 << uint8(DexId.CURVE_V2)), tradeTypeFlags: 5 }
        ));

        // Allow withdraw managers to sell USDC
        TRADING_MODULE.setTokenPermissions(
            address(managers[0]),
            address(USDC),
            ITradingModule.TokenPermissions(
            { allowSell: true, dexFlags: uint32(1 << uint8(DexId.CURVE_V2)), tradeTypeFlags: 5 }
        ));
        TRADING_MODULE.setTokenPermissions(
            address(managers[1]),
            address(USDC),
            ITradingModule.TokenPermissions(
            { allowSell: true, dexFlags: uint32(1 << uint8(DexId.CURVE_V2)), tradeTypeFlags: 5 }
        ));
        // Allow Ethena manager to sell DAI
        TRADING_MODULE.setTokenPermissions(
            address(y),
            address(DAI),
            ITradingModule.TokenPermissions(
            { allowSell: true, dexFlags: uint32(1 << uint8(DexId.CURVE_V2)), tradeTypeFlags: 5 }
        ));
        vm.stopPrank();
    }
}

contract Test_LP_Curve_pxETH_ETH is TestSingleSidedLPStrategy {
    function setMarketVariables() internal override {
        lpToken = ERC20(0xC8Eb2Cf2f792F77AF0Cd9e203305a585E588179D);
        rewardPool = 0x3B793E505A3C7dbCb718Fe871De8eBEf7854e74b;
        asset = ERC20(address(WETH));
        stakeTokenIndex = 1;

        managers[0] = new GenericERC20WithdrawRequestManager(address(WETH));
        managers[1] = new DineroWithdrawRequestManager(address(pxETH));
        withdrawRequests[0] = new TestGenericERC20WithdrawRequest();
        withdrawRequests[1] = new TestDinero_pxETH_WithdrawRequest();

        curveInterface = CurveInterface.StableSwapNG;
        primaryIndex = 0;
        maxPoolShare = 100e18;
        dyAmount = 1e9;

        defaultDeposit = 10e18;
        defaultBorrow = 90e18;

        maxEntryValuationSlippage = 0.002e18;
        maxExitValuationSlippage = 0.015e18;

        (AggregatorV2V3Interface ethOracle, /* */) = TRADING_MODULE.priceOracles(ETH_ADDRESS);
        MockOracle pxETHOracle = new MockOracle(ethOracle.latestAnswer() * 0.9996e18 / 1e8);
        // TODO: need a pxETH oracle
        vm.prank(owner);
        TRADING_MODULE.setPriceOracle(
            address(pxETH),
            AggregatorV2V3Interface(address(pxETHOracle))
        );
    }
}

// contract Test_LP_Curve_pxETH_stETH is TestSingleSidedLPStrategy {
//     function setMarketVariables() internal override {
//         lpToken = ERC20(0x6951bDC4734b9f7F3E1B74afeBC670c736A0EDB6);
//         rewardPool = 0x633556C8413FCFd45D83656290fF8d64EE41A7c1;
//         asset = ERC20(address(WETH));
//         stakeTokenIndex = 1;

//         // TODO: need a stETH withdraw manager
//         managers[0] = new GenericERC20WithdrawRequestManager(address(WETH));
//         managers[1] = new DineroWithdrawRequestManager(address(pxETH));
//         withdrawRequests[0] = new TestGenericERC20WithdrawRequest();
//         withdrawRequests[1] = new TestDineropxETHWithdrawRequest();

//         curveInterface = CurveInterface.StableSwapNG;
//         primaryIndex = 0;
//         maxPoolShare = 100e18;
//         dyAmount = 1e9;

//         defaultDeposit = 10e18;
//         defaultBorrow = 90e18;

//         maxEntryValuationSlippage = 0.002e18;
//         maxExitValuationSlippage = 0.015e18;

//         (AggregatorV2V3Interface ethOracle, /* */) = TRADING_MODULE.priceOracles(ETH_ADDRESS);
//         MockOracle pxETHOracle = new MockOracle(ethOracle.latestAnswer() * 0.9996e18 / 1e8);
//         // TODO: need a pxETH oracle
//         vm.prank(owner);
//         TRADING_MODULE.setPriceOracle(
//             address(pxETH),
//             AggregatorV2V3Interface(address(pxETHOracle))
//         );
//     }
// }

// contract Test_LP_Curve_tETH_weETH is TestSingleSidedLPStrategy {
//     function setMarketVariables() internal override {
//         lpToken = ERC20(0x394a1e1b934cb4F4a0dC17BDD592ec078741542F);
//         curveGauge = 0xFe964d3E779752C7598985436A8598F13f22F6F4;
//         w = ERC20(curveGauge);
//         asset = ERC20(address(WETH));
//         stakeTokenIndex = 1;

//         maxPoolShare = 100e18;
//         dyAmount = 1e9;

//         defaultDeposit = 10e18;
//         defaultBorrow = 90e18;

//         // TODO: need a tETH withdraw manager
//         managers[0] = new GenericERC20WithdrawRequestManager(address(WETH));
//         managers[1] = new EtherFiWithdrawRequestManager();
//         withdrawRequests[0] = new TestGenericERC20WithdrawRequest();
//         withdrawRequests[1] = new TestEtherFiWithdrawRequest();
//     }
// }

contract Test_LP_Curve_deUSD_USDC is TestSingleSidedLPStrategy {
    function overrideForkBlock() internal override {
        FORK_BLOCK = 22589309;
    }

    function setMarketVariables() internal override {
        lpToken = ERC20(0x5F6c431AC417f0f430B84A666a563FAbe681Da94);
        curveGauge = 0x4C1533350dfAaE6c55604160A5F70aD84A108b48;
        w = ERC20(curveGauge);
        asset = ERC20(address(USDC));
        curveInterface = CurveInterface.StableSwapNG;
        primaryIndex = 1;
        maxPoolShare = 100e18;
        dyAmount = 1e6;

        defaultDeposit = 10_000e6;
        defaultBorrow = 90_000e6;

        // Set deUSD oracle to USD
        vm.prank(owner);
        TRADING_MODULE.setPriceOracle(
            address(0x15700B564Ca08D9439C58cA5053166E8317aa138),
            AggregatorV2V3Interface(address(0x471a6299C027Bd81ed4D66069dc510Bd0569f4F8))
        );
    }
}

contract Test_LP_Curve_lvlUSD_USDC is TestSingleSidedLPStrategy {
    function setMarketVariables() internal override {
        lpToken = ERC20(0x1220868672D5B10F3E1cB9Ab519E4d0B08545ea4);
        curveGauge = 0x60483b4792A17c980A275449caF848084231543C;
        w = ERC20(curveGauge);
        asset = ERC20(address(USDC));
        curveInterface = CurveInterface.StableSwapNG;
        primaryIndex = 0;
        maxPoolShare = 100e18;
        dyAmount = 1e6;

        defaultDeposit = 10_000e6;
        defaultBorrow = 90_000e6;

        maxExitValuationSlippage = 0.002e18;

        // TODO: Set lvlUSD oracle to USD, this is a hardcoded 1-1 value
        MockOracle lvlUSDOracle = new MockOracle(1e18);
        vm.prank(owner);
        TRADING_MODULE.setPriceOracle(
            address(0x7C1156E515aA1A2E851674120074968C905aAF37),
            AggregatorV2V3Interface(address(lvlUSDOracle))
        );
    }
}

contract Test_LP_Curve_USDC_crvUSD is TestSingleSidedLPStrategy {
    function setMarketVariables() internal override {
        lpToken = ERC20(0x4DEcE678ceceb27446b35C672dC7d61F30bAD69E);
        rewardPool = 0x44D8FaB7CD8b7877D5F79974c2F501aF6E65AbBA;
        asset = USDC;
        w = ERC20(rewardPool);
        curveInterface = CurveInterface.V1;
        primaryIndex = 0;
        maxPoolShare = 100e18;
        dyAmount = 1e6;

        defaultDeposit = 10_000e6;
        defaultBorrow = 90_000e6;
    }
}

contract Test_LP_Curve_USDT_crvUSD is TestSingleSidedLPStrategy {
    function getDepositData(address /* user */, uint256 depositAmount) internal pure override returns (bytes memory) {
        TradeParams[] memory depositTrades = new TradeParams[](2);
        depositTrades[0] = TradeParams({
            tradeType: TradeType.EXACT_IN_SINGLE,
            dexId: uint8(DexId.CURVE_V2),
            tradeAmount: depositAmount,
            minPurchaseAmount: 0,
            exchangeData: abi.encode(CurveV2SingleData({
                // USDC/USDT pool
                pool: 0x4f493B7dE8aAC7d55F71853688b1F7C8F0243C85,
                fromIndex: 0,
                toIndex: 1
            }))
        });

        // Don't buy any crvUSD
        depositTrades[1] = TradeParams({
            tradeType: TradeType.EXACT_IN_SINGLE,
            dexId: uint8(DexId.CURVE_V2),
            tradeAmount: 0,
            minPurchaseAmount: 0,
            exchangeData: bytes("")
        });

        return abi.encode(DepositParams({
            minPoolClaim: 0,
            depositTrades: depositTrades
        }));
    }

    function getRedeemData(address /* user */, uint256 /* redeemAmount */) internal pure override returns (bytes memory) {
        TradeParams[] memory redeemTrades = new TradeParams[](2);
        // Sell USDT for USDC
        redeemTrades[0] = TradeParams({
            tradeType: TradeType.EXACT_IN_SINGLE,
            dexId: uint8(DexId.CURVE_V2),
            tradeAmount: 0,
            minPurchaseAmount: 0,
            exchangeData: abi.encode(CurveV2SingleData({
                // USDC/USDT pool
                pool: 0x4f493B7dE8aAC7d55F71853688b1F7C8F0243C85,
                fromIndex: 1,
                toIndex: 0
            }))
        });
        // Sell crvUSD for USDC
        redeemTrades[1] = TradeParams({
            tradeType: TradeType.EXACT_IN_SINGLE,
            dexId: uint8(DexId.CURVE_V2),
            tradeAmount: 0,
            minPurchaseAmount: 0,
            exchangeData: abi.encode(CurveV2SingleData({
                // USDC/crvUSD pool
                pool: 0x4DEcE678ceceb27446b35C672dC7d61F30bAD69E,
                fromIndex: 1,
                toIndex: 0
            }))
        });

        return abi.encode(RedeemParams({
            minAmounts: new uint256[](2),
            redemptionTrades: redeemTrades
        }));
    }

    function setMarketVariables() internal override {
        lpToken = ERC20(0x390f3595bCa2Df7d23783dFd126427CCeb997BF4);
        rewardPool = 0xD1DdB0a0815fD28932fBb194C84003683AF8a824;
        asset = USDC;
        w = ERC20(rewardPool);
        curveInterface = CurveInterface.V1;
        primaryIndex = 0;
        maxPoolShare = 100e18;
        dyAmount = 1e6;

        defaultDeposit = 10_000e6;
        defaultBorrow = 90_000e6;
    }

    function postDeploySetup() internal override {
        super.postDeploySetup();

        vm.startPrank(owner);
        // Allow selling USDC
        TRADING_MODULE.setTokenPermissions(
            address(y),
            address(asset),
            ITradingModule.TokenPermissions(
            { allowSell: true, dexFlags: uint32(1 << uint8(DexId.CURVE_V2)), tradeTypeFlags: 5 }
        ));
        // Allow selling USDT
        TRADING_MODULE.setTokenPermissions(
            address(y),
            address(0xdAC17F958D2ee523a2206206994597C13D831ec7),
            ITradingModule.TokenPermissions(
            { allowSell: true, dexFlags: uint32(1 << uint8(DexId.CURVE_V2)), tradeTypeFlags: 5 }
        ));
        // Allow selling crvUSD
        TRADING_MODULE.setTokenPermissions(
            address(y),
            address(0xf939E0A03FB07F59A73314E73794Be0E57ac1b4E),
            ITradingModule.TokenPermissions(
            { allowSell: true, dexFlags: uint32(1 << uint8(DexId.CURVE_V2)), tradeTypeFlags: 5 }
        ));
        vm.stopPrank();
    }
}

contract Test_LP_Curve_GHO_crvUSD is TestSingleSidedLPStrategy {
    function getDepositData(address /* user */, uint256 depositAmount) internal pure override returns (bytes memory) {
        TradeParams[] memory depositTrades = new TradeParams[](2);
        // Sell USDC for GHO
        depositTrades[0] = TradeParams({
            tradeType: TradeType.EXACT_IN_SINGLE,
            dexId: uint8(DexId.UNISWAP_V3),
            tradeAmount: depositAmount,
            minPurchaseAmount: 0,
            exchangeData: abi.encode(UniV3SingleData({
                fee: 500
            }))
        });

        // Don't buy any crvUSD
        depositTrades[1] = TradeParams({
            tradeType: TradeType.EXACT_IN_SINGLE,
            dexId: uint8(DexId.UNISWAP_V3),
            tradeAmount: 0,
            minPurchaseAmount: 0,
            exchangeData: bytes("")
        });

        return abi.encode(DepositParams({
            minPoolClaim: 0,
            depositTrades: depositTrades
        }));
    }

    function getRedeemData(address /* user */, uint256 /* redeemAmount */) internal pure override returns (bytes memory) {
        TradeParams[] memory redeemTrades = new TradeParams[](2);
        // Sell GHO for USDC
        redeemTrades[0] = TradeParams({
            tradeType: TradeType.EXACT_IN_SINGLE,
            dexId: uint8(DexId.UNISWAP_V3),
            tradeAmount: 0,
            minPurchaseAmount: 0,
            exchangeData: abi.encode(UniV3SingleData({
                fee: 500
            }))
        });

        // Sell crvUSD for USDC
        redeemTrades[1] = TradeParams({
            tradeType: TradeType.EXACT_IN_SINGLE,
            dexId: uint8(DexId.CURVE_V2),
            tradeAmount: 0,
            minPurchaseAmount: 0,
            exchangeData: abi.encode(CurveV2SingleData({
                // USDC/crvUSD pool
                pool: 0x4DEcE678ceceb27446b35C672dC7d61F30bAD69E,
                fromIndex: 1,
                toIndex: 0
            }))
        });

        return abi.encode(RedeemParams({
            minAmounts: new uint256[](2),
            redemptionTrades: redeemTrades
        }));
    }

    function setMarketVariables() internal override {
        lpToken = ERC20(0x635EF0056A597D13863B73825CcA297236578595);
        rewardPool = 0x5eC758f79b96AE74e7F1Ba9583009aFB3fc8eACB;
        asset = USDC;
        w = ERC20(rewardPool);
        curveInterface = CurveInterface.StableSwapNG;
        primaryIndex = 0;
        maxPoolShare = 100e18;
        dyAmount = 1e6;

        maxExitValuationSlippage = 0.0075e18;

        defaultDeposit = 10_000e6;
        defaultBorrow = 90_000e6;
    }

    function postDeploySetup() internal override {
        super.postDeploySetup();

        vm.startPrank(owner);
        // Allow selling USDC
        TRADING_MODULE.setTokenPermissions(
            address(y),
            address(asset),
            ITradingModule.TokenPermissions(
            { allowSell: true, dexFlags: uint32(1 << uint8(DexId.UNISWAP_V3)), tradeTypeFlags: 5 }
        ));
        // Allow selling GHO
        TRADING_MODULE.setTokenPermissions(
            address(y),
            address(0x40D16FC0246aD3160Ccc09B8D0D3A2cD28aE6C2f),
            ITradingModule.TokenPermissions(
            { allowSell: true, dexFlags: uint32(1 << uint8(DexId.UNISWAP_V3)), tradeTypeFlags: 5 }
        ));
        // Allow selling crvUSD
        TRADING_MODULE.setTokenPermissions(
            address(y),
            address(0xf939E0A03FB07F59A73314E73794Be0E57ac1b4E),
            ITradingModule.TokenPermissions(
            { allowSell: true, dexFlags: uint32(1 << uint8(DexId.CURVE_V2)), tradeTypeFlags: 5 }
        ));
        vm.stopPrank();
    }
}