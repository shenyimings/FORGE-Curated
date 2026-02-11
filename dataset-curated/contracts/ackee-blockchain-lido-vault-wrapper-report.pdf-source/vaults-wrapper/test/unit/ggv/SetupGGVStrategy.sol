// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {Test} from "forge-std/Test.sol";

import {StvStrategyPoolHarness} from "test/utils/StvStrategyPoolHarness.sol";
import {GGVStrategy} from "src/strategy/GGVStrategy.sol";
import {IStrategy} from "src/interfaces/IStrategy.sol";
import {StvStETHPool} from "src/StvStETHPool.sol";
import {GGVVaultMock} from "src/mock/ggv/GGVVaultMock.sol";
import {ITellerWithMultiAssetSupport} from "src/interfaces/ggv/ITellerWithMultiAssetSupport.sol";
import {IBoringOnChainQueue} from "src/interfaces/ggv/IBoringOnChainQueue.sol";
import {MockDashboard, MockDashboardFactory} from "test/mocks/MockDashboard.sol";
import {MockVaultHub} from "test/mocks/MockVaultHub.sol";
import {MockStETH} from "test/mocks/MockStETH.sol";
import {MockWstETH} from "test/mocks/MockWstETH.sol";
import {StrategyCallForwarder} from "src/strategy/StrategyCallForwarder.sol";
import {console} from "forge-std/console.sol";


abstract contract SetupGGVStrategy is Test {
    using SafeCast for uint256;

    StvStETHPool public pool;
    MockDashboard public dashboard;
    MockVaultHub public vaultHub;
    MockStETH public steth;
    MockWstETH public wsteth;

    address public owner;
    address public withdrawalQueue;
    address public userAlice;
    address public userBob;

    GGVStrategy public ggvStrategy;
    ITellerWithMultiAssetSupport public teller;
    IBoringOnChainQueue public boringOnChainQueue;
    GGVVaultMock public boringVault;

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

        boringVault = new GGVVaultMock(owner, address(steth), address(wsteth));
        teller = ITellerWithMultiAssetSupport(address(boringVault.TELLER()));
        boringOnChainQueue = IBoringOnChainQueue(address(boringVault.BORING_QUEUE()));

        address strategyCallForwarderImpl = address(new StrategyCallForwarder());
        GGVStrategy ggvStrategyImpl = new GGVStrategy(bytes32("ggv.startegy"), strategyCallForwarderImpl, address(pool), address(teller), address(boringOnChainQueue));

        ERC1967Proxy ggvStrategyProxy = new ERC1967Proxy(address(ggvStrategyImpl), "");
        ggvStrategy = GGVStrategy(payable(ggvStrategyProxy));
        ggvStrategy.initialize(owner, owner);
    }
}

