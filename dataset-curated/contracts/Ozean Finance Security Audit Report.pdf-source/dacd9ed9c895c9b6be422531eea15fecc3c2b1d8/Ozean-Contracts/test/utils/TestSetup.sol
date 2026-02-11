// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import {Test} from "forge-std/Test.sol";
import {console2 as console} from "forge-std/console2.sol";
import {OptimismPortal} from "optimism/src/L1/OptimismPortal.sol";
import {SystemConfig} from "optimism/src/L1/SystemConfig.sol";
import {L1StandardBridge} from "optimism/src/L1/L1StandardBridge.sol";
import {IUSDX, IERC20Faucet, IERC20} from "test/utils/TestInterfaces.sol";
import {IStETH, IWstETH} from "test/utils/TestInterfaces.sol";
import {USDXBridge} from "src/L1/USDXBridge.sol";
import {LGEStaking} from "src/L1/LGEStaking.sol";
import {LGEMigrationV1, IL1LidoTokensBridge} from "src/L1/LGEMigrationV1.sol";
import {OzUSD} from "src/L2/OzUSD.sol";
import {WozUSD} from "src/L2/WozUSD.sol";

contract TestSetup is Test {
    /// L1
    address public constant faucetOwner = 0xC959483DBa39aa9E78757139af0e9a2EDEb3f42D;
    OptimismPortal public optimismPortal;
    SystemConfig public systemConfig;
    L1StandardBridge public l1StandardBridge;
    IL1LidoTokensBridge public l1LidoTokensBridge;
    IERC20Faucet public usdc;
    IERC20Faucet public usdt;
    IERC20Faucet public dai;
    IStETH public stETH;
    IWstETH public wstETH;

    IUSDX public usdx;
    USDXBridge public usdxBridge;
    LGEStaking public lgeStaking;
    LGEMigrationV1 public lgeMigration;

    /// L2

    OzUSD public ozUSD;
    WozUSD public wozUSD;

    /// Universal
    address public hexTrust;
    address public alice;
    address public bob;

    function setUp() public virtual {
        hexTrust = makeAddr("HEX_TRUST");
        alice = makeAddr("ALICE");
        bob = makeAddr("BOB");
    }

    modifier prank(address _user) {
        vm.startPrank(_user);
        _;
        vm.stopPrank();
    }

    /// FORK L1 ///

    function _forkL1() internal {
        string memory rpcURL = vm.envString("L1_RPC_URL");
        uint256 l1Fork = vm.createFork(rpcURL);
        vm.selectFork(l1Fork);
        /// Environment
        vm.deal(hexTrust, 10_000 ether);
        vm.deal(alice, 10_000 ether);
        vm.deal(bob, 10_000 ether);
        optimismPortal = OptimismPortal(payable(0x6EeeA09335D09870dD467FD34ECc10Fdb5106527));
        systemConfig = SystemConfig(0xdEC733B0643E7c3Bd06576A4C70Ca87E301EAe87);
        l1StandardBridge = L1StandardBridge(payable(0xb9558CE3C11EC69e18632A8e5B316581e852dB91));
        l1LidoTokensBridge = IL1LidoTokensBridge(0xd836932faEaC34FdFF0bb14696E92bA33805D4E3);
        usdx = IUSDX(0x43bd82D1e29a1bEC03AfD11D5a3252779b8c760c);
        usdc = IERC20Faucet(0x94a9D9AC8a22534E3FaCa9F4e7F2E2cf85d5E4C8);
        usdt = IERC20Faucet(0xaA8E23Fb1079EA71e0a56F48a2aA51851D8433D0);
        dai = IERC20Faucet(0xFF34B3d4Aee8ddCd6F9AFFFB6Fe49bD371b8a357);
        stETH = IStETH(0x3e3FE7dBc6B4C189E7128855dD526361c49b40Af);
        wstETH = IWstETH(0xB82381A3fBD3FaFA77B3a7bE693342618240067b);
        _distributeTokens(alice);
        _distributeTokens(bob);
    }

    function _distributeTokens(address _user) internal prank(faucetOwner) {
        usdc.mint(_user, 1e18);
        usdt.mint(_user, 1e18);
        dai.mint(_user, 1e30);
        vm.deal(faucetOwner, 10_000 ether);
        uint256 amount0 = stETH.submit{value: 10_000 ether}(address(69));
        stETH.approve(address(wstETH), amount0);
        uint256 amount1 = wstETH.wrap(amount0);
        wstETH.transfer(_user, amount1);
    }

    /// FORK L2 ///

    function _forkL2() internal {
        string memory rpcURL = vm.envString("L2_RPC_URL");
        uint256 l2Fork = vm.createFork(rpcURL);
        vm.selectFork(l2Fork);
        /// Environment
        vm.deal(hexTrust, 10_000 ether);
        vm.deal(alice, 10_000 ether);
        vm.deal(bob, 10_000 ether);
    }
}
