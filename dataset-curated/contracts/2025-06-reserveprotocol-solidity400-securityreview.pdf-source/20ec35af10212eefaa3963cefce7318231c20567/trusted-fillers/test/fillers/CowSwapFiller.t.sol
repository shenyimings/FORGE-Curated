// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "forge-std/Test.sol";

import { MockERC20 } from "@mock/MockERC20.sol";
import { MockEIP712 } from "@mock/MockEIP712.sol";
import { BaseTest, CowSwapFiller } from "@test/base/BaseTest.sol";

import { IBaseTrustedFiller } from "@interfaces/IBaseTrustedFiller.sol";

import { GPV2_SETTLEMENT } from "@src/fillers/cowswap/Constants.sol";
import { GPv2OrderLib } from "@src/fillers/cowswap/GPv2OrderLib.sol";

contract CowSwapFillerFillerTest is BaseTest {
    CowSwapFiller trustedFiller;

    MockERC20 sellToken;
    MockERC20 buyToken;

    uint256 sellAmount = 1e18;
    uint256 minBuyAmount = 1e18;

    function _setUp() public override {
        sellToken = new MockERC20("Sell Token", "SELL", 18);
        buyToken = new MockERC20("Buy Token", "BUY", 18);

        sellToken.mint(address(this), sellAmount);
        buyToken.mint(address(this), minBuyAmount);

        trustedFiller = CowSwapFiller(
            address(trustedFillerRegistry.createTrustedFiller(address(this), address(cowSwapFiller), bytes32(0)))
        );

        sellToken.approve(address(trustedFiller), sellAmount);
        trustedFiller.initialize(address(this), sellToken, buyToken, sellAmount, minBuyAmount);

        // deploy a MockEIP712 to the GPV2_SETTLEMENT address
        address mockEIP712 = address(
            new MockEIP712(0xc078f884a2676e1345748b1feace7b0abee5d00ecadb6e574dcdd109a63e8943)
        );
        vm.etch(address(GPV2_SETTLEMENT), mockEIP712.code);
    }

    function test_CowSwap_correctInitialization() public view {
        assertTrue(trustedFiller.fillCreator() == address(this));
        assertTrue(trustedFiller.sellToken() == sellToken);
        assertTrue(trustedFiller.buyToken() == buyToken);
        assertTrue(trustedFiller.sellAmount() == sellAmount);
        assertTrue(trustedFiller.price() == 1e27);
    }

    function test_CowSwap_isValidSignature_orderHash() public {
        GPv2OrderLib.Data memory order = GPv2OrderLib.Data({
            sellToken: sellToken,
            buyToken: buyToken,
            receiver: address(trustedFiller),
            sellAmount: sellAmount,
            buyAmount: minBuyAmount,
            validTo: uint32(block.timestamp + 1),
            appData: bytes32(0),
            feeAmount: 0,
            kind: GPv2OrderLib.KIND_SELL,
            partiallyFillable: true,
            sellTokenBalance: GPv2OrderLib.BALANCE_ERC20,
            buyTokenBalance: GPv2OrderLib.BALANCE_ERC20
        });
        bytes32 orderHash = GPv2OrderLib.hash(order, GPV2_SETTLEMENT.domainSeparator());

        bytes4 returnSelector = trustedFiller.isValidSignature(orderHash, abi.encode(order));
        assertTrue(returnSelector == trustedFiller.isValidSignature.selector);

        vm.expectRevert();
        trustedFiller.isValidSignature(bytes32(uint256(123)), abi.encode(order));
    }

    function test_CowSwap_swapActive() public {
        assertFalse(trustedFiller.swapActive());

        sellToken.burn(address(trustedFiller), sellAmount);
        assertTrue(trustedFiller.swapActive());

        vm.expectRevert(abi.encodeWithSelector(IBaseTrustedFiller.IBaseTrustedFiller__SwapActive.selector));
        trustedFiller.closeFiller();
    }
}
