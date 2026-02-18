// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.29;

import "forge-std/src/Test.sol";
import "./TestMorphoYieldStrategy.sol";
import "../src/rewards/ConvexRewardManager.sol";
import "../src/interfaces/IRewardManager.sol";
import "../src/single-sided-lp/CurveConvex2Token.sol";
import "../src/single-sided-lp/AbstractSingleSidedLP.sol";
import "../src/oracles/Curve2TokenOracle.sol";
import "./TestWithdrawRequest.sol";
import "../src/interfaces/ITradingModule.sol";

abstract contract TestSingleSidedLPStrategy is TestMorphoYieldStrategy {
    ERC20 lpToken;
    address rewardPool;
    IRewardManager rm;
    CurveInterface curveInterface;
    uint8 primaryIndex;
    uint256 maxPoolShare;
    AggregatorV2V3Interface baseToUSDOracle;
    bool invertBase;
    uint256 dyAmount;
    address curveGauge;
    uint8 stakeTokenIndex;
    // Used to set the price oracle to USD for the primary token
    address usdOracleToken;
    IWithdrawRequestManager[] managers;

    DepositParams depositParams;
    RedeemParams redeemParams;
    WithdrawParams withdrawParams;

    TradeParams[] tradeBeforeDepositParams;
    TradeParams[] tradeBeforeRedeemParams;

    TestWithdrawRequest[] withdrawRequests;

    function getDepositData(
        address /* user */,
        uint256 /* depositAmount */
    ) internal virtual override returns (bytes memory depositData) {
        return abi.encode(depositParams);
    }

    function getRedeemData(
        address /* user */,
        uint256 /* shares */
    ) internal virtual override returns (bytes memory redeemData) {
        RedeemParams memory r = redeemParams;
        if (r.minAmounts.length == 0) {
            r.minAmounts = new uint256[](2);
        }

        return abi.encode(r);
    }

    function getWithdrawRequestData(
        address /* user */,
        uint256 /* shares */
    ) internal view override virtual returns (bytes memory withdrawRequestData) {
        WithdrawParams memory w;
        w.minAmounts = new uint256[](2);
        w.withdrawData = new bytes[](2);
        return abi.encode(w);
    }

    function finalizeWithdrawRequest(address user) internal override {
        for (uint256 i; i < managers.length; i++) {
            if (address(managers[i]) == address(0)) continue;
            (WithdrawRequest memory w, /* */) = managers[i].getWithdrawRequest(address(y), user);
            if (address(withdrawRequests[i]) == address(0)) continue;
            withdrawRequests[i].finalizeWithdrawRequest(w.requestId);
        }
    }

    function setMarketVariables() internal virtual;

    function deployYieldStrategy() internal override {
        ConvexRewardManager rmImpl = new ConvexRewardManager();
        invertBase = false;
        // Set default parameters
        managers.push(IWithdrawRequestManager(address(0)));
        managers.push(IWithdrawRequestManager(address(0)));
        withdrawRequests.push(TestWithdrawRequest(address(0)));
        withdrawRequests.push(TestWithdrawRequest(address(0)));
        tradeBeforeDepositParams.push(TradeParams({
            tradeType: TradeType.STAKE_TOKEN,
            dexId: 0,
            tradeAmount: 0,
            minPurchaseAmount: 0,
            exchangeData: bytes("")
        }));
        tradeBeforeDepositParams.push(TradeParams({
            tradeType: TradeType.STAKE_TOKEN,
            dexId: 0,
            tradeAmount: 0,
            minPurchaseAmount: 0,
            exchangeData: bytes("")
        }));
        tradeBeforeRedeemParams.push(TradeParams({
            tradeType: TradeType.STAKE_TOKEN,
            dexId: 0,
            tradeAmount: 0,
            minPurchaseAmount: 0,
            exchangeData: bytes("")
        }));
        tradeBeforeRedeemParams.push(TradeParams({
            tradeType: TradeType.STAKE_TOKEN,
            dexId: 0,
            tradeAmount: 0,
            minPurchaseAmount: 0,
            exchangeData: bytes("")
        }));

        setMarketVariables();
        if (usdOracleToken == address(0)) usdOracleToken = address(asset);
        if (address(w) == address(0)) w = ERC20(rewardPool);

        for (uint256 i = 0; i < managers.length; i++) {
            if (address(managers[i]) == address(0)) continue;
            vm.startPrank(owner);
            // Create a proxy to the manager
            managers[i] = IWithdrawRequestManager(address(
                new TimelockUpgradeableProxy(address(managers[i]),
                abi.encodeWithSelector(Initializable.initialize.selector, bytes(""))))
            );
            ADDRESS_REGISTRY.setWithdrawRequestManager(address(managers[i]));
            vm.stopPrank();
        }

        y = new CurveConvex2Token(
            maxPoolShare,
            address(asset),
            address(w),
            0.0010e18, // 0.1%
            address(rmImpl),
            DeploymentParams({
                pool: address(lpToken),
                poolToken: address(lpToken),
                gauge: curveGauge,
                convexRewardPool: address(rewardPool),
                curveInterface: curveInterface
            }),
            managers[0]
        );

        feeToken = lpToken;
        (baseToUSDOracle, /* */) = TRADING_MODULE.priceOracles(usdOracleToken);
        Curve2TokenOracle oracle = new Curve2TokenOracle(
            0.95e18,
            1.05e18,
            address(lpToken),
            primaryIndex,
            "Curve 2 Token Oracle",
            address(0),
            baseToUSDOracle,
            invertBase,
            dyAmount
        );

        o = new MockOracle(oracle.latestAnswer());
    }

    function postDeploySetup() internal override virtual {
        rm = IRewardManager(address(y));
        if (address(rewardPool) != address(0)) {
            vm.startPrank(owner);
            rm.migrateRewardPool(address(lpToken), RewardPoolStorage({
                rewardPool: rewardPool,
                forceClaimAfter: 0,
                lastClaimTimestamp: 0
            }));
            // List CRV reward token
            rm.updateRewardToken(0, address(0xD533a949740bb3306d119CC777fa900bA034cd52), 0, 0);
            vm.stopPrank();
        }

        for (uint256 i = 0; i < managers.length; i++) {
            if (address(managers[i]) == address(0)) continue;
            vm.startPrank(owner);
            managers[i].setApprovedVault(address(y), true);
            vm.stopPrank();
        }
    }

    function test_claimRewards() public {
        // TODO: test claims on the curve gauge directly
        vm.skip(rewardPool == address(0));
        _enterPosition(msg.sender, defaultDeposit, defaultBorrow);

        vm.warp(block.timestamp + 1 days);

        vm.prank(msg.sender);
        lendingRouter.claimRewards(address(y));
        (VaultRewardState[] memory rewardStates, /* */) = rm.getRewardSettings();
        uint256[] memory rewardsBefore = new uint256[](rewardStates.length);
        for (uint256 i = 0; i < rewardStates.length; i++) {
            rewardsBefore[i] = ERC20(rewardStates[i].rewardToken).balanceOf(msg.sender);
            assertGt(rewardsBefore[i], 0);
        }

        vm.prank(msg.sender);
        lendingRouter.claimRewards(address(y));
        for (uint256 i = 0; i < rewardStates.length; i++) {
            assertEq(ERC20(rewardStates[i].rewardToken).balanceOf(msg.sender), rewardsBefore[i]);
        }
    }

    function test_enterPosition_stakeBeforeDeposit() public {
        vm.skip(address(managers[stakeTokenIndex]) == address(0));

        depositParams.depositTrades.push(TradeParams({
            tradeType: TradeType.STAKE_TOKEN,
            dexId: 0,
            tradeAmount: 0,
            minPurchaseAmount: 0,
            exchangeData: bytes("")
        }));
        depositParams.depositTrades.push(TradeParams({
            tradeType: TradeType.STAKE_TOKEN,
            dexId: 0,
            tradeAmount: 0,
            minPurchaseAmount: 0,
            exchangeData: bytes("")
        }));

        depositParams.depositTrades[stakeTokenIndex] = TradeParams({
            tradeType: TradeType.STAKE_TOKEN,
            dexId: 0,
            tradeAmount: (defaultDeposit + defaultBorrow) / 2,
            minPurchaseAmount: 0,
            exchangeData: abi.encode(address(managers[stakeTokenIndex]), bytes(""))
        });


        vm.startPrank(msg.sender);
        if (!MORPHO.isAuthorized(msg.sender, address(lendingRouter))) MORPHO.setAuthorization(address(lendingRouter), true);
        asset.approve(address(lendingRouter), defaultDeposit);

        // Ensures that the stake tokens function is called
        vm.expectCall(
            address(managers[stakeTokenIndex]),
            abi.encodeWithSelector(IWithdrawRequestManager.stakeTokens.selector),
            1
        );
        lendingRouter.enterPosition(msg.sender, address(y), defaultDeposit, defaultBorrow, getDepositData(msg.sender, defaultDeposit + defaultBorrow));
        postEntryAssertions(msg.sender, lendingRouter);
        vm.stopPrank();

        delete depositParams;
    }

    function test_enterPosition_tradeBeforeDeposit() public {
        vm.skip(tradeBeforeDepositParams[stakeTokenIndex].dexId == 0);

        depositParams.depositTrades = tradeBeforeDepositParams;
        depositParams.depositTrades[stakeTokenIndex].tradeAmount = (defaultDeposit + defaultBorrow) / 2;

        vm.startPrank(msg.sender);
        if (!MORPHO.isAuthorized(msg.sender, address(lendingRouter))) MORPHO.setAuthorization(address(lendingRouter), true);
        asset.approve(address(lendingRouter), defaultDeposit);

        // Ensures that the trading was done
        vm.expectEmit(true, false, false, false, address(y));
        emit ITradingModule.TradeExecuted(
            address(asset), address(0), (defaultDeposit + defaultBorrow) / 2, 0
        );
        lendingRouter.enterPosition(msg.sender, address(y), defaultDeposit, defaultBorrow, getDepositData(msg.sender, defaultDeposit + defaultBorrow));
        postEntryAssertions(msg.sender, lendingRouter);
        vm.stopPrank();

        delete depositParams;
    }

    function test_enterPosition_RevertsIf_ExistingWithdrawRequest() public {
        vm.skip(address(managers[stakeTokenIndex]) == address(0));

        _enterPosition(msg.sender, defaultDeposit, defaultBorrow);
        uint256 balanceBefore = lendingRouter.balanceOfCollateral(msg.sender, address(y));

        vm.startPrank(msg.sender);
        lendingRouter.initiateWithdraw(msg.sender, address(y), getWithdrawRequestData(msg.sender, balanceBefore));

        asset.approve(address(lendingRouter), defaultDeposit);

        vm.expectRevert(abi.encodeWithSelector(CannotEnterPosition.selector));
        lendingRouter.enterPosition(msg.sender, address(y), defaultDeposit, defaultBorrow, getDepositData(msg.sender, defaultDeposit));
        vm.stopPrank();
    }

    function test_exitPosition_tradeBeforeRedeem(bool isFullExit) public {
        vm.skip(tradeBeforeRedeemParams[stakeTokenIndex].dexId == 0);
        if (isFullExit) {
            _enterPosition(msg.sender, defaultDeposit, defaultBorrow);
        } else {
            _enterPosition(msg.sender, defaultDeposit * 4, defaultBorrow);
        }
        uint256 initialBalance = lendingRouter.balanceOfCollateral(msg.sender, address(y));

        vm.warp(block.timestamp + 6 minutes);

        redeemParams.minAmounts = new uint256[](2);
        redeemParams.redemptionTrades = tradeBeforeRedeemParams;

        uint256 netWorthBefore = y.convertToAssets(initialBalance) - defaultBorrow;
        vm.startPrank(msg.sender);
        uint256 sharesToExit = isFullExit ? initialBalance : initialBalance / 10;
        uint256 assetsToRepay = isFullExit ? type(uint256).max : defaultBorrow / 10;

        // Ensures that the trading was done
        uint256 assetsBefore = asset.balanceOf(msg.sender);
        vm.expectEmit(false, true, false, false, address(y));
        emit ITradingModule.TradeExecuted(
            address(0), address(asset), 0, 0
        );
        lendingRouter.exitPosition(
            msg.sender, address(y), msg.sender, sharesToExit, assetsToRepay, getRedeemData(msg.sender, sharesToExit)
        );
        uint256 assetsAfter = asset.balanceOf(msg.sender);
        uint256 profitsWithdrawn = assetsAfter - assetsBefore;
        uint256 collateralAfter = lendingRouter.balanceOfCollateral(msg.sender, address(y));
        uint256 netWorthAfter = isFullExit ? 0 : y.convertToAssets(collateralAfter) - (defaultBorrow - assetsToRepay);
        vm.stopPrank();

        postExitAssertions(initialBalance, netWorthBefore, sharesToExit, profitsWithdrawn, netWorthAfter);

        delete redeemParams;
    }

    function test_exitPosition_withdrawBeforeRedeem() public {
        vm.skip(address(managers[stakeTokenIndex]) == address(0));
        _enterPosition(msg.sender, defaultDeposit, defaultBorrow);

        withdrawParams.minAmounts = new uint256[](2);
        withdrawParams.withdrawData = new bytes[](2);

        vm.startPrank(msg.sender);
        lendingRouter.initiateWithdraw(msg.sender, address(y), abi.encode(withdrawParams));

        vm.warp(block.timestamp + 6 minutes);
        uint256 shares = lendingRouter.balanceOfCollateral(msg.sender, address(y));

        redeemParams.minAmounts = new uint256[](2);
        redeemParams.redemptionTrades = tradeBeforeRedeemParams;
        bytes memory redeemData = abi.encode(redeemParams);

        // The call reverts properly inside the library but we don't propagate the revert
        // so we need to expect a revert here
        vm.expectPartialRevert(WithdrawRequestNotFinalized.selector);
        lendingRouter.exitPosition(
            msg.sender,
            address(y),
            msg.sender,
            shares,
            type(uint256).max,
            redeemData
        );
        vm.stopPrank();

        finalizeWithdrawRequest(msg.sender);

        vm.startPrank(msg.sender);
        lendingRouter.exitPosition(
            msg.sender,
            address(y),
            msg.sender,
            shares,
            type(uint256).max,
            redeemData
        );
        vm.stopPrank();

        delete redeemParams;
    }

    function test_cannotEnterAboveMaxPoolShare() public {
        address newImpl = address(new CurveConvex2Token(
            0.001e18, // 0.1% max pool share
            address(asset),
            address(w),
            0.0010e18, // 0.1%
            address(new ConvexRewardManager()),
            DeploymentParams({
                pool: address(lpToken),
                poolToken: address(lpToken),
                gauge: curveGauge,
                convexRewardPool: address(rewardPool),
                curveInterface: curveInterface
            }),
            managers[0]
        ));

        vm.startPrank(owner);
        TimelockUpgradeableProxy(payable(address(y))).initiateUpgrade(address(newImpl));
        vm.warp(block.timestamp + 7 days);
        TimelockUpgradeableProxy(payable(address(y))).executeUpgrade(bytes(""));
        vm.stopPrank();

        vm.startPrank(msg.sender);
        if (!MORPHO.isAuthorized(msg.sender, address(y))) MORPHO.setAuthorization(address(y), true);
        asset.approve(address(lendingRouter), defaultDeposit);
        bytes memory depositData = getDepositData(msg.sender, defaultDeposit + defaultBorrow);
        vm.expectPartialRevert(PoolShareTooHigh.selector);
        lendingRouter.enterPosition(msg.sender, address(y), defaultDeposit, defaultBorrow, depositData);
        vm.stopPrank();
    }

    function test_withdrawRequestValuation() public {
        vm.skip(address(managers[stakeTokenIndex]) == address(0));
        
        address staker = makeAddr("staker");
        vm.prank(owner);
        asset.transfer(staker, defaultDeposit);

        _enterPosition(msg.sender, defaultDeposit, defaultBorrow);
        // The staker exists to generate fees on the position to test the withdraw valuation
        _enterPosition(staker, defaultDeposit, defaultBorrow);

        (/* */, uint256 collateralValueBefore, /* */) = lendingRouter.healthFactor(msg.sender, address(y));
        (/* */, uint256 collateralValueBeforeStaker, /* */) = lendingRouter.healthFactor(staker, address(y));
        assertApproxEqRel(collateralValueBefore, collateralValueBeforeStaker, 0.0005e18, "Staker should have same collateral value as msg.sender");

        vm.startPrank(msg.sender);
        lendingRouter.initiateWithdraw(msg.sender, address(y), getWithdrawRequestData(msg.sender, lendingRouter.balanceOfCollateral(msg.sender, address(y))));
        vm.stopPrank();
        (/* */, uint256 collateralValueAfter, /* */) = lendingRouter.healthFactor(msg.sender, address(y));
        assertApproxEqRel(collateralValueBefore, collateralValueAfter, 0.0001e18, "Withdrawal should not change collateral value");

        vm.warp(block.timestamp + 10 days);
        (/* */, uint256 collateralValueAfterWarp, /* */) = lendingRouter.healthFactor(msg.sender, address(y));
        (/* */, uint256 collateralValueAfterWarpStaker, /* */) = lendingRouter.healthFactor(staker, address(y));

        // Collateral value for the withdrawer should not change over time
        assertEq(collateralValueAfter, collateralValueAfterWarp, "Withdrawal should not change collateral value over time");

        // For the staker, the collateral value should have decreased due to fees
        assertGt(collateralValueBeforeStaker, collateralValueAfterWarpStaker, "Staker should have lost value due to fees");

        // Check price after finalize
        finalizeWithdrawRequest(msg.sender);
        for (uint256 i = 0; i < managers.length; i++) {
            if (address(managers[i]) == address(0)) continue;
            managers[i].finalizeRequestManual(address(y), msg.sender);
        }
        (/* */, uint256 collateralValueAfterFinalize, /* */) = lendingRouter.healthFactor(msg.sender, address(y));

        assertApproxEqRel(collateralValueAfterFinalize, collateralValueAfterWarp, 0.01e18, "Withdrawal should be similar to collateral value after finalize");
        assertGt(collateralValueAfterFinalize, collateralValueAfterWarp, "Withdrawal value should increase after finalize");
    }

    function test_liquidate_tokenizesWithdrawRequest() public {
        vm.skip(address(managers[stakeTokenIndex]) == address(0));
        _enterPosition(msg.sender, defaultDeposit, defaultBorrow);

        vm.startPrank(msg.sender);
        lendingRouter.initiateWithdraw(msg.sender, address(y), getWithdrawRequestData(msg.sender, lendingRouter.balanceOfCollateral(msg.sender, address(y))));
        vm.stopPrank();

        // Drop the price of the two listed tokens since the LP token valuation is
        // no longer relevant
        for (uint256 i = 0; i < managers.length; i++) {
            if (address(managers[i]) == address(0)) continue;
            address yieldToken = managers[i].YIELD_TOKEN();
            // Don't drop the price of the asset token since it will offset the
            // price drop of the yield token
            if (yieldToken == address(asset)) continue;
            (AggregatorV2V3Interface oracle, /* */) = TRADING_MODULE.priceOracles(yieldToken);
            MockOracle o = new MockOracle(oracle.latestAnswer());

            int256 oraclePrecision = int256(10 ** oracle.decimals());
            o.setPrice(o.latestAnswer() * 0.85e18 / oraclePrecision);

            vm.prank(owner);
            TRADING_MODULE.setPriceOracle(yieldToken, AggregatorV2V3Interface(address(o)));
        }

        vm.warp(block.timestamp + 6 minutes);

        vm.startPrank(owner);
        uint256 balanceBefore = lendingRouter.balanceOfCollateral(msg.sender, address(y));
        asset.approve(address(lendingRouter), type(uint256).max);
        uint256 assetBefore = asset.balanceOf(owner);
        uint256 sharesToLiquidator = lendingRouter.liquidate(msg.sender, address(y), balanceBefore, 0);
        uint256 assetAfter = asset.balanceOf(owner);
        uint256 netAsset = assetBefore - assetAfter;

        assertEq(lendingRouter.balanceOfCollateral(msg.sender, address(y)), balanceBefore - sharesToLiquidator);
        assertEq(y.balanceOf(owner), sharesToLiquidator);
        vm.stopPrank();

        finalizeWithdrawRequest(owner);

        // The owner does receive a tokenized withdraw request
        for (uint256 i = 0; i < managers.length; i++) {
            if (address(managers[i]) == address(0)) continue;
            (WithdrawRequest memory w, TokenizedWithdrawRequest memory s) = managers[i].getWithdrawRequest(address(y), owner);
            assertNotEq(w.requestId, 0);
            assertEq(w.sharesAmount, sharesToLiquidator);
            assertGt(w.yieldTokenAmount, 0);

            // We have not finalized the tokenized withdraw request yet
            assertEq(s.totalYieldTokenAmount, w.yieldTokenAmount);
            assertEq(s.finalized, false);
            assertEq(s.totalWithdraw, 0);
        }

        vm.startPrank(owner);
        uint256 assets = y.redeemNative(sharesToLiquidator, getRedeemData(owner, sharesToLiquidator));
        assertGt(assets, netAsset);
        vm.stopPrank();

        // The owner does receive a tokenized withdraw request
        for (uint256 i = 0; i < managers.length; i++) {
            if (address(managers[i]) == address(0)) continue;
            // Assert that the withdraw request is cleared
            (WithdrawRequest memory w, TokenizedWithdrawRequest memory s) = managers[i].getWithdrawRequest(address(y), owner);
            assertEq(w.sharesAmount, 0);
            assertEq(w.yieldTokenAmount, 0);

            // The original withdraw request is still active on the liquidated account
            if (balanceBefore > sharesToLiquidator) {
                (w, s) = managers[i].getWithdrawRequest(address(y), msg.sender);
                assertNotEq(w.requestId, 0);
                assertEq(w.sharesAmount, balanceBefore - sharesToLiquidator);
                assertGt(w.yieldTokenAmount, 0);

                assertGt(s.totalYieldTokenAmount, 0);
                assertGt(s.totalWithdraw, 0);
                assertEq(s.finalized, true);
            }
        }
    }

    function test_enterPosition_after_Exit_WithdrawRequest() public {
        vm.skip(address(managers[stakeTokenIndex]) == address(0));

        _enterPosition(msg.sender, defaultDeposit, defaultBorrow);
        uint256 balanceBefore = lendingRouter.balanceOfCollateral(msg.sender, address(y));

        vm.startPrank(msg.sender);
        lendingRouter.initiateWithdraw(msg.sender, address(y), getWithdrawRequestData(msg.sender, balanceBefore));
        vm.stopPrank();

        finalizeWithdrawRequest(msg.sender);

        vm.warp(block.timestamp + 6 minutes);

        vm.startPrank(msg.sender);
        lendingRouter.exitPosition(
            msg.sender,
            address(y),
            msg.sender,
            balanceBefore,
            type(uint256).max,
            getRedeemData(msg.sender, balanceBefore)
        );
        vm.stopPrank();
        assertEq(lendingRouter.balanceOfCollateral(msg.sender, address(y)), 0);

        // Assert that we can re-enter the position after previously exiting a withdraw request
        _enterPosition(msg.sender, defaultDeposit, defaultBorrow);
    }

    // TODO: test re-entrancy context
}