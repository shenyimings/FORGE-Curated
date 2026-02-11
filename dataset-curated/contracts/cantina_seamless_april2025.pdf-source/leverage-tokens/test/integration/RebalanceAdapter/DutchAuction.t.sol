// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {LeverageTokenConfig} from "src/types/DataTypes.sol";
import {RebalanceTest} from "test/integration/LeverageManager/Rebalance.t.sol";
import {DutchAuctionRebalanceAdapter} from "src/rebalance/DutchAuctionRebalanceAdapter.sol";
import {Auction, LeverageTokenState} from "src/types/DataTypes.sol";
import {IDutchAuctionRebalanceAdapter} from "src/interfaces/IDutchAuctionRebalanceAdapter.sol";
import {RebalanceAdapter} from "src/rebalance/RebalanceAdapter.sol";
import {ILendingAdapter} from "src/interfaces/ILendingAdapter.sol";
import {ICollateralRatiosRebalanceAdapter} from "src/interfaces/ICollateralRatiosRebalanceAdapter.sol";

contract DutchAuctionTest is RebalanceTest {
    function test_setUp() public view {
        assertEq(address(ethLong2xRebalanceAdapter.getLeverageToken()), address(ethLong2x));
        assertEq(address(ethLong2xRebalanceAdapter.getLeverageManager()), address(leverageManager));
        assertEq(ethLong2xRebalanceAdapter.getAuctionDuration(), 7 minutes);
        assertEq(ethLong2xRebalanceAdapter.getInitialPriceMultiplier(), 1.2e18);
        assertEq(ethLong2xRebalanceAdapter.getMinPriceMultiplier(), 0.98e18);
        assertEq(ethLong2xRebalanceAdapter.getLeverageTokenMinCollateralRatio(), 1.8e18);
        assertEq(ethLong2xRebalanceAdapter.getLeverageTokenMaxCollateralRatio(), 2.2e18);
        assertEq(ethLong2xRebalanceAdapter.getAuthorizedCreator(), address(this));
    }

    function testFork_DeployNewDutchAuctionRebalanceAdapter_RevertIf_MinPriceMultiplierTooHigh() public {
        vm.expectRevert(IDutchAuctionRebalanceAdapter.MinPriceMultiplierTooHigh.selector);
        ethLong2xRebalanceAdapter = _deployRebalanceAdapter(1, 2, 2, 1, 1.2e18, 1.2e18 + 1, 1.1e18, 40_00);
    }

    function testFork_DeployNewDutchAuctionRebalanceAdapter_RevertIf_InvalidAuctionDuration() public {
        vm.expectRevert(IDutchAuctionRebalanceAdapter.InvalidAuctionDuration.selector);
        ethLong2xRebalanceAdapter = _deployRebalanceAdapter(1, 2, 2, 0, 1.2e18, 0.9e18, 1.1e18, 40_00);
    }

    function testFork_DeployNewDutchAuctionRebalanceAdapter_RevertIf_InvalidCollateralRatios() public {
        vm.expectRevert(ICollateralRatiosRebalanceAdapter.InvalidCollateralRatios.selector);
        _deployRebalanceAdapter(3, 2, 2, 1, 1.2e18, 0.9e18, 1.1e18, 40_00);
    }

    function testFork_CreateNewLeverageToken_RevertIf_LeverageTokenAlreadySet() public {
        address morphoLendingAdapter = makeAddr("morphoLendingAdapter");
        vm.mockCall(
            address(morphoLendingAdapter),
            abi.encodeWithSelector(ILendingAdapter.postLeverageTokenCreation.selector),
            abi.encode()
        );

        LeverageTokenConfig memory config = LeverageTokenConfig({
            lendingAdapter: ILendingAdapter(morphoLendingAdapter),
            rebalanceAdapter: ethLong2xRebalanceAdapter,
            depositTokenFee: 0,
            withdrawTokenFee: 0
        });

        vm.expectRevert(IDutchAuctionRebalanceAdapter.LeverageTokenAlreadySet.selector);
        leverageManager.createNewLeverageToken(config, "ETH Long 2x", "ETH2X");
    }

    function _prepareOverCollateralizedState() internal {
        // Deposit 10 WETH following target ratio
        uint256 equityToDeposit = 10 * 1e18;
        uint256 collateralToAdd = leverageManager.previewDeposit(ethLong2x, equityToDeposit).collateral;
        _deposit(ethLong2x, user, equityToDeposit, collateralToAdd);

        _moveEthPrice(20_00); // 20% up price movement. Collateral ratio should be 2.4x
    }

    function _prepareUnderCollateralizedState() internal {
        // Deposit 10 WETH following target ratio
        uint256 equityToDeposit = 10 * 1e18;
        uint256 collateralToAdd = leverageManager.previewDeposit(ethLong2x, equityToDeposit).collateral;
        _deposit(ethLong2x, user, equityToDeposit, collateralToAdd);

        _moveEthPrice(-20_00); // 20% down price movement. Collateral ratio should be 1.6x
    }
}
