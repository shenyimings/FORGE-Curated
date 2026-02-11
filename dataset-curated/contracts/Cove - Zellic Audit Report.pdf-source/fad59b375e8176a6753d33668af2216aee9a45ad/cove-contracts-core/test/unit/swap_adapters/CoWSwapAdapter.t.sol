// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { BaseTest } from "test/utils/BaseTest.t.sol";

import { Errors } from "src/libraries/Errors.sol";
import { CoWSwapAdapter } from "src/swap_adapters/CoWSwapAdapter.sol";
import { CoWSwapClone } from "src/swap_adapters/CoWSwapClone.sol";
import { BasketTradeOwnership, ExternalTrade } from "src/types/Trades.sol";

contract CoWSwapAdapterTest is BaseTest {
    CoWSwapAdapter private adapter;
    address internal constant _VAULT_RELAYER = 0xC92E8bdf79f0507f65a392b0ab4667716BFE0110;
    address internal clone;

    struct ExternalTradeWithoutBasketOwnership {
        address sellToken;
        address buyToken;
        uint256 sellAmount;
        uint256 minAmount;
    }

    function setUp() public override {
        // Deploy the CoWSwapAdapter contract
        clone = address(new CoWSwapClone());
        adapter = new CoWSwapAdapter(clone);
    }

    function testFuzz_constructor(address impl) public {
        vm.assume(impl != address(0));
        assertEq(new CoWSwapAdapter(impl).cloneImplementation(), impl, "Incorrect clone implementation address");
    }

    function test_constructor_revertWhen_ZeroAddress() public {
        vm.expectRevert(Errors.ZeroAddress.selector);
        new CoWSwapAdapter(address(0));
    }

    function testFuzz_executeTokenSwap(ExternalTradeWithoutBasketOwnership[] calldata externalTrades) public {
        vm.assume(externalTrades.length < 5);
        for (uint256 i = 0; i < externalTrades.length; i++) {
            // Avoid precompiled contract addresses from 0x01 to 0x09
            vm.assume(uint160(externalTrades[i].sellToken) > 9);
            vm.assume(externalTrades[i].sellToken != CONSOLE);
            vm.assume(externalTrades[i].sellToken != VM_ADDRESS);
            vm.assume(uint160(externalTrades[i].buyToken) > 9);
            vm.assume(externalTrades[i].buyToken != CONSOLE);
            vm.assume(externalTrades[i].buyToken != VM_ADDRESS);
            bytes32 salt = keccak256(
                abi.encodePacked(
                    externalTrades[i].sellToken,
                    externalTrades[i].buyToken,
                    externalTrades[i].sellAmount,
                    externalTrades[i].minAmount,
                    uint32(vm.getBlockTimestamp() + 15 minutes)
                )
            );
            address deployed = _predictDeterministicAddress(salt, address(adapter));
            vm.mockCall(
                externalTrades[i].sellToken,
                abi.encodeWithSelector(IERC20.transfer.selector, deployed, externalTrades[i].sellAmount),
                abi.encode(true)
            );
            vm.mockCall(
                externalTrades[i].sellToken,
                abi.encodeWithSelector(IERC20.approve.selector, _VAULT_RELAYER, type(uint256).max),
                abi.encode(true)
            );

            vm.expectEmit();
            emit CoWSwapAdapter.OrderCreated(
                externalTrades[i].sellToken,
                externalTrades[i].buyToken,
                externalTrades[i].sellAmount,
                externalTrades[i].minAmount,
                uint32(vm.getBlockTimestamp() + 15 minutes),
                deployed
            );
        }
        ExternalTrade[] memory trades = new ExternalTrade[](externalTrades.length);
        for (uint256 i = 0; i < externalTrades.length; i++) {
            trades[i] = ExternalTrade({
                sellToken: externalTrades[i].sellToken,
                buyToken: externalTrades[i].buyToken,
                sellAmount: externalTrades[i].sellAmount,
                minAmount: externalTrades[i].minAmount,
                basketTradeOwnership: new BasketTradeOwnership[](0) // Use empty array for basket trade ownership
             });
        }
        adapter.executeTokenSwap(trades, "");
    }

    function testFuzz_completeTokenSwap(ExternalTradeWithoutBasketOwnership[] calldata externalTrades) public {
        testFuzz_executeTokenSwap(externalTrades);
        ExternalTrade[] memory trades = new ExternalTrade[](externalTrades.length);
        for (uint256 i = 0; i < externalTrades.length; i++) {
            trades[i] = ExternalTrade({
                sellToken: externalTrades[i].sellToken,
                buyToken: externalTrades[i].buyToken,
                sellAmount: externalTrades[i].sellAmount,
                minAmount: externalTrades[i].minAmount,
                basketTradeOwnership: new BasketTradeOwnership[](0) // Use empty array for basket trade ownership
             });
            bytes32 salt = keccak256(
                abi.encodePacked(
                    externalTrades[i].sellToken,
                    externalTrades[i].buyToken,
                    externalTrades[i].sellAmount,
                    externalTrades[i].minAmount,
                    uint32(vm.getBlockTimestamp() + 15 minutes)
                )
            );
            address deployed = _predictDeterministicAddress(salt, address(adapter));
            vm.mockCall(
                deployed,
                abi.encodeWithSelector(CoWSwapClone(deployed).claim.selector),
                abi.encodePacked(externalTrades[i].sellAmount, externalTrades[i].minAmount)
            );

            vm.expectEmit();
            emit CoWSwapAdapter.TokenSwapCompleted(
                externalTrades[i].sellToken,
                externalTrades[i].buyToken,
                externalTrades[i].sellAmount,
                externalTrades[i].minAmount,
                deployed
            );
        }
        uint256[2][] memory claimedAmounts = adapter.completeTokenSwap(trades);
        for (uint256 i = 0; i < externalTrades.length; i++) {
            assertEq(claimedAmounts[i][0], externalTrades[i].sellAmount, "Incorrect claimed sell amount");
            assertEq(claimedAmounts[i][1], externalTrades[i].minAmount, "Incorrect claimed buy amount");
        }
    }
}
