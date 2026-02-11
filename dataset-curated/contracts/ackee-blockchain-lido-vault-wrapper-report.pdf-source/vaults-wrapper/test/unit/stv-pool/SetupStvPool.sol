// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ShortString, ShortStrings} from "@openzeppelin/contracts/utils/ShortStrings.sol";

import {Test} from "forge-std/Test.sol";
import {StvPool} from "src/StvPool.sol";
import {MockDashboard, MockDashboardFactory} from "test/mocks/MockDashboard.sol";
import {MockStETH} from "test/mocks/MockStETH.sol";
import {MockVaultHub} from "test/mocks/MockVaultHub.sol";

abstract contract SetupStvPool is Test {
    StvPool public pool;
    MockDashboard public dashboard;
    MockVaultHub public vaultHub;
    MockStETH public steth;

    address public owner;
    address public userAlice;
    address public userBob;

    address public withdrawalQueue;

    uint256 public constant INITIAL_DEPOSIT = 1 ether;

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
        vaultHub = dashboard.VAULT_HUB();

        // Fund the dashboard with 1 ETH
        dashboard.fund{value: INITIAL_DEPOSIT}();

        // Deploy the pool
        StvPool poolImpl = new StvPool({
            _dashboard: address(dashboard),
            _allowListEnabled: false,
            _withdrawalQueue: withdrawalQueue,
            _distributor: address(0),
            _poolType: ShortString.unwrap(ShortStrings.toShortString("TestPool"))
        });
        ERC1967Proxy poolProxy = new ERC1967Proxy(address(poolImpl), "");

        pool = StvPool(payable(poolProxy));
        pool.initialize(owner, "Test", "stvETH");
    }
}
