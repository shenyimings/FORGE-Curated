// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.23;

import {PriceFeedInfo} from "../../interfaces/Types.sol";

import {Test} from "forge-std/Test.sol";
import {PriceFeedStore} from "../../instance/PriceFeedStore.sol";
import {IPriceFeedStore} from "../../interfaces/IPriceFeedStore.sol";
import {IAddressProvider} from "../../interfaces/IAddressProvider.sol";
import {MockPriceFeed} from "../mocks/MockPriceFeed.sol";
import {AP_INSTANCE_MANAGER_PROXY, NO_VERSION_CONTROL} from "../../libraries/ContractLiterals.sol";
import {ImmutableOwnableTrait} from "../../traits/ImmutableOwnableTrait.sol";
import {
    ZeroAddressException,
    StalePriceException,
    IncorrectPriceException,
    IncorrectPriceFeedException
} from "@gearbox-protocol/core-v3/contracts/interfaces/IExceptions.sol";

contract PriceFeedStoreTest is Test {
    PriceFeedStore public store;
    address public owner;
    address public token;
    MockPriceFeed public priceFeed;
    IAddressProvider public addressProvider;

    function setUp() public {
        owner = makeAddr("owner");
        token = makeAddr("token");
        priceFeed = new MockPriceFeed();

        vm.mockCall(
            address(addressProvider),
            abi.encodeWithSignature(
                "getAddressOrRevert(bytes32,uint256)", AP_INSTANCE_MANAGER_PROXY, NO_VERSION_CONTROL
            ),
            abi.encode(owner)
        );

        store = new PriceFeedStore(address(addressProvider));
    }

    /// @notice Test basic price feed addition flow
    function test_PFS_01_addPriceFeed_works() public {
        uint32 stalenessPeriod = 3600;

        vm.prank(owner);
        store.addPriceFeed(address(priceFeed), stalenessPeriod);

        // Verify price feed was added correctly
        assertEq(store.getStalenessPeriod(address(priceFeed)), stalenessPeriod);

        // Get price feed info
        PriceFeedInfo memory priceFeedInfo = store.priceFeedInfo(address(priceFeed));
        store.priceFeedInfo(address(priceFeed));

        // Verify all parameters were set correctly
        assertEq(priceFeedInfo.author, owner);
        assertEq(priceFeedInfo.priceFeedType, "MOCK_PRICE_FEED");
        assertEq(priceFeedInfo.stalenessPeriod, stalenessPeriod);
        assertEq(priceFeedInfo.version, 1);

        // Verify price feed is in known list
        address[] memory knownPriceFeeds = store.getKnownPriceFeeds();
        assertEq(knownPriceFeeds.length, 1);
        assertEq(knownPriceFeeds[0], address(priceFeed));
    }

    /// @notice Test that only owner can add price feeds
    function test_PFS_02_addPriceFeed_reverts_if_not_owner() public {
        address notOwner = makeAddr("notOwner");
        vm.prank(notOwner);
        vm.expectRevert(abi.encodeWithSignature("CallerIsNotOwnerException(address)", notOwner));
        store.addPriceFeed(address(priceFeed), 3600);
    }

    /// @notice Test that zero address price feed cannot be added
    function test_PFS_03_addPriceFeed_reverts_on_zero_address() public {
        vm.prank(owner);
        vm.expectRevert(ZeroAddressException.selector);
        store.addPriceFeed(address(0), 3600);
    }

    /// @notice Test duplicate price feed addition is prevented
    function test_PFS_04_addPriceFeed_reverts_on_duplicate() public {
        vm.startPrank(owner);
        store.addPriceFeed(address(priceFeed), 3600);

        vm.expectRevert(
            abi.encodeWithSelector(IPriceFeedStore.PriceFeedAlreadyAddedException.selector, address(priceFeed))
        );
        store.addPriceFeed(address(priceFeed), 3600);
        vm.stopPrank();
    }

    /// @notice Test staleness period validation
    function test_PFS_05_addPriceFeed_validates_staleness() public {
        MockPriceFeed stalePriceFeed = new MockPriceFeed();
        stalePriceFeed.setLastUpdateTime(block.timestamp);

        vm.warp(block.timestamp + 7200);

        vm.prank(owner);
        vm.expectRevert(StalePriceException.selector);
        store.addPriceFeed(address(stalePriceFeed), 3600);
    }

    /// @notice Test price feed allowance for tokens
    function test_PFS_06_allowPriceFeed_works() public {
        vm.startPrank(owner);
        store.addPriceFeed(address(priceFeed), 3600);
        store.allowPriceFeed(token, address(priceFeed));
        vm.stopPrank();

        assertTrue(store.isAllowedPriceFeed(token, address(priceFeed)));
    }

    /// @notice Test only owner can allow price feeds
    function test_PFS_07_allowPriceFeed_reverts_if_not_owner() public {
        vm.prank(owner);
        store.addPriceFeed(address(priceFeed), 3600);

        address notOwner = makeAddr("notOwner");
        vm.prank(notOwner);
        vm.expectRevert(abi.encodeWithSignature("CallerIsNotOwnerException(address)", notOwner));
        store.allowPriceFeed(token, address(priceFeed));
    }

    /// @notice Test unknown price feeds cannot be allowed
    function test_PFS_08_allowPriceFeed_reverts_on_unknown_feed() public {
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(IPriceFeedStore.PriceFeedNotKnownException.selector, address(priceFeed)));
        store.allowPriceFeed(token, address(priceFeed));
    }

    /// @notice Test price feed forbidding
    function test_PFS_09_forbidPriceFeed_works() public {
        vm.startPrank(owner);
        store.addPriceFeed(address(priceFeed), 3600);
        store.allowPriceFeed(token, address(priceFeed));
        store.forbidPriceFeed(token, address(priceFeed));
        vm.stopPrank();

        assertFalse(store.isAllowedPriceFeed(token, address(priceFeed)));
    }

    /// @notice Test only owner can forbid price feeds
    function test_PFS_10_forbidPriceFeed_reverts_if_not_owner() public {
        vm.startPrank(owner);
        store.addPriceFeed(address(priceFeed), 3600);
        store.allowPriceFeed(token, address(priceFeed));
        vm.stopPrank();

        address notOwner = makeAddr("notOwner");
        vm.prank(notOwner);
        vm.expectRevert(abi.encodeWithSignature("CallerIsNotOwnerException(address)", notOwner));
        store.forbidPriceFeed(token, address(priceFeed));
    }

    /// @notice Test staleness period updates
    function test_PFS_11_setStalenessPeriod_works() public {
        vm.startPrank(owner);
        store.addPriceFeed(address(priceFeed), 3600);
        store.setStalenessPeriod(address(priceFeed), 7200);
        vm.stopPrank();

        assertEq(store.getStalenessPeriod(address(priceFeed)), 7200);
    }

    /// @notice Test staleness period validation on update
    function test_PFS_12_setStalenessPeriod_validates_staleness() public {
        vm.startPrank(owner);
        store.addPriceFeed(address(priceFeed), 3600);

        priceFeed.setLastUpdateTime(block.timestamp);
        vm.warp(block.timestamp + 7200);

        vm.expectRevert(StalePriceException.selector);
        store.setStalenessPeriod(address(priceFeed), 3601);
        vm.stopPrank();
    }

    /// @notice Test token list management
    function test_PFS_13_maintains_token_list() public {
        vm.startPrank(owner);
        store.addPriceFeed(address(priceFeed), 3600);
        store.allowPriceFeed(token, address(priceFeed));
        vm.stopPrank();

        address[] memory knownTokens = store.getKnownTokens();
        assertEq(knownTokens.length, 1);
        assertEq(knownTokens[0], token);
    }

    /// @notice Test multiple price feeds per token
    function test_PFS_14_allows_multiple_feeds_per_token() public {
        MockPriceFeed priceFeed2 = new MockPriceFeed();

        vm.startPrank(owner);
        store.addPriceFeed(address(priceFeed), 3600);
        store.addPriceFeed(address(priceFeed2), 3600);
        store.allowPriceFeed(token, address(priceFeed));
        store.allowPriceFeed(token, address(priceFeed2));
        vm.stopPrank();

        address[] memory feeds = store.getPriceFeeds(token);
        assertEq(feeds.length, 2);
        assertTrue(store.isAllowedPriceFeed(token, address(priceFeed)));
        assertTrue(store.isAllowedPriceFeed(token, address(priceFeed2)));
    }
}
