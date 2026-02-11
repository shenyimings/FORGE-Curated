// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import "forge-std/Test.sol";
import {CapyfiAggregatorV3} from "src/contracts/PriceOracle/CapyfiAggregatorV3.sol";

contract CapyfiAggregatorV3Test is Test {
    CapyfiAggregatorV3 public aggregator;
    
    address public owner;
    address public authorizedUser;
    address public unauthorizedUser;
    
    uint8 constant DECIMALS = 8;
    string constant DESCRIPTION = "BTC/USD Price Feed";
    uint256 constant VERSION = 1;
    int256 constant INITIAL_PRICE = 50000e8; // $50,000 with 8 decimals
    
    event AnswerUpdated(int256 indexed current, uint256 indexed roundId, uint256 updatedAt);
    event NewRound(uint256 indexed roundId, address indexed startedBy, uint256 startedAt);
    event AuthorizedAddressAdded(address indexed addr);
    event AuthorizedAddressRemoved(address indexed addr);

    function setUp() public {
        owner = makeAddr("owner");
        authorizedUser = makeAddr("authorizedUser");
        unauthorizedUser = makeAddr("unauthorizedUser");
        
        vm.prank(owner);
        aggregator = new CapyfiAggregatorV3(
            DECIMALS,
            DESCRIPTION,
            VERSION,
            INITIAL_PRICE
        );
    }

    // ============ Constructor Tests ============
    
    function testConstructorValidPrice() public {
        int256 price = 3000e8;
        vm.prank(owner);
        CapyfiAggregatorV3 newAggregator = new CapyfiAggregatorV3(18, "ETH/USD", 2, price);
        
        assertEq(newAggregator.decimals(), 18);
        assertEq(newAggregator.description(), "ETH/USD");
        assertEq(newAggregator.version(), 2);
        assertEq(newAggregator.latestAnswer(), price);
        assertEq(newAggregator.latestRound(), 1);
    }
    
    function testConstructorInvalidPriceZero() public {
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(CapyfiAggregatorV3.InvalidPrice.selector, int256(0)));
        new CapyfiAggregatorV3(DECIMALS, DESCRIPTION, VERSION, 0);
    }
    
    function testConstructorInvalidPriceNegative() public {
        int256 negativePrice = -1000;
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(CapyfiAggregatorV3.InvalidPrice.selector, negativePrice));
        new CapyfiAggregatorV3(DECIMALS, DESCRIPTION, VERSION, negativePrice);
    }

    // ============ Access Control Tests ============
    
    function testAddAuthorizedAddress() public {
        vm.prank(owner);
        vm.expectEmit(true, false, false, false);
        emit AuthorizedAddressAdded(authorizedUser);
        aggregator.addAuthorizedAddress(authorizedUser);
        
        assertTrue(aggregator.authorizedAddresses(authorizedUser));
    }
    
    function testAddAuthorizedAddressZeroAddress() public {
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(CapyfiAggregatorV3.InvalidAddress.selector, address(0)));
        aggregator.addAuthorizedAddress(address(0));
    }
    
    function testAddAuthorizedAddressUnauthorized() public {
        vm.prank(unauthorizedUser);
        vm.expectRevert("Ownable: caller is not the owner");
        aggregator.addAuthorizedAddress(authorizedUser);
    }
    
    function testRemoveAuthorizedAddress() public {
        // First add the address
        vm.prank(owner);
        aggregator.addAuthorizedAddress(authorizedUser);
        assertTrue(aggregator.authorizedAddresses(authorizedUser));
        
        // Then remove it
        vm.prank(owner);
        vm.expectEmit(true, false, false, false);
        emit AuthorizedAddressRemoved(authorizedUser);
        aggregator.removeAuthorizedAddress(authorizedUser);
        
        assertFalse(aggregator.authorizedAddresses(authorizedUser));
    }

    function testRemoveNonAuthorizedAddress() public {
        // Try to remove an address that was never authorized
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(CapyfiAggregatorV3.InvalidAddress.selector, unauthorizedUser));
        aggregator.removeAuthorizedAddress(unauthorizedUser);
    }

    // ============ Price Update Tests ============
    
    function testUpdateAnswerAsOwner() public {
        int256 newPrice = 51000e8;
        
        vm.prank(owner);
        vm.expectEmit(true, true, false, true);
        emit AnswerUpdated(newPrice, 2, block.timestamp);
        aggregator.updateAnswer(newPrice);
        
        assertEq(aggregator.latestAnswer(), newPrice);
        assertEq(aggregator.latestRound(), 2);
    }
    
    function testUpdateAnswerAsAuthorizedUser() public {
        // First authorize the user
        vm.prank(owner);
        aggregator.addAuthorizedAddress(authorizedUser);
        
        int256 newPrice = 52000e8;
        vm.prank(authorizedUser);
        aggregator.updateAnswer(newPrice);
        
        assertEq(aggregator.latestAnswer(), newPrice);
    }
    
    function testUpdateAnswerUnauthorized() public {
        int256 newPrice = 53000e8;
        
        vm.prank(unauthorizedUser);
        vm.expectRevert(abi.encodeWithSelector(CapyfiAggregatorV3.UnauthorizedCaller.selector, unauthorizedUser));
        aggregator.updateAnswer(newPrice);
    }
    
    function testUpdateAnswerInvalidPriceZero() public {
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(CapyfiAggregatorV3.InvalidPrice.selector, int256(0)));
        aggregator.updateAnswer(0);
    }
    
    function testUpdateAnswerInvalidPriceNegative() public {
        int256 negativePrice = -5000;
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(CapyfiAggregatorV3.InvalidPrice.selector, negativePrice));
        aggregator.updateAnswer(negativePrice);
    }

    // ============ Round Data Tests ============
    
    function testGetRoundDataValid() public view {
        (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) = 
            aggregator.getRoundData(1);
        
        assertEq(roundId, 1);
        assertEq(answer, INITIAL_PRICE);
        assertGt(startedAt, 0);
        assertGt(updatedAt, 0);
        assertEq(answeredInRound, 1);
    }
    
    function testGetRoundDataInvalidRoundIdZero() public {
        vm.expectRevert(abi.encodeWithSelector(CapyfiAggregatorV3.RoundNotFound.selector, uint80(0)));
        aggregator.getRoundData(0);
    }
    
    function testGetRoundDataInvalidRoundIdTooHigh() public {
        uint80 invalidRoundId = 999;
        vm.expectRevert(abi.encodeWithSelector(CapyfiAggregatorV3.RoundNotFound.selector, invalidRoundId));
        aggregator.getRoundData(invalidRoundId);
    }
    
    function testLatestRoundData() public view {
        (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) = 
            aggregator.latestRoundData();
        
        assertEq(roundId, 1);
        assertEq(answer, INITIAL_PRICE);
        assertGt(startedAt, 0);
        assertGt(updatedAt, 0);
        assertEq(answeredInRound, 1);
    }

    // ============ Multiple Rounds Tests ============
    
    function testMultipleRounds() public {
        int256[] memory prices = new int256[](3);
        prices[0] = 51000e8;
        prices[1] = 52000e8;
        prices[2] = 53000e8;
        
        for (uint256 i = 0; i < prices.length; i++) {
            vm.prank(owner);
            aggregator.updateAnswer(prices[i]);
            
            assertEq(aggregator.latestAnswer(), prices[i]);
            assertEq(aggregator.latestRound(), i + 2); // +2 because round 1 is initial
            
            (uint80 currentRoundId, int256 currentAnswer, , , uint80 currentAnsweredInRound) = 
                aggregator.getRoundData(uint80(i + 2));
            assertEq(currentRoundId, i + 2);
            assertEq(currentAnswer, prices[i]);
            assertEq(currentAnsweredInRound, i + 2);
        }
        
        // Verify we can still access old rounds
        (uint80 firstRoundId, int256 firstAnswer, , , ) = aggregator.getRoundData(1);
        assertEq(firstRoundId, 1);
        assertEq(firstAnswer, INITIAL_PRICE);
    }

    // ============ View Function Tests ============
    
    function testDecimals() public view {
        assertEq(aggregator.decimals(), DECIMALS);
    }
    
    function testDescription() public view {
        assertEq(aggregator.description(), DESCRIPTION);
    }
    
    function testVersion() public view {
        assertEq(aggregator.version(), VERSION);
    }
    
    function testLatestRound() public view {
        assertEq(aggregator.latestRound(), 1);
    }
    
    function testLatestAnswer() public {
        assertEq(aggregator.latestAnswer(), INITIAL_PRICE);
        
        int256 newPrice = 55000e8;
        vm.prank(owner);
        aggregator.updateAnswer(newPrice);
        assertEq(aggregator.latestAnswer(), newPrice);
    }
    
    function testLatestTimestamp() public {
        uint256 initialTimestamp = aggregator.latestTimestamp();
        assertGt(initialTimestamp, 0);
        
        vm.warp(block.timestamp + 3600); // Fast forward 1 hour
        vm.prank(owner);
        aggregator.updateAnswer(55000e8);
        
        uint256 newTimestamp = aggregator.latestTimestamp();
        assertGt(newTimestamp, initialTimestamp);
        assertEq(newTimestamp, block.timestamp);
    }

    // ============ Event Tests ============
    
    function testUpdateAnswerEvents() public {
        int256 newPrice = 60000e8;
        uint256 expectedRoundId = 2;
        
        vm.prank(owner);
        vm.expectEmit(true, true, false, true);
        emit AnswerUpdated(newPrice, expectedRoundId, block.timestamp);
        vm.expectEmit(true, true, false, true);
        emit NewRound(expectedRoundId, owner, block.timestamp);
        
        aggregator.updateAnswer(newPrice);
    }

    // ============ Fuzz Tests ============
    
    function testFuzzValidPriceUpdates(int256 price) public {
        vm.assume(price > 0);
        vm.assume(price < type(int256).max);
        
        vm.prank(owner);
        aggregator.updateAnswer(price);
        
        assertEq(aggregator.latestAnswer(), price);
    }
    
    function testFuzzInvalidPriceUpdates(int256 price) public {
        vm.assume(price <= 0);
        
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(CapyfiAggregatorV3.InvalidPrice.selector, price));
        aggregator.updateAnswer(price);
    }
    
    function testFuzzGetRoundData(uint80 roundId) public {
        // Test with current valid range (only round 1 exists initially)
        if (roundId == 1) {
            (uint80 returnedRoundId, int256 answer, , , ) = aggregator.getRoundData(roundId);
            assertEq(returnedRoundId, 1);
            assertEq(answer, INITIAL_PRICE);
        } else {
            vm.expectRevert(abi.encodeWithSelector(CapyfiAggregatorV3.RoundNotFound.selector, roundId));
            aggregator.getRoundData(roundId);
        }
    }

    // ============ Integration Tests ============
    
    function testCompleteWorkflow() public {
        // 1. Initial state verification
        assertEq(aggregator.decimals(), DECIMALS);
        assertEq(aggregator.version(), VERSION);
        assertEq(aggregator.latestRound(), 1);
        assertEq(aggregator.latestAnswer(), INITIAL_PRICE);
        
        // 2. Add authorized user
        vm.prank(owner);
        aggregator.addAuthorizedAddress(authorizedUser);
        
        // 3. Update price from authorized user
        int256 price2 = 55000e8;
        vm.prank(authorizedUser);
        aggregator.updateAnswer(price2);
        
        // 4. Update price from owner
        int256 price3 = 60000e8;
        vm.prank(owner);
        aggregator.updateAnswer(price3);
        
        // 5. Verify all rounds are accessible
        (uint80 roundId1, int256 answer1, , , ) = aggregator.getRoundData(1);
        assertEq(roundId1, 1);
        assertEq(answer1, INITIAL_PRICE);
        
        (uint80 roundId2, int256 answer2, , , ) = aggregator.getRoundData(2);
        assertEq(roundId2, 2);
        assertEq(answer2, price2);
        
        (uint80 roundId3, int256 answer3, , , ) = aggregator.getRoundData(3);
        assertEq(roundId3, 3);
        assertEq(answer3, price3);
        
        // 6. Verify latest data
        assertEq(aggregator.latestRound(), 3);
        assertEq(aggregator.latestAnswer(), price3);
        
        // 7. Remove authorization and verify access denied
        vm.prank(owner);
        aggregator.removeAuthorizedAddress(authorizedUser);
        
        vm.prank(authorizedUser);
        vm.expectRevert(abi.encodeWithSelector(CapyfiAggregatorV3.UnauthorizedCaller.selector, authorizedUser));
        aggregator.updateAnswer(65000e8);
    }

    // ============ Edge Case Tests ============
    
    function testTimestampAccuracy() public {
        uint256 beforeUpdate = block.timestamp;
        
        vm.prank(owner);
        aggregator.updateAnswer(51000e8);
        
        uint256 latestTimestamp = aggregator.latestTimestamp();
        assertEq(latestTimestamp, beforeUpdate);
        
        (, , uint256 startedAt, uint256 updatedAt, ) = aggregator.latestRoundData();
        assertEq(startedAt, beforeUpdate);
        assertEq(updatedAt, beforeUpdate);
    }

    function testGetAnswer() public {
        // Test getting answer for round 1 (initial round)
        assertEq(aggregator.getAnswer(1), INITIAL_PRICE);
        
        // Add a new round and test
        int256 newPrice = 55000e8;
        vm.prank(owner);
        aggregator.updateAnswer(newPrice);
        
        assertEq(aggregator.getAnswer(2), newPrice);
        assertEq(aggregator.getAnswer(1), INITIAL_PRICE); // Old round still accessible
    }
    
    function testGetAnswerInvalidRound() public {
        vm.expectRevert(abi.encodeWithSelector(CapyfiAggregatorV3.RoundNotFound.selector, uint80(0)));
        aggregator.getAnswer(0);
        
        vm.expectRevert(abi.encodeWithSelector(CapyfiAggregatorV3.RoundNotFound.selector, uint80(999)));
        aggregator.getAnswer(999);
    }
    
    function testGetTimestamp() public {
        // Test getting timestamp for round 1
        uint256 timestamp1 = aggregator.getTimestamp(1);
        assertGt(timestamp1, 0);
        
        // Add a new round and test
        vm.warp(block.timestamp + 3600); // Fast forward 1 hour
        vm.prank(owner);
        aggregator.updateAnswer(55000e8);
        
        uint256 timestamp2 = aggregator.getTimestamp(2);
        assertGt(timestamp2, timestamp1);
        assertEq(timestamp2, block.timestamp);
    }
    
    function testGetTimestampInvalidRound() public {
        vm.expectRevert(abi.encodeWithSelector(CapyfiAggregatorV3.RoundNotFound.selector, uint80(0)));
        aggregator.getTimestamp(0);
        
        vm.expectRevert(abi.encodeWithSelector(CapyfiAggregatorV3.RoundNotFound.selector, uint80(999)));
        aggregator.getTimestamp(999);
    }
} 