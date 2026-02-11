pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {ERC4626Feed} from "../src/ERC4626Feed.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/interfaces/IERC20Metadata.sol";
import {MockERC4626} from "./mocks/MockERC4626.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

contract ERC4626FeedTest is Test {
    ERC4626Feed public feed;
    MockERC4626 public vault;
    MockERC20 public asset;

    uint8 constant DECIMALS = 18;
    string constant SYMBOL = "TEST";
    string constant NAME = "Test Token";

    function setUp() public {
        // Deploy mock tokens
        asset = new MockERC20(NAME, SYMBOL, DECIMALS);
        vault = new MockERC4626(asset, "Vault Test", "vTEST");
        feed = new ERC4626Feed(vault, 0); // Use asset's decimals
    }

    function testConstructor() public {
        assertEq(address(feed.vault()), address(vault));
        assertEq(address(feed.token()), address(asset));
        assertEq(feed.decimals(), DECIMALS);
        assertEq(feed.description(), string.concat(vault.symbol(), " / ", asset.symbol()));
        assertEq(feed.version(), 1);
    }

    function testConstructorWithCustomDecimals() public {
        uint8 customDecimals = 8;
        ERC4626Feed customFeed = new ERC4626Feed(vault, customDecimals);
        assertEq(customFeed.decimals(), customDecimals);
    }

    function testGetPrice() public {
        uint256 amount = 2e18; // 2 assets per share
        uint256 shares = 1e18;
        
        // Mock vault conversion rate - 1 share = 2 assets
        vault.setConvertToAssets(shares, amount);
        
        // Price should be 2e18 (2 assets per share)
        assertEq(feed.getPrice(), 2e18);
    }

    function testLatestRoundData() public {
        uint256 amount = 2e18; // 2 assets per share
        uint256 shares = 1e18;
        
        // Mock vault conversion rate - 1 share = 2 assets
        vault.setConvertToAssets(shares, amount);
        
        (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        ) = feed.latestRoundData();

        assertEq(roundId, 1);
        assertEq(answer, int256(2e18));
        assertEq(startedAt, block.timestamp);
        assertEq(updatedAt, block.timestamp);
        assertEq(answeredInRound, 1);
    }

    function testGetRoundData() public {
        uint256 amount = 2e18; // 2 assets per share
        uint256 shares = 1e18;
        
        // Mock vault conversion rate - 1 share = 2 assets
        vault.setConvertToAssets(shares, amount);
        
        (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        ) = feed.getRoundData(1);

        assertEq(roundId, 1);
        assertEq(answer, int256(2e18));
        assertEq(startedAt, block.timestamp);
        assertEq(updatedAt, block.timestamp);
        assertEq(answeredInRound, 1);
    }

    function testFuzzGetPrice(uint256 amount) public {
        vm.assume(amount > 0);
        vm.assume(amount <= type(uint128).max); // Prevent overflow in multiplication
        
        uint256 shares = 1e18;
        
        // Mock vault conversion rate
        vault.setConvertToAssets(shares, amount);
        
        // The price should be the raw conversion rate since we're using the same decimals
        assertEq(feed.getPrice(), amount);
    }

    function testDifferentDecimals() public {
        uint8 customDecimals = 8;
        ERC4626Feed customFeed = new ERC4626Feed(vault, customDecimals);
        
        uint256 amount = 2e18; // 2 assets per share
        uint256 shares = 1e18;
        
        // Mock vault conversion rate - 1 share = 2 assets
        vault.setConvertToAssets(shares, amount);
        
        // Price should be 2e8 (2 * 10^8) since we're converting from 18 decimals to 8
        uint256 expectedPrice = (amount * 10**customDecimals) / 10**DECIMALS;
        assertEq(customFeed.getPrice(), expectedPrice);
    }
} 