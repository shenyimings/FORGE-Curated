// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {MarketParamsLib} from "@morpho-blue/libraries/MarketParamsLib.sol";
import {IMorpho} from "@morpho-blue/interfaces/IMorpho.sol";
import {MorphoLendingAdapterTest} from "./MorphoLendingAdapter.t.sol";
import {IMorphoLendingAdapter} from "src/interfaces/IMorphoLendingAdapter.sol";
import {MorphoLendingAdapter} from "src/lending/MorphoLendingAdapter.sol";

contract GetLiquidationPenaltyTest is MorphoLendingAdapterTest {
    function test_getLiquidationPenalty_DefaultLendingAdapter() public view {
        // Liquidation penalty is 0 because default lending adapter is deployed with 100% lltv
        uint256 liquidationPenalty = lendingAdapter.getLiquidationPenalty();
        assertEq(liquidationPenalty, 0);
    }

    function test_getLiquidationPenalty_91_50_lltv() public {
        // Simulate PT-sUSDE-27MAR2025 / DAI market from Morpho UI
        lendingAdapter = _deployLendingAdapterWithLltv(0.915e18);

        uint256 liquidationPenalty = lendingAdapter.getLiquidationPenalty();
        assertEq(liquidationPenalty, 0.02616726526423807e18);

        // Validate that the number is that same as on morpho UI
        uint256 liquidationPenaltyOnFourDecimals = liquidationPenalty / 1e14 * 1e14;
        assertEq(liquidationPenaltyOnFourDecimals, 0.0261e18); // 2.61%
    }

    function test_getLiquidationPenalty_86_lltv() public {
        // Simulate cbBTC / USDC market from Morpho UI
        lendingAdapter = _deployLendingAdapterWithLltv(0.86e18);

        uint256 liquidationPenalty = lendingAdapter.getLiquidationPenalty();
        assertEq(liquidationPenalty, 0.043841336116910229e18);

        // Validate that the number is the same as on morpho UI
        uint256 liquidationPenaltyOnFourDecimals = liquidationPenalty / 1e14 * 1e14;
        assertEq(liquidationPenaltyOnFourDecimals, 0.0438e18); // 4.38%
    }

    function _deployLendingAdapterWithLltv(uint256 lltv) public returns (IMorphoLendingAdapter) {
        defaultMarketParams.lltv = lltv;
        vm.mockCall(
            address(morpho),
            abi.encodeWithSelector(IMorpho.idToMarketParams.selector, defaultMarketId),
            abi.encode(defaultMarketParams)
        );

        return IMorphoLendingAdapter(
            address(
                new ERC1967Proxy(
                    address(lendingAdapter),
                    abi.encodeCall(MorphoLendingAdapter.initialize, (defaultMarketId, authorizedCreator))
                )
            )
        );
    }
}
