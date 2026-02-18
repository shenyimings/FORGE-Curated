// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.29;

import "./TestEnvironment.sol";
import "../src/routers/MorphoLendingRouter.sol";

abstract contract TestDilutionAttack is TestEnvironment {

    function setAsset() internal virtual;

    function deployYieldStrategy() internal override {
        setAsset();
        w = new MockWrapperERC20(ERC20(asset));
        if (asset == USDC) {
            o = new MockOracle(1e18);
        } else {
            (AggregatorV2V3Interface ethOracle, /* */) = TRADING_MODULE.priceOracles(ETH_ADDRESS);
            o = new MockOracle(ethOracle.latestAnswer() * 1e18 / 1e8);
        }

        y = new MockYieldStrategy(
            address(asset),
            address(w),
            0.0010e18 // 0.1% fee rate
        );
        defaultDeposit = asset == USDC ? 10_000e6 : 10e18;
        defaultBorrow = asset == USDC ? 90_000e6 : 90e18;
    }

    function setupLendingRouter(uint256 lltv) internal override returns (ILendingRouter l) {
        l = new MorphoLendingRouter();

        vm.startPrank(owner);
        ADDRESS_REGISTRY.setLendingRouter(address(l));
        MorphoLendingRouter(address(l)).initializeMarket(address(y), IRM, lltv);

        asset.approve(address(MORPHO), type(uint256).max);
        MORPHO.supply(
            MorphoLendingRouter(address(l)).marketParams(address(y)),
            1_000_000 * 10 ** asset.decimals(), 0, owner, ""
        );
        vm.stopPrank();

        return l;
    }

    function _enterPosition(address user, uint256 depositAmount, uint256 borrowAmount) internal {
        vm.startPrank(user);
        if (!MORPHO.isAuthorized(user, address(lendingRouter))) MORPHO.setAuthorization(address(lendingRouter), true);
        asset.approve(address(lendingRouter), depositAmount);
        lendingRouter.enterPosition(
            user, address(y), depositAmount, borrowAmount,
            getDepositData(user, depositAmount + borrowAmount)
        );
        vm.stopPrank();
    }

    function test_dilution_attack() public {
        address attacker = makeAddr("attacker");
        vm.prank(owner);
        asset.transfer(attacker, defaultDeposit + defaultBorrow + 1);

        _enterPosition(attacker, 1, 0);
        vm.warp(block.timestamp + 6 minutes);

        vm.startPrank(attacker);
        // Mint and donate wrapped tokens
        asset.approve(address(w), defaultDeposit + defaultBorrow);
        MockWrapperERC20(address(w)).deposit(defaultDeposit + defaultBorrow);
        MockWrapperERC20(address(w)).transfer(address(y), w.balanceOf(attacker));
        vm.stopPrank();

        _enterPosition(msg.sender, defaultDeposit, defaultBorrow);
        vm.startPrank(attacker);
        uint256 assetsBefore = asset.balanceOf(attacker);
        uint256 shares = lendingRouter.balanceOfCollateral(attacker, address(y));
        lendingRouter.exitPosition(
            attacker,
            address(y),
            attacker,
            shares,
            0,
            getRedeemData(attacker, shares)
        );
        uint256 assetsAfter = asset.balanceOf(attacker);
        vm.stopPrank();
        uint256 profitsWithdrawn = assetsAfter - assetsBefore;
        // NOTE: the attacker will lose money on the donation since some of it will be allocated to the
        // virtual shares and some will accrue to fees
        assertLe(profitsWithdrawn, defaultDeposit + defaultBorrow);
    }
}

contract TestDilutionAttack_USDC is TestDilutionAttack {
    function setAsset() internal override { asset = USDC; }
}

contract TestDilutionAttack_WETH is TestDilutionAttack {
    function setAsset() internal override { asset = ERC20(address(WETH)); }
}