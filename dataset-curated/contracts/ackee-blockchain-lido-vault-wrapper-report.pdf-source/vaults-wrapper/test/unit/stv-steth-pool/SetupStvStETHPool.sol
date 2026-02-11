// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Test} from "forge-std/Test.sol";

import {StvStETHPool} from "src/StvStETHPool.sol";
import {MockDashboard, MockDashboardFactory} from "test/mocks/MockDashboard.sol";
import {MockStETH} from "test/mocks/MockStETH.sol";
import {MockVaultHub} from "test/mocks/MockVaultHub.sol";
import {MockWstETH} from "test/mocks/MockWstETH.sol";

abstract contract SetupStvStETHPool is Test {
    StvStETHPool public pool;
    MockDashboard public dashboard;
    MockVaultHub public vaultHub;
    MockStETH public steth;
    MockWstETH public wsteth;

    address public owner;
    address public withdrawalQueue;
    address public userAlice;
    address public userBob;

    uint256 public constant INITIAL_DEPOSIT = 1 ether;
    uint256 public constant RESERVE_RATIO_GAP_BP = 5_00; // 5%

    function setUp() public virtual {
        owner = makeAddr("owner");
        userAlice = makeAddr("userAlice");
        userBob = makeAddr("userBob");
        withdrawalQueue = makeAddr("withdrawalQueue");

        // Fund accounts
        vm.deal(owner, 100 ether);
        vm.deal(userAlice, 1000 ether);
        vm.deal(userBob, 1000 ether);

        // Deploy mocks
        dashboard = new MockDashboardFactory().createMockDashboard(owner);
        steth = dashboard.STETH();
        wsteth = dashboard.WSTETH();
        vaultHub = dashboard.VAULT_HUB();

        // Fund the dashboard with 1 ETH
        dashboard.fund{value: INITIAL_DEPOSIT}();

        // Deploy the pool with mock withdrawal queue
        StvStETHPool poolImpl = new StvStETHPool(
            address(dashboard), false, RESERVE_RATIO_GAP_BP, withdrawalQueue, address(0), keccak256("test.stv.steth.pool")
        );
        ERC1967Proxy poolProxy = new ERC1967Proxy(address(poolImpl), "");

        pool = StvStETHPool(payable(poolProxy));
        pool.initialize(owner, "Test", "stvETH");
    }
}
