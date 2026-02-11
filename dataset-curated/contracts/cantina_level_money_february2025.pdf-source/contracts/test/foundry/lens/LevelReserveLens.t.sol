// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.8.21;

import {Test, console2} from "forge-std/Test.sol";
import {Utils} from "../../utils/Utils.sol";

import {LevelReserveLens} from "../../../src/lens/LevelReserveLens.sol";

import {Initializable} from "@openzeppelin-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin-upgradeable/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ERC1967Utils} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";
import {Upgrades} from "@openzeppelin-upgrades/src/Upgrades.sol";

import {IERC20Metadata} from "@openzeppelin/contracts/interfaces/IERC20Metadata.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";

contract LevelReserveLens2 is Initializable, OwnableUpgradeable, UUPSUpgradeable {
    address public constant karakReserveManager = 0x329F91FE82c1799C3e089FabE9D3A7efDC2D3151;
    address public constant symbioticReserveManager = 0x21C937d436f2D86859ce60311290a8072368932D;

    constructor() {
        _disableInitializers();
    }

    function initialize(address admin) public initializer {
        __Ownable_init(admin);
        __UUPSUpgradeable_init();
    }

    function getReserveValue(address token) public view returns (uint256) {
        return 1337;
    }

    // Try changing function ordering; this should not affect the upgrade
    function getRedeemPrice(IERC20Metadata collateral) public view returns (uint256) {
        return 7331;
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}
}

contract LevelReserveLensTest is Test {
    Utils internal utils;

    address internal owner;
    address internal random;
    uint256 internal ownerPrivateKey;
    uint256 internal randomPrivateKey;

    LevelReserveLens internal lens;
    ERC1967Proxy internal proxy;

    IERC20Metadata internal constant usdc = IERC20Metadata(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    IERC20Metadata internal constant usdt = IERC20Metadata(0xdAC17F958D2ee523a2206206994597C13D831ec7);
    IERC20Metadata internal constant lvlusd = IERC20Metadata(0x7C1156E515aA1A2E851674120074968C905aAF37);

    function setUp() public {
        utils = new Utils();

        ownerPrivateKey = 0xA11CE;
        randomPrivateKey = 0x1CE;

        owner = vm.addr(ownerPrivateKey);
        random = vm.addr(randomPrivateKey);

        // Setup forked environment.
        string memory rpcKey = "MAINNET_RPC_URL";
        utils.startFork(rpcKey, 21597570);

        vm.startPrank(owner);

        LevelReserveLens implementation = new LevelReserveLens();

        proxy = new ERC1967Proxy(
            address(implementation), abi.encodeWithSelector(LevelReserveLens.initialize.selector, owner)
        );

        lens = LevelReserveLens(address(proxy));
        vm.stopPrank();
    }

    function testInitialization() public {
        assertEq(lens.owner(), owner, "Owner should be admin");
    }

    function testCannotReinitialize() public {
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        lens.initialize(owner);
    }

    function testUpgrade() public {
        vm.startPrank(owner);
        LevelReserveLens2 implementationV2 = new LevelReserveLens2();

        lens.upgradeToAndCall(address(implementationV2), "");

        // Mock implementation will always return 1337 no matter the address.
        uint256 reserves = lens.getReserveValue(address(0));

        assertEq(
            Upgrades.getImplementationAddress(address(proxy)), address(implementationV2), "Implementation should be V2"
        );
        assertEq(lens.owner(), owner, "Owner should be admin");
        assertEq(reserves, 1337);

        vm.expectRevert();
        lens.getMintPrice(usdc);

        assertEq(lens.getRedeemPrice(usdc), 7331);
        // Ensure that constants don't change when upgrades change constant ordering
        assertEq(lens.karakReserveManager(), 0x329F91FE82c1799C3e089FabE9D3A7efDC2D3151);
        vm.stopPrank();

        vm.startPrank(random);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, random));
        lens.upgradeToAndCall(
            address(implementationV2), abi.encodeWithSelector(LevelReserveLens2.initialize.selector, random)
        );

        vm.expectRevert(Initializable.InvalidInitialization.selector);
        lens.initialize(random);
    }

    function test__initialize_fails() public {
        vm.startPrank(owner);
        LevelReserveLens implementation = new LevelReserveLens();

        vm.expectRevert(Initializable.InvalidInitialization.selector);
        implementation.initialize(owner);
    }

    function testCannotUpgradeUnauthorized() public {
        vm.startPrank(random);
        LevelReserveLens implementationV2 = new LevelReserveLens();

        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, random));
        lens.upgradeToAndCall(
            address(implementationV2), abi.encodeWithSelector(LevelReserveLens.initialize.selector, owner)
        );
    }

    function test_getUsdcReserves_succeeds() public {
        vm.rollFork(21718875);
        vm.startPrank(owner);

        LevelReserveLens implementation = new LevelReserveLens();

        proxy = new ERC1967Proxy(
            address(implementation), abi.encodeWithSelector(LevelReserveLens.initialize.selector, owner)
        );

        lens = LevelReserveLens(address(proxy));
        vm.stopPrank();

        uint256 usdcReserves = lens.getReserves(address(usdc));

        uint256 usdcReserveAmount = 19145827151545 + 179169754211;
        uint256 amountInEigenStrategy = 0;
        uint256 amountInSymbioticStrategy = 10;

        uint256 total = usdcReserveAmount + amountInEigenStrategy + amountInSymbioticStrategy;
        uint256 adjustedTotal = lens.safeAdjustForDecimals(total, usdc.decimals(), 18);

        assertEq(usdcReserves, adjustedTotal);
    }

    function test_getUsdtReserves_succeeds() public {
        vm.rollFork(21718875);
        vm.startPrank(owner);

        LevelReserveLens implementation = new LevelReserveLens();

        proxy = new ERC1967Proxy(
            address(implementation), abi.encodeWithSelector(LevelReserveLens.initialize.selector, owner)
        );

        lens = LevelReserveLens(address(proxy));
        vm.stopPrank();

        uint256 usdtReserves = lens.getReserves(address(usdt));

        uint256 usdtReserveAmount = 5798076589218 + 56667618;
        uint256 amountInEigenStrategy = 1000000;
        uint256 amountInSymbioticStrategy = 0;

        uint256 total = usdtReserveAmount + amountInEigenStrategy + amountInSymbioticStrategy;
        uint256 adjustedTotal = lens.safeAdjustForDecimals(total, usdt.decimals(), 18);

        assertEq(usdtReserves, adjustedTotal);
    }

    function test_getAllReserves_succeeds() public {
        vm.rollFork(21718875);
        vm.startPrank(owner);

        LevelReserveLens implementation = new LevelReserveLens();

        proxy = new ERC1967Proxy(
            address(implementation), abi.encodeWithSelector(LevelReserveLens.initialize.selector, owner)
        );

        lens = LevelReserveLens(address(proxy));
        vm.stopPrank();

        uint256 adjustedUsdtReserves = lens.getReserveValue(address(usdt));
        uint256 adjustedUsdcReserves = lens.getReserveValue(address(usdc));

        uint256 allReserves = lens.getReserveValue();

        assertEq(allReserves, adjustedUsdtReserves + adjustedUsdcReserves);
        // Ensure lvlUSD supply is within 1% of reserves
        assertApproxEqRel(allReserves, lvlusd.totalSupply(), 0.01e18);
    }

    function test_getReservePrice() public {
        vm.rollFork(21718875);
        vm.startPrank(owner);

        LevelReserveLens implementation = new LevelReserveLens();

        proxy = new ERC1967Proxy(
            address(implementation), abi.encodeWithSelector(LevelReserveLens.initialize.selector, owner)
        );

        lens = LevelReserveLens(address(proxy));
        vm.stopPrank();

        uint256 getReservePrice = lens.getReservePrice();
        assertEq(getReservePrice, 1e18);
    }

    function test_getReservePrice_succeedsWhenPriceIsUnderReserves() public {
        vm.rollFork(21718875);
        vm.startPrank(owner);

        LevelReserveLens implementation = new LevelReserveLens();

        proxy = new ERC1967Proxy(
            address(implementation), abi.encodeWithSelector(LevelReserveLens.initialize.selector, owner)
        );

        lens = LevelReserveLens(address(proxy));
        vm.stopPrank();

        uint256 realSupply = lvlusd.totalSupply();
        uint256 mockInsolventSupply = (realSupply * 1.02e18) / 1e18;

        vm.mockCall(
            address(lvlusd), abi.encodeWithSelector(IERC20.totalSupply.selector), abi.encode(mockInsolventSupply)
        );
        uint256 reservePrice = lens.getReservePrice();

        uint256 expectedReservePrice = (lens.getReserveValue() * 1e18) / mockInsolventSupply;

        assertEq(reservePrice, expectedReservePrice);
    }

    function test_getDai_fails() public {
        address dai = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
        vm.expectRevert("Invalid collateral token");
        lens.getReserves(dai);
    }

    function test_getMintPrice__succeeds_whenCollateralUnderPeg() public {
        uint256 lvlUsdPriceWithUsdc = lens.getMintPrice(usdc);
        uint256 lvlUsdPriceWithUsdt = lens.getMintPrice(usdt);

        // USDC Price at this block was $0.99996033
        assertEq(lvlUsdPriceWithUsdc, 999960330000000000);

        // USDT Price at this block was $0.9999
        assertEq(lvlUsdPriceWithUsdt, 999900000000000000);
    }

    function test_getRedeemPrice__succeeds_whenCollateralUnderPeg() public {
        uint256 usdcPrice = lens.getRedeemPrice(usdc);
        uint256 usdtPrice = lens.getRedeemPrice(usdt);

        assertEq(usdcPrice, 1e6);
        assertEq(usdtPrice, 1e6);
    }

    function test_getMintPrice__succeeds_whenCollateralOverPeg() public {
        vm.rollFork(21570930);

        vm.startPrank(owner);

        LevelReserveLens implementation = new LevelReserveLens();

        proxy = new ERC1967Proxy(
            address(implementation), abi.encodeWithSelector(LevelReserveLens.initialize.selector, owner)
        );

        lens = LevelReserveLens(address(proxy));
        vm.stopPrank();

        uint256 lvlUsdPriceWithUsdt = lens.getMintPrice(usdt);
        assertEq(lvlUsdPriceWithUsdt, 1 ether);
    }

    function test_getRedeemPrice__succeeds_whenCollateralOverPeg() public {
        vm.rollFork(21570930);

        vm.startPrank(owner);

        LevelReserveLens implementation = new LevelReserveLens();

        proxy = new ERC1967Proxy(
            address(implementation), abi.encodeWithSelector(LevelReserveLens.initialize.selector, owner)
        );

        lens = LevelReserveLens(address(proxy));
        vm.stopPrank();

        uint256 usdtPrice = lens.getRedeemPrice(usdt);

        // USDT Price at this block was $1.00009
        assertEq(usdtPrice, 999910);
    }
}
