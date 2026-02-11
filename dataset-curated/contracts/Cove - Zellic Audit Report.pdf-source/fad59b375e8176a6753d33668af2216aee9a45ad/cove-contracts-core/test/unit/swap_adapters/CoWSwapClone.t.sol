// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import { Test } from "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ClonesWithImmutableArgs } from "clones-with-immutable-args/ClonesWithImmutableArgs.sol";

import { ERC20Mock } from "test/utils/mocks/ERC20Mock.sol";

import { GPv2Order } from "src/deps/cowprotocol/GPv2Order.sol";
import { CoWSwapClone } from "src/swap_adapters/CoWSwapClone.sol";

contract CoWSwapCloneTest is Test {
    using GPv2Order for GPv2Order.Data;

    CoWSwapClone private impl;
    address internal constant _VAULT_RELAYER = 0xC92E8bdf79f0507f65a392b0ab4667716BFE0110;
    bytes32 internal constant _COW_SETTLEMENT_DOMAIN_SEPARATOR =
        0xc078f884a2676e1345748b1feace7b0abee5d00ecadb6e574dcdd109a63e8943;

    bytes4 internal constant _ERC1271_MAGIC_VALUE = 0x1626ba7e;
    bytes4 internal constant _ERC1271_NON_MAGIC_VALUE = 0xffffffff;

    function setUp() public {
        // Deploy the CoWSwapClone implementation
        impl = new CoWSwapClone();
    }

    function testFuzz_clone(
        address sellToken,
        address buyToken,
        uint256 sellAmount,
        uint256 minBuyAmount,
        uint32 validTo,
        address receiver,
        address operator,
        bytes32 salt
    )
        public
        returns (address clone)
    {
        clone = ClonesWithImmutableArgs.clone3(
            address(impl),
            abi.encodePacked(sellToken, buyToken, sellAmount, minBuyAmount, uint64(validTo), receiver, operator),
            salt
        );
        CoWSwapClone cloneInstance = CoWSwapClone(clone);
        // Test that the clone contract was deployed and cloned correctly
        assertEq(cloneInstance.sellToken(), sellToken, "Incorrect sell token");
        assertEq(cloneInstance.buyToken(), buyToken, "Incorrect buy token");
        assertEq(cloneInstance.sellAmount(), sellAmount, "Incorrect sell amount");
        assertEq(cloneInstance.minBuyAmount(), minBuyAmount, "Incorrect min buy amount");
        assertEq(cloneInstance.validTo(), validTo, "Incorrect valid to");
        assertEq(cloneInstance.receiver(), receiver, "Incorrect receiver");
        assertEq(cloneInstance.operator(), operator, "Incorrect operator");
    }

    function testFuzz_initialize_revertWhen_SellTokenIsNotERC20(
        address sellToken,
        address buyToken,
        uint256 sellAmount,
        uint256 minBuyAmount,
        uint32 validTo,
        address receiver,
        address operator,
        bytes32 salt
    )
        public
    {
        vm.assume(sellToken.code.length == 0);
        address clone = testFuzz_clone(sellToken, buyToken, sellAmount, minBuyAmount, validTo, receiver, operator, salt);
        vm.expectRevert();
        CoWSwapClone(clone).initialize();
    }

    function testFuzz_initialize(
        address buyToken,
        uint256 sellAmount,
        uint256 minBuyAmount,
        uint32 validTo,
        address receiver,
        address operator,
        bytes32 salt
    )
        public
    {
        address sellToken = address(new ERC20Mock());
        address clone = testFuzz_clone(sellToken, buyToken, sellAmount, minBuyAmount, validTo, receiver, operator, salt);
        uint256 allowanceBefore = IERC20(sellToken).allowance(address(clone), _VAULT_RELAYER);
        assertEq(allowanceBefore, 0, "Allowance should be 0 before initialization");
        vm.expectCall(
            sellToken, abi.encodeWithSelector(IERC20(sellToken).approve.selector, _VAULT_RELAYER, type(uint256).max)
        );
        // Check that the OrderCreated event was emitted correctly
        vm.expectEmit();
        emit CoWSwapClone.OrderCreated(sellToken, buyToken, sellAmount, minBuyAmount, validTo, receiver, operator);
        CoWSwapClone(clone).initialize();
        uint256 allowanceAfter = IERC20(sellToken).allowance(address(clone), _VAULT_RELAYER);
        assertEq(allowanceAfter, type(uint256).max, "Allowance should be max after initialization");
    }

    function testFuzz_isValidSignature(
        address sellToken,
        address buyToken,
        uint256 sellAmount,
        uint256 minBuyAmount,
        uint256 buyAmount,
        uint32 validTo,
        address receiver,
        address operator,
        bytes32 salt
    )
        public
    {
        vm.assume(buyAmount >= minBuyAmount);
        address clone = testFuzz_clone(sellToken, buyToken, sellAmount, minBuyAmount, validTo, receiver, operator, salt);
        GPv2Order.Data memory order = _getOrderData(sellToken, buyToken, sellAmount, buyAmount, validTo, clone);
        bytes32 orderDigest = order.hash(_COW_SETTLEMENT_DOMAIN_SEPARATOR);

        assertEq(
            CoWSwapClone(clone).isValidSignature(orderDigest, abi.encode(order)),
            _ERC1271_MAGIC_VALUE,
            "Invalid signature magic value"
        );
    }

    function testFuzz_isValidSignature_returnsNonMagicValueWhen_OrderDigestIsNotCorrect(
        address sellToken,
        address buyToken,
        uint256 sellAmount,
        uint256 buyAmount,
        uint32 validTo,
        address receiver,
        address operator,
        bytes32 salt,
        bytes32 badOrderDigest
    )
        public
    {
        address clone = testFuzz_clone(sellToken, buyToken, sellAmount, buyAmount, validTo, receiver, operator, salt);
        GPv2Order.Data memory order = _getOrderData(sellToken, buyToken, sellAmount, buyAmount, validTo, clone);
        vm.assume(badOrderDigest != order.hash(_COW_SETTLEMENT_DOMAIN_SEPARATOR));

        assertEq(
            CoWSwapClone(clone).isValidSignature(badOrderDigest, abi.encode(order)),
            _ERC1271_NON_MAGIC_VALUE,
            "Invalid signature non-magic value"
        );
    }

    function testFuzz_isValidSignature_returnsNonMagicValueWhen_SellTokenIsNotCorrect(
        address sellToken,
        address buyToken,
        uint256 sellAmount,
        uint256 buyAmount,
        uint32 validTo,
        address receiver,
        address operator,
        bytes32 salt,
        address badSellToken
    )
        public
    {
        vm.assume(sellToken != badSellToken);
        address clone = testFuzz_clone(sellToken, buyToken, sellAmount, buyAmount, validTo, receiver, operator, salt);
        GPv2Order.Data memory order = _getOrderData(badSellToken, buyToken, sellAmount, buyAmount, validTo, clone);

        assertEq(
            CoWSwapClone(clone).isValidSignature(order.hash(_COW_SETTLEMENT_DOMAIN_SEPARATOR), abi.encode(order)),
            _ERC1271_NON_MAGIC_VALUE,
            "Invalid signature non-magic value"
        );
    }

    function testFuzz_isValidSignature_returnsNonMagicValueWhen_BuyTokenIsNotCorrect(
        address sellToken,
        address buyToken,
        uint256 sellAmount,
        uint256 buyAmount,
        uint32 validTo,
        address receiver,
        address operator,
        bytes32 salt,
        address badBuyToken
    )
        public
    {
        vm.assume(buyToken != badBuyToken);
        address clone = testFuzz_clone(sellToken, buyToken, sellAmount, buyAmount, validTo, receiver, operator, salt);
        GPv2Order.Data memory order = _getOrderData(sellToken, badBuyToken, sellAmount, buyAmount, validTo, clone);

        assertEq(
            CoWSwapClone(clone).isValidSignature(order.hash(_COW_SETTLEMENT_DOMAIN_SEPARATOR), abi.encode(order)),
            _ERC1271_NON_MAGIC_VALUE,
            "Invalid signature non-magic value"
        );
    }

    function testFuzz_isValidSignature_returnsNonMagicValueWhen_SellAmountIsNotCorrect(
        address sellToken,
        address buyToken,
        uint256 sellAmount,
        uint256 buyAmount,
        uint32 validTo,
        address receiver,
        address operator,
        bytes32 salt,
        uint256 badSellAmount
    )
        public
    {
        vm.assume(sellAmount != badSellAmount);
        address clone = testFuzz_clone(sellToken, buyToken, sellAmount, buyAmount, validTo, receiver, operator, salt);
        GPv2Order.Data memory order = _getOrderData(sellToken, buyToken, badSellAmount, buyAmount, validTo, clone);

        assertEq(
            CoWSwapClone(clone).isValidSignature(order.hash(_COW_SETTLEMENT_DOMAIN_SEPARATOR), abi.encode(order)),
            _ERC1271_NON_MAGIC_VALUE,
            "Invalid signature non-magic value"
        );
    }

    function testFuzz_isValidSignature_returnsNonMagicValueWhen_BuyAmountIsLessThanExpected(
        address sellToken,
        address buyToken,
        uint256 sellAmount,
        uint256 buyAmount,
        uint32 validTo,
        address receiver,
        address operator,
        bytes32 salt,
        uint256 badBuyAmount
    )
        public
    {
        vm.assume(badBuyAmount < buyAmount);
        address clone = testFuzz_clone(sellToken, buyToken, sellAmount, buyAmount, validTo, receiver, operator, salt);
        GPv2Order.Data memory order = _getOrderData(sellToken, buyToken, sellAmount, badBuyAmount, validTo, clone);

        assertEq(
            CoWSwapClone(clone).isValidSignature(order.hash(_COW_SETTLEMENT_DOMAIN_SEPARATOR), abi.encode(order)),
            _ERC1271_NON_MAGIC_VALUE,
            "Invalid signature non-magic value"
        );
    }

    function testFuzz_isValidSignature_returnsNonMagicValueWhen_ValidToIsNotCorrect(
        address sellToken,
        address buyToken,
        uint256 sellAmount,
        uint256 buyAmount,
        uint32 validTo,
        address receiver,
        address operator,
        bytes32 salt,
        uint32 badValidTo
    )
        public
    {
        vm.assume(validTo != badValidTo);
        address clone = testFuzz_clone(sellToken, buyToken, sellAmount, buyAmount, validTo, receiver, operator, salt);
        GPv2Order.Data memory order = _getOrderData(sellToken, buyToken, sellAmount, buyAmount, badValidTo, clone);

        assertEq(
            CoWSwapClone(clone).isValidSignature(order.hash(_COW_SETTLEMENT_DOMAIN_SEPARATOR), abi.encode(order)),
            _ERC1271_NON_MAGIC_VALUE,
            "Invalid signature non-magic value"
        );
    }

    function testFuzz_isValidSignature_returnsNonMagicValueWhen_FeeAmountIsNotZero(
        address sellToken,
        address buyToken,
        uint256 sellAmount,
        uint256 buyAmount,
        uint32 validTo,
        address receiver,
        address operator,
        bytes32 salt,
        uint256 feeAmount
    )
        public
    {
        vm.assume(feeAmount != 0);
        address clone = testFuzz_clone(sellToken, buyToken, sellAmount, buyAmount, validTo, receiver, operator, salt);
        GPv2Order.Data memory order = _getOrderData(sellToken, buyToken, sellAmount, buyAmount, validTo, clone);
        order.feeAmount = feeAmount;

        assertEq(
            CoWSwapClone(clone).isValidSignature(order.hash(_COW_SETTLEMENT_DOMAIN_SEPARATOR), abi.encode(order)),
            _ERC1271_NON_MAGIC_VALUE,
            "Invalid signature non-magic value"
        );
    }

    function testFuzz_isValidSignature_returnsNonMagicValueWhen_KindIsNotSell(
        address sellToken,
        address buyToken,
        uint256 sellAmount,
        uint256 buyAmount,
        uint32 validTo,
        address receiver,
        address operator,
        bytes32 salt,
        bytes1 kind
    )
        public
    {
        vm.assume(kind != GPv2Order.KIND_SELL);
        address clone = testFuzz_clone(sellToken, buyToken, sellAmount, buyAmount, validTo, receiver, operator, salt);
        GPv2Order.Data memory order = GPv2Order.Data({
            sellToken: IERC20(sellToken),
            buyToken: IERC20(buyToken),
            receiver: receiver,
            sellAmount: sellAmount,
            buyAmount: buyAmount,
            validTo: validTo,
            appData: 0,
            feeAmount: 0,
            kind: kind,
            partiallyFillable: false,
            sellTokenBalance: GPv2Order.BALANCE_ERC20,
            buyTokenBalance: GPv2Order.BALANCE_ERC20
        });
        bytes32 orderDigest = order.hash(_COW_SETTLEMENT_DOMAIN_SEPARATOR);

        assertEq(
            CoWSwapClone(clone).isValidSignature(orderDigest, abi.encode(order)),
            _ERC1271_NON_MAGIC_VALUE,
            "Invalid signature non-magic value"
        );
    }

    function testFuzz_isValidSignature_returnsNonMagicValueWhen_OrderIsPartiallyFillable(
        address sellToken,
        address buyToken,
        uint256 sellAmount,
        uint256 buyAmount,
        uint32 validTo,
        address receiver,
        address operator,
        bytes32 salt
    )
        public
    {
        address clone = testFuzz_clone(sellToken, buyToken, sellAmount, buyAmount, validTo, receiver, operator, salt);
        GPv2Order.Data memory order = _getOrderData(sellToken, buyToken, sellAmount, buyAmount, validTo, clone);
        order.partiallyFillable = true;

        assertEq(
            CoWSwapClone(clone).isValidSignature(order.hash(_COW_SETTLEMENT_DOMAIN_SEPARATOR), abi.encode(order)),
            _ERC1271_NON_MAGIC_VALUE,
            "Invalid signature non-magic value"
        );
    }

    function testFuzz_isValidSignature_returnsNonMagicValueWhen_SellTokenBalanceIsNotERC20(
        address sellToken,
        address buyToken,
        uint256 sellAmount,
        uint256 buyAmount,
        uint32 validTo,
        address receiver,
        address operator,
        bytes32 salt,
        bytes32 badSellTokenBalance
    )
        public
    {
        vm.assume(badSellTokenBalance != GPv2Order.BALANCE_ERC20);
        address clone = testFuzz_clone(sellToken, buyToken, sellAmount, buyAmount, validTo, receiver, operator, salt);
        GPv2Order.Data memory order = _getOrderData(sellToken, buyToken, sellAmount, buyAmount, validTo, clone);
        order.sellTokenBalance = badSellTokenBalance;

        assertEq(
            CoWSwapClone(clone).isValidSignature(order.hash(_COW_SETTLEMENT_DOMAIN_SEPARATOR), abi.encode(order)),
            _ERC1271_NON_MAGIC_VALUE,
            "Invalid signature non-magic value"
        );
    }

    function testFuzz_isValidSignature_returnsNonMagicValueWhen_BuyTokenBalanceIsNotERC20(
        address sellToken,
        address buyToken,
        uint256 sellAmount,
        uint256 buyAmount,
        uint32 validTo,
        address receiver,
        address operator,
        bytes32 salt,
        bytes32 badBuyTokenBalance
    )
        public
    {
        vm.assume(badBuyTokenBalance != GPv2Order.BALANCE_ERC20);
        address clone = testFuzz_clone(sellToken, buyToken, sellAmount, buyAmount, validTo, receiver, operator, salt);

        GPv2Order.Data memory order = _getOrderData(sellToken, buyToken, sellAmount, buyAmount, validTo, clone);
        order.buyTokenBalance = badBuyTokenBalance;

        assertEq(
            CoWSwapClone(clone).isValidSignature(order.hash(_COW_SETTLEMENT_DOMAIN_SEPARATOR), abi.encode(order)),
            _ERC1271_NON_MAGIC_VALUE,
            "Invalid signature non-magic value"
        );
    }

    function testFuzz_isValidSignature_returnsNonMagicValueWhen_ReceiverIsNotCorrect(
        address sellToken,
        address buyToken,
        uint256 sellAmount,
        uint256 buyAmount,
        uint32 validTo,
        address receiver,
        address operator,
        bytes32 salt,
        address badReceiver
    )
        public
    {
        address clone = testFuzz_clone(sellToken, buyToken, sellAmount, buyAmount, validTo, receiver, operator, salt);
        vm.assume(badReceiver != clone);
        GPv2Order.Data memory order = _getOrderData(sellToken, buyToken, sellAmount, buyAmount, validTo, badReceiver);

        assertEq(
            CoWSwapClone(clone).isValidSignature(order.hash(_COW_SETTLEMENT_DOMAIN_SEPARATOR), abi.encode(order)),
            _ERC1271_NON_MAGIC_VALUE,
            "Invalid signature non-magic value"
        );
    }

    function testFuzz_claim(
        uint256 initialSellBalance,
        uint256 initialBuyBalance,
        uint256 sellAmount,
        uint256 buyAmount,
        uint32 validTo,
        address receiver,
        address operator,
        bytes32 salt
    )
        public
    {
        vm.assume(receiver != address(0));

        // Deploy ERC20Mocks for sellToken and buyToken
        ERC20Mock sellToken = new ERC20Mock();
        ERC20Mock buyToken = new ERC20Mock();

        // Create the clone contract
        address clone = testFuzz_clone(
            address(sellToken), address(buyToken), sellAmount, buyAmount, validTo, receiver, operator, salt
        );

        // Mint tokens to the clone contract
        deal(address(sellToken), address(clone), initialSellBalance);
        deal(address(buyToken), address(clone), initialBuyBalance);

        // Check that the OrderClaimed event was emitted correctly
        vm.expectEmit();
        emit CoWSwapClone.OrderClaimed(operator, initialSellBalance, initialBuyBalance);

        // Claim the tokens
        vm.prank(operator);
        (uint256 claimedSellAmount, uint256 claimedBuyAmount) = CoWSwapClone(clone).claim();

        // Check that the tokens were transferred to the receiver
        assertEq(claimedSellAmount, initialSellBalance, "Incorrect claimed sell amount");
        assertEq(claimedBuyAmount, initialBuyBalance, "Incorrect claimed buy amount");
        assertEq(sellToken.balanceOf(receiver), initialSellBalance, "Incorrect sell token balance");
        assertEq(buyToken.balanceOf(receiver), initialBuyBalance, "Incorrect buy token balance");
    }

    function testFuzz_claim_revertWhen_CallerIsNotOperatorOrReceiver(
        address sellToken,
        address buyToken,
        uint256 sellAmount,
        uint256 buyAmount,
        uint32 validTo,
        address receiver,
        address operator,
        bytes32 salt,
        address caller
    )
        public
    {
        address clone = testFuzz_clone(sellToken, buyToken, sellAmount, buyAmount, validTo, receiver, operator, salt);
        // Test that the claim function reverts if called by someone other than the operator or receiver
        vm.assume(caller != operator && caller != receiver);
        vm.expectRevert(CoWSwapClone.CallerIsNotOperatorOrReceiver.selector);
        vm.prank(caller);
        CoWSwapClone(clone).claim();
    }

    function _getOrderData(
        address sellToken,
        address buyToken,
        uint256 sellAmount,
        uint256 buyAmount,
        uint32 validTo,
        address receiver
    )
        internal
        pure
        returns (GPv2Order.Data memory)
    {
        return GPv2Order.Data({
            sellToken: IERC20(sellToken),
            buyToken: IERC20(buyToken),
            receiver: receiver,
            sellAmount: sellAmount,
            buyAmount: buyAmount,
            validTo: validTo,
            appData: 0,
            feeAmount: 0,
            kind: GPv2Order.KIND_SELL,
            partiallyFillable: false,
            sellTokenBalance: GPv2Order.BALANCE_ERC20,
            buyTokenBalance: GPv2Order.BALANCE_ERC20
        });
    }
}
