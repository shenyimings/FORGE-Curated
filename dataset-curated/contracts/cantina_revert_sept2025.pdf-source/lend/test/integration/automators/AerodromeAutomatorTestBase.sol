// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import "../../../src/transformers/V3Utils.sol";
import "../../../src/utils/Constants.sol";

abstract contract AerodromeAutomatorTestBase is Test {
    uint256 constant Q64 = 2 ** 64;

    int24 constant MIN_TICK_1 = -887272;
    int24 constant MIN_TICK_10 = -887270;

    // Base network token addresses
    IERC20 constant WETH_ERC20 = IERC20(0x4200000000000000000000000000000000000006);  // WETH on Base
    IERC20 constant USDC = IERC20(0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913);  // USDC on Base
    IERC20 constant USDbC = IERC20(0xd9aAEc86B65D86f6A7B5B1b0c42FFA531710b6CA);  // USDbC (Bridged USDC) on Base
    IERC20 constant DAI = IERC20(0x50c5725949A6F0c72E6C4a641F24049A917DB0Cb);  // DAI on Base
    IERC20 constant AERO = IERC20(0x940181a94A35A4569E4529A3CDfB74e38FD98631);  // AERO on Base

    // Use a known whale address on Base for testing
    address constant WHALE_ACCOUNT = 0x3304E22DDaa22bCdC5fCa2269b418046aE7b566A;  // Example whale
    address constant OPERATOR_ACCOUNT = 0x3304E22DDaa22bCdC5fCa2269b418046aE7b566A;
    address constant WITHDRAWER_ACCOUNT = 0x3304E22DDaa22bCdC5fCa2269b418046aE7b566A;

    uint64 constant MAX_REWARD = uint64(Q64 / 400); //0.25%
    uint64 constant MAX_FEE_REWARD = uint64(Q64 / 20); //5%

    // Aerodrome Slipstream Factory on Base
    address FACTORY = 0x420DD381b31aEf6683db6B902084cB0FFECe40Da;

    // Aerodrome Slipstream NFT Position Manager on Base
    INonfungiblePositionManager constant NPM = INonfungiblePositionManager(0x827922686190790b37229fd06084350E74485b72);

    // Base network infrastructure
    address EX0x = address(0); // 0x not available on Base yet, will need alternative
    address UNIVERSAL_ROUTER = 0x198EF79F1F515F02dFE9e3115eD9fC07183f02fC; // Universal Router on Base
    address PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3; // Permit2 on Base

    // For testing, we'll create positions dynamically rather than using existing ones
    // This gives us more control over the test conditions
    
    // We'll use these addresses for test accounts
    address constant TEST_NFT_ACCOUNT = address(0x1111111111111111111111111111111111111111);
    address constant TEST_NFT_2_ACCOUNT = address(0x2222222222222222222222222222222222222222);
    address constant TEST_NFT_3_ACCOUNT = address(0x3333333333333333333333333333333333333333);
    address constant TEST_NFT_4_ACCOUNT = address(0x4444444444444444444444444444444444444444);
    address constant TEST_NFT_5_ACCOUNT = address(0x5555555555555555555555555555555555555555);
    address constant TEST_FEE_ACCOUNT = address(0x6666666666666666666666666666666666666666);
    
    // These will be set dynamically in tests
    uint256 TEST_NFT;
    uint256 TEST_NFT_2;
    uint256 TEST_NFT_2_A;
    uint256 TEST_NFT_2_B;
    uint256 TEST_NFT_3;
    uint256 TEST_NFT_4;
    uint256 TEST_NFT_5;
    
    address TEST_NFT_POOL;
    address TEST_NFT_2_POOL;
    address TEST_NFT_3_POOL;
    address TEST_NFT_4_POOL;

    uint256 baseFork;

    V3Utils v3utils;

    function _setupBase() internal {
        // Fork Base network 
        // You can use a public RPC or configure your own
        string memory BASE_RPC;
        try vm.envString("BASE_RPC_URL") returns (string memory url) {
            BASE_RPC = url;
        } catch {
            BASE_RPC = "https://mainnet.base.org";
        }
        
        // Fork at a recent block (you may want to update this)
        baseFork = vm.createFork(BASE_RPC);
        vm.selectFork(baseFork);

        v3utils = new V3Utils(NPM, EX0x, UNIVERSAL_ROUTER, PERMIT2);
    }
} 