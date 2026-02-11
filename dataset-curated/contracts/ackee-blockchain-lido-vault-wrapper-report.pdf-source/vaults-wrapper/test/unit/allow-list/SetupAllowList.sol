// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ShortString, ShortStrings} from "@openzeppelin/contracts/utils/ShortStrings.sol";
import {Test} from "forge-std/Test.sol";
import {StvPool} from "src/StvPool.sol";
import {MockDashboard, MockDashboardFactory} from "test/mocks/MockDashboard.sol";
import {MockStETH} from "test/mocks/MockStETH.sol";

abstract contract SetupAllowList is Test {
    StvPool public poolWithAllowList;
    StvPool public poolWithoutAllowList;
    MockDashboard public dashboard;
    MockStETH public steth;

    address public owner;
    address public userAllowListed;
    address public userNotAllowListed;
    address public userAny;

    uint256 public constant INITIAL_DEPOSIT = 1 ether;

    function setUp() public virtual {
        owner = makeAddr("owner");
        userAllowListed = makeAddr("userAllowListed");
        userNotAllowListed = makeAddr("userNotAllowListed");
        userAny = makeAddr("userAny");

        // Fund accounts
        vm.deal(owner, 100 ether);
        vm.deal(userAllowListed, 100 ether);
        vm.deal(userNotAllowListed, 100 ether);
        vm.deal(userAny, 100 ether);

        // Deploy mocks
        dashboard = new MockDashboardFactory().createMockDashboard(owner);
        steth = dashboard.STETH();

        // Fund the dashboard with 1 ETH
        dashboard.fund{value: INITIAL_DEPOSIT}();

        // Deploy pool without allow list
        StvPool implWithoutAllowList = new StvPool({
            _dashboard: address(dashboard),
            _allowListEnabled: false,
            _withdrawalQueue: address(0),
            _distributor: address(0),
            _poolType: ShortString.unwrap(ShortStrings.toShortString("TestPool"))
        });
        ERC1967Proxy poolProxyWithoutAllowList = new ERC1967Proxy(address(implWithoutAllowList), "");
        poolWithoutAllowList = StvPool(payable(poolProxyWithoutAllowList));
        poolWithoutAllowList.initialize(owner, "Test", "stvETH");

        // Deploy pool with allow list
        StvPool implWithAllowList = new StvPool({
            _dashboard: address(dashboard),
            _allowListEnabled: true,
            _withdrawalQueue: address(0),
            _distributor: address(0),
            _poolType: ShortString.unwrap(ShortStrings.toShortString("TestPool"))
        });
        ERC1967Proxy poolProxyWithAllowList = new ERC1967Proxy(address(implWithAllowList), "");
        poolWithAllowList = StvPool(payable(poolProxyWithAllowList));
        poolWithAllowList.initialize(owner, "Test", "stvETH");

        // Setup allow list
        vm.prank(owner);
        poolWithAllowList.addToAllowList(userAllowListed);
    }
}
