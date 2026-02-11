// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "../BaseTest.sol";
import {IDestinationSettler} from "../../contracts/interfaces/ERC7683/IDestinationSettler.sol";
import {Intent, Route, Reward, TokenAmount, Call} from "../../contracts/types/Intent.sol";

// Simple concrete implementation for testing
contract TestDestinationSettler is IDestinationSettler {
    mapping(bytes32 => bool) public filled;

    function fill(
        bytes32 _orderId,
        bytes calldata,
        /* _originData */
        bytes calldata /* _fillerData */
    ) external payable {
        filled[_orderId] = true;
        emit OrderFilled(_orderId, msg.sender);
    }
}

contract DestinationSettlerTest is BaseTest {
    TestDestinationSettler internal destinationSettler;

    address internal filler;
    address internal recipient;

    function setUp() public override {
        super.setUp();

        filler = makeAddr("filler");
        recipient = makeAddr("recipient");

        vm.prank(deployer);
        destinationSettler = new TestDestinationSettler();

        _mintAndApprove(creator, MINT_AMOUNT);
        _mintAndApprove(filler, MINT_AMOUNT);
        _fundUserNative(creator, 10 ether);
        _fundUserNative(filler, 10 ether);
    }

    function testFillOrder() public {
        Intent memory destIntent = intent;
        destIntent.destination = uint64(block.chainid); // Current chain as destination

        bytes memory originData = abi.encode(destIntent);
        bytes memory fillerData = abi.encode(filler, recipient, "");

        bytes32 orderId = keccak256("test-order");

        vm.prank(filler);
        destinationSettler.fill(orderId, originData, fillerData);

        // Verify order was filled
        assertTrue(destinationSettler.filled(orderId));
    }

    function testFillOrderEmitsEvent() public {
        Intent memory destIntent = intent;
        destIntent.destination = uint64(block.chainid);

        bytes memory originData = abi.encode(destIntent);
        bytes memory fillerData = abi.encode(filler, recipient, "");

        bytes32 orderId = keccak256("test-order");

        _expectEmit();
        emit IDestinationSettler.OrderFilled(orderId, filler);

        vm.prank(filler);
        destinationSettler.fill(orderId, originData, fillerData);
    }

    function testFillOrderWithValue() public {
        Intent memory destIntent = intent;
        destIntent.destination = uint64(block.chainid);

        bytes memory originData = abi.encode(destIntent);
        bytes memory fillerData = abi.encode(filler, recipient, "");

        bytes32 orderId = keccak256("test-order");

        vm.prank(filler);
        destinationSettler.fill{value: 1 ether}(
            orderId,
            originData,
            fillerData
        );

        assertTrue(destinationSettler.filled(orderId));
    }
}
