// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";

import {SetupGGVStrategy} from "./SetupGGVStrategy.sol";
import {GGVStrategy} from "src/strategy/GGVStrategy.sol";
import {IStrategyCallForwarder} from "src/interfaces/IStrategyCallForwarder.sol";
import {console} from "forge-std/console.sol";

contract SupplyMinimumMintUint256Test is Test, SetupGGVStrategy {
    function test_supply_allows_minimumMint_above_uint16() public {
        uint256 depositAmount = 1 ether;
        uint256 minimumMint = uint256(uint16(type(uint16).max)) + 1; // > type(uint16).max

        // Predict forwarder address and compute minting amount in advance.
        IStrategyCallForwarder callForwarder = ggvStrategy.getStrategyCallForwarderAddress(userAlice);
        uint256 wstethToMint = pool.remainingMintingCapacitySharesOf(address(callForwarder), depositAmount);

        vm.prank(userAlice);
        ggvStrategy.supply{value: depositAmount}(address(0), wstethToMint, abi.encode(GGVStrategy.GGVParamsSupply(minimumMint)));

        // Strategy minted liability exactly equals requested wstETH amount (shares-denominated)
        assertEq(ggvStrategy.mintedStethSharesOf(userAlice), wstethToMint, "minted stETH shares mismatch");

        // Ensure teller deposit produced vault shares and honored minimumMint.
        uint256 ggvShares = boringVault.balanceOf(address(callForwarder));
        assertGt(ggvShares, 0, "expected GGV shares > 0");
        assertGe(ggvShares, minimumMint, "GGV shares should meet minimumMint requirement");
    }
}

