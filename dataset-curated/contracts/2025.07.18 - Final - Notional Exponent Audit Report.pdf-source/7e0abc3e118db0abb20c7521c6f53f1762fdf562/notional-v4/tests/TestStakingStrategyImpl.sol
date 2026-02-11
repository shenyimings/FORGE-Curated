// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.29;

import "forge-std/src/Test.sol";
import "./TestWithdrawRequestImpl.sol";
import "../src/staking/AbstractStakingStrategy.sol";
import "../src/staking/StakingStrategy.sol";
import "../src/withdraws/EtherFi.sol";
import "../src/withdraws/Dinero.sol";
import "../src/interfaces/ITradingModule.sol";
import "./TestStakingStrategy.sol";
import "./Mocks.sol";

contract TestMockStakingStrategy_EtherFi is TestStakingStrategy {
    function getRedeemData(
        address /* user */,
        uint256 /* shares */
    ) internal pure override returns (bytes memory redeemData) {
        return abi.encode(RedeemParams({
            minPurchaseAmount: 0,
            dexId: uint8(DexId.CURVE_V2),
            exchangeData: abi.encode(CurveV2SingleData({
                pool: 0xDB74dfDD3BB46bE8Ce6C33dC9D82777BCFc3dEd5,
                fromIndex: 1,
                toIndex: 0
            }))
        }));
    }

    function deployYieldStrategy() internal override {
        setupWithdrawRequestManager(address(new EtherFiWithdrawRequestManager()));
        y = new MockStakingStrategy(address(WETH), address(weETH), 0.0010e18);

        w = ERC20(y.yieldToken());
        (AggregatorV2V3Interface oracle, ) = TRADING_MODULE.priceOracles(address(w));
        o = new MockOracle(oracle.latestAnswer());

        defaultDeposit = 10e18;
        defaultBorrow = 90e18;
        maxEntryValuationSlippage = 0.0050e18;
        maxExitValuationSlippage = 0.0050e18;

        withdrawRequest = new TestEtherFiWithdrawRequest();
        canInspectTransientVariables = true;
    }

    function postDeploySetup() internal override {
        vm.startPrank(owner);
        TRADING_MODULE.setTokenPermissions(
            address(y),
            address(weETH),
            ITradingModule.TokenPermissions(
            { allowSell: true, dexFlags: uint32(1 << uint8(DexId.CURVE_V2)), tradeTypeFlags: 5 }
        ));
        vm.stopPrank();
    }
}

contract TestStakingStrategy_EtherFi is TestStakingStrategy {
    function getRedeemData(
        address /* user */,
        uint256 /* shares */
    ) internal pure override returns (bytes memory redeemData) {
        return abi.encode(RedeemParams({
            minPurchaseAmount: 0,
            dexId: uint8(DexId.CURVE_V2),
            exchangeData: abi.encode(CurveV2SingleData({
                pool: 0xDB74dfDD3BB46bE8Ce6C33dC9D82777BCFc3dEd5,
                fromIndex: 1,
                toIndex: 0
            }))
        }));
    }

    function deployYieldStrategy() internal override {
        setupWithdrawRequestManager(address(new EtherFiWithdrawRequestManager()));
        y = new StakingStrategy(address(WETH), address(weETH), 0.0010e18);

        w = ERC20(y.yieldToken());
        (AggregatorV2V3Interface oracle, ) = TRADING_MODULE.priceOracles(address(w));
        o = new MockOracle(oracle.latestAnswer());

        defaultDeposit = 10e18;
        defaultBorrow = 90e18;
        maxEntryValuationSlippage = 0.0050e18;
        maxExitValuationSlippage = 0.0050e18;

        withdrawRequest = new TestEtherFiWithdrawRequest();
    }

    function postDeploySetup() internal override {
        vm.startPrank(owner);
        TRADING_MODULE.setTokenPermissions(
            address(y),
            address(weETH),
            ITradingModule.TokenPermissions(
            { allowSell: true, dexFlags: uint32(1 << uint8(DexId.CURVE_V2)), tradeTypeFlags: 5 }
        ));
        vm.stopPrank();
    }
}

// contract TestStakingStrategy_apxETH is TestStakingStrategy {
//     function getRedeemData(
//         address /* user */,
//         uint256 /* shares */
//     ) internal override returns (bytes memory redeemData) {
//         vm.skip(true);
//         // No way to trade out of this position
//         return bytes("");
//     }

//     function deployYieldStrategy() internal override {
//         setupWithdrawRequestManager(address(new DineroWithdrawRequestManager(address(apxETH))));
//         y = new StakingStrategy(address(WETH), address(apxETH), 0.0010e18);
//         w = ERC20(y.yieldToken());
//         (AggregatorV2V3Interface oracle, ) = TRADING_MODULE.priceOracles(address(w));
//         o = new MockOracle(oracle.latestAnswer());

//         defaultDeposit = 10e18;
//         defaultBorrow = 90e18;
//         maxEntryValuationSlippage = 0.0050e18;
//         maxExitValuationSlippage = 0.0050e18;

//         withdrawRequest = new TestDinero_apxETH_WithdrawRequest();

//         // TODO: need apxETH oracle price this is to ETH, so combine with the
//         // ETH/USD price
//         // 0x19219BC90F48DeE4d5cF202E09c438FAacFd8Bea
//     }
// }
