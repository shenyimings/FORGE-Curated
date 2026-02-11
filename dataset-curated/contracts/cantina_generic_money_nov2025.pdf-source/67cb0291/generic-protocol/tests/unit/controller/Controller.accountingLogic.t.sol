// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.29;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

import { ControllerTest } from "./Controller.t.sol";

using Math for uint256;

abstract contract Controller_AccountingLogic_Test is ControllerTest { }

contract Controller_AccountingLogic_BackingAssetsValue_Test is Controller_AccountingLogic_Test {
    function test_shouldReturnZero_whenNoVaults() public view {
        assertEq(controller.backingAssetsValue(), 0);
    }

    function test_shouldReturnSumOfAllVaultsBackingAssetsValue() public {
        _mockVault(makeAddr("vault1"), makeAddr("asset1"), 100e18, makeAddr("feed1"), 1.1e8, 8);
        _mockVault(makeAddr("vault2"), makeAddr("asset2"), 200e18, makeAddr("feed2"), 0.74e8, 8);
        _mockVault(makeAddr("vault3"), makeAddr("asset3"), 300e18, makeAddr("feed3"), 1.2e8, 8);

        assertEq(controller.backingAssetsValue(), 100e18 * 1.1 + 200e18 * 0.74 + 300e18 * 1.2);
    }
}

contract Controller_AccountingLogic_SafetyBuffer_Test is Controller_AccountingLogic_Test {
    function test_shouldReturnZero_whenNoVaults() public {
        vm.mockCall(address(share), abi.encodeWithSelector(IERC20.totalSupply.selector), abi.encode(0));

        assertEq(controller.safetyBuffer(), 0);
    }

    function test_shouldReturnZero_whenBackingValueLessOrEqualToTotalSupply() public {
        _mockVault(makeAddr("vault1"), makeAddr("asset1"), 100e18, makeAddr("feed1"), 1e8, 8);
        _mockVault(makeAddr("vault2"), makeAddr("asset2"), 200e18, makeAddr("feed2"), 1e8, 8);
        _mockVault(makeAddr("vault3"), makeAddr("asset3"), 300e18, makeAddr("feed3"), 1e8, 8);

        vm.mockCall(address(share), abi.encodeWithSelector(IERC20.totalSupply.selector), abi.encode(601e18));

        assertEq(controller.safetyBuffer(), 0);
    }

    function test_shouldReturnSafetyBuffer_whenBackingValueGreaterThanTotalSupply() public {
        _mockVault(makeAddr("vault1"), makeAddr("asset1"), 100e18, makeAddr("feed1"), 1e8, 8);
        _mockVault(makeAddr("vault2"), makeAddr("asset2"), 200e18, makeAddr("feed2"), 1e8, 8);
        _mockVault(makeAddr("vault3"), makeAddr("asset3"), 300e18, makeAddr("feed3"), 1e8, 8);

        vm.mockCall(address(share), abi.encodeWithSelector(IERC20.totalSupply.selector), abi.encode(550e18));

        assertEq(controller.safetyBuffer(), 50e18);
    }
}

contract Controller_AccountingLogic_AssetDepositPrice_Test is Controller_AccountingLogic_Test {
    address asset = makeAddr("asset1");
    address feed = makeAddr("feed1");

    function test_shouldReturnMaxPrice_whenPriceAboveMax(uint256 price) public {
        price = bound(price, controller.ASSET_DEPOSIT_MAX_PRICE() + 1, uint256(type(int256).max));
        _mockVault(makeAddr("vault1"), asset, 100e18, feed, price, 18);

        assertEq(controller.assetDepositPrice(asset), controller.ASSET_DEPOSIT_MAX_PRICE());
    }

    function test_shouldReturnPrice_whenPriceBelowMax(uint256 price) public {
        price = bound(price, 1, controller.ASSET_DEPOSIT_MAX_PRICE() - 1);
        _mockVault(makeAddr("vault1"), asset, 100e18, feed, price, 18);

        assertEq(controller.assetDepositPrice(asset), price);
    }
}

contract Controller_AccountingLogic_AssetRedemptionPrice_Test is Controller_AccountingLogic_Test {
    address asset = makeAddr("asset1");
    address feed = makeAddr("feed1");

    function test_shouldReturnMinPrice_whenPriceBelowMin(uint256 price) public {
        price = bound(price, 1, controller.ASSET_REDEMPTION_MIN_PRICE() - 1);
        _mockVault(makeAddr("vault1"), asset, 100e18, feed, price, 18);

        assertEq(controller.assetRedemptionPrice(asset), controller.ASSET_REDEMPTION_MIN_PRICE());
    }

    function test_shouldReturnPrice_whenPriceAboveMin(uint256 price) public {
        price = bound(price, controller.ASSET_REDEMPTION_MIN_PRICE() + 1, uint256(type(int256).max));
        _mockVault(makeAddr("vault1"), asset, 100e18, feed, price, 18);

        assertEq(controller.assetRedemptionPrice(asset), price);
    }
}

contract Controller_AccountingLogic_ShareRedemptionPrice_Test is Controller_AccountingLogic_Test {
    function test_shouldReturnMintPrice_whenNoShares() public {
        vm.mockCall(address(share), abi.encodeWithSelector(IERC20.totalSupply.selector), abi.encode(0));

        assertEq(controller.shareRedemptionPrice(), controller.SHARE_MINT_PRICE());
    }

    function testFuzz_shouldReturnMintPrice_whenShareTotalSupplyLessThanCollateralValue(uint256 price) public {
        price = bound(price, 1e18, 30e18);

        vm.mockCall(address(share), abi.encodeWithSelector(IERC20.totalSupply.selector), abi.encode(500e18));
        _mockVault(makeAddr("vault1"), makeAddr("asset1"), 500e18, makeAddr("feed1"), price, 18);

        assertEq(controller.shareRedemptionPrice(), controller.SHARE_MINT_PRICE());
    }

    function testFuzz_shouldReturnCollateralValuePerShare_whenShareTotalSupplyGreaterThanCollateralValue(uint256 price)
        public
    {
        price = bound(price, 0.001e18, 1e18 - 1);

        vm.mockCall(address(share), abi.encodeWithSelector(IERC20.totalSupply.selector), abi.encode(500e18));
        _mockVault(makeAddr("vault1"), makeAddr("asset1"), 500e18, makeAddr("feed1"), price, 18);

        assertEq(controller.shareRedemptionPrice(), price);
    }
}

contract Controller_AccountingLogic_ConvertToShares_Test is Controller_AccountingLogic_Test {
    function testFuzz_shouldMulByAssetPriceAndDivBySharePrice(
        uint256 assets,
        uint256 assetPrice,
        uint256 sharePrice
    )
        external
        view
    {
        assets = bound(assets, 0, type(uint256).max / 1e18);
        assetPrice = bound(assetPrice, 0.001e18, 100e18);
        sharePrice = bound(sharePrice, 0.001e18, 100e18);

        assertEq(
            controller.exposed_convertToShares(assets, assetPrice, sharePrice, Math.Rounding.Floor),
            assets.mulDiv(assetPrice, sharePrice, Math.Rounding.Floor)
        );
        assertEq(
            controller.exposed_convertToShares(assets, assetPrice, sharePrice, Math.Rounding.Ceil),
            assets.mulDiv(assetPrice, sharePrice, Math.Rounding.Ceil)
        );
    }
}

contract Controller_AccountingLogic_ConvertToAssets_Test is Controller_AccountingLogic_Test {
    function testFuzz_shouldMulBySharePriceAndDivByAssetPrice(
        uint256 assets,
        uint256 assetPrice,
        uint256 sharePrice
    )
        external
        view
    {
        assets = bound(assets, 0, type(uint256).max / 1e18);
        assetPrice = bound(assetPrice, 0.001e18, 100e18);
        sharePrice = bound(sharePrice, 0.001e18, 100e18);

        assertEq(
            controller.exposed_convertToAssets(assets, assetPrice, sharePrice, Math.Rounding.Floor),
            assets.mulDiv(sharePrice, assetPrice, Math.Rounding.Floor)
        );
        assertEq(
            controller.exposed_convertToAssets(assets, assetPrice, sharePrice, Math.Rounding.Ceil),
            assets.mulDiv(sharePrice, assetPrice, Math.Rounding.Ceil)
        );
    }
}
