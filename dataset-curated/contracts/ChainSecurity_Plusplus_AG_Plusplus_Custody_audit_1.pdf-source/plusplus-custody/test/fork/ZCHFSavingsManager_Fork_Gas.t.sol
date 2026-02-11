// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import {ZCHFSavingsManager} from "src/ZCHFSavingsManager.sol";
import {IFrankencoinSavings} from "../interfaces/IFrankencoinSavings.sol";

// Minimal ERC20 interface
interface IERC20 {
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
    function balanceOf(address who) external view returns (uint256);
}

/// @title ZCHFSavingsManagerForkGasTest
/// @notice Measures the gas consumption of core ZCHFSavingsManager operations
/// on a forked mainnet. This test suite evaluates the cost of moving ZCHF,
/// rescuing tokens, and creating/redeeming varying numbers of deposits. It
/// optionally computes the USD cost of each operation using environment
/// variables GAS_PRICE_WEI and ETH_PRICE_USD (both scaled by 1e18).
contract ZCHFSavingsManagerForkGasTest is Test {
    address constant ZCHF_ADDRESS = 0xB58E61C3098d85632Df34EecfB899A1Ed80921cB;
    address constant SAVINGS_MODULE = 0x27d9AD987BdE08a0d083ef7e0e4043C857A17B38;
    address constant WHALE = 0xa8c4E40075D1bb3A6E3343Be55b32B8E4a5612a1;

    ZCHFSavingsManager internal manager;
    IERC20 internal zchf;
    IFrankencoinSavings internal savings;

    address internal admin;
    address internal operator;
    address internal receiver;

    /// @notice Sets up the fork environment and funds the test contract with ZCHF.
    function setUp() public {
        uint256 forkId = vm.createSelectFork(vm.envString("MAINNET_RPC_URL"));
        vm.selectFork(forkId);

        admin = address(this);
        operator = address(this);
        receiver = makeAddr("gasReceiver");

        zchf = IERC20(ZCHF_ADDRESS);
        savings = IFrankencoinSavings(SAVINGS_MODULE);
        manager = new ZCHFSavingsManager(admin, ZCHF_ADDRESS, SAVINGS_MODULE);
        manager.grantRole(manager.OPERATOR_ROLE(), operator);
        manager.grantRole(manager.RECEIVER_ROLE(), receiver);
        manager.setDailyLimit(operator, 1_000_000e18);

        // Acquire substantial ZCHF from whale
        uint256 supply = 200_000 ether;
        vm.startPrank(WHALE);
        require(zchf.transfer(address(this), supply), "transfer failed");
        vm.stopPrank();

        zchf.approve(address(manager), type(uint256).max);
        vm.deal(address(this), 50 ether);
    }

    /// @notice Helper function to log gas usage and optional USD cost.
    function _logGas(string memory label, uint256 gasUsed) internal view {
        // Attempt to pull gas price and ETH price from the environment
        uint256 gasPrice;
        uint256 ethPriceUSD;
        bool haveGasPrice;
        bool haveEthPrice;
        // Try/catch is not available in Solidity 0.8.20 for env, so use low-level
        // We wrap in a try-catch style by reading into a local and checking for zero.
        try this._envUint("GAS_PRICE_WEI") returns (uint256 gp) {
            gasPrice = gp;
            haveGasPrice = true;
        } catch {
            haveGasPrice = false;
        }
        try this._envUint("ETH_PRICE_USD") returns (uint256 ep) {
            ethPriceUSD = ep;
            haveEthPrice = true;
        } catch {
            haveEthPrice = false;
        }
        gasUsed = gasUsed + 21000;
        console.log(label, gasUsed);
        if (haveGasPrice && haveEthPrice) {
            // Compute cost in USD scaled to 1e18
            uint256 weiCost = gasUsed * gasPrice;
            // CostUSD_e18 = weiCost * ethPriceUSD / 1e36
            uint256 costUSD_e18 = weiCost * ethPriceUSD / 1e34;
            console.log(string(abi.encodePacked(label, " costUSD_cents")), costUSD_e18);
        }
    }

    /// @notice Wrapper to call vm.envUint from within a try-catch. This must
    /// be external because internal try-catch cannot access vm env.
    function _envUint(string memory key) external view returns (uint256) {
        return vm.envUint(key);
    }

    /// @notice Measures the gas consumption for various operations on the fork.
    function testFork_GasMetrics() public {
        // Ensure there's some saved balance for moveZCHF measurement
        {
            bytes32[] memory ids = new bytes32[](1);
            uint192[] memory amts = new uint192[](1);
            ids[0] = keccak256("gasSeed");
            amts[0] = 1_000 ether;
            vm.prank(operator);
            manager.createDeposits(ids, amts, address(this));
        }

        // 1. Measure moveZCHF gas
        uint256 gasBefore = gasleft();
        vm.prank(admin);
        manager.moveZCHF(receiver, 500 ether);
        uint256 gasUsedMove = gasBefore - gasleft();
        _logGas("moveZCHF", gasUsedMove);

        // 2. Measure rescueTokens for ERC20
        // Fund manager with tokens to rescue
        require(zchf.transfer(address(manager), 1_000 ether), "fund manager failed");
        gasBefore = gasleft();
        vm.prank(admin);
        manager.rescueTokens(ZCHF_ADDRESS, receiver, 200 ether);
        uint256 gasUsedRescueToken = gasBefore - gasleft();
        _logGas("rescueTokens(ZCHF)", gasUsedRescueToken);

        // 3. Measure rescueTokens for ETH
        // Fund manager with ETH
        vm.deal(address(manager), 1_000 ether);
        //(bool s,) = address(manager).call{value: 1 ether}("");
        //require(s, "eth send failed");
        gasBefore = gasleft();
        vm.prank(admin);
        manager.rescueTokens(address(0), receiver, 0.5 ether);
        uint256 gasUsedRescueETH = gasBefore - gasleft();
        _logGas("rescueTokens(ETH)", gasUsedRescueETH);

        // 4. Measure create and redeem for various batch sizes
        uint256[6] memory counts = [uint256(1), 2, 5, 10, 20, 50];
        for (uint256 idx = 0; idx < counts.length; idx++) {
            uint256 count = counts[idx];
            // Prepare batch ids and amounts
            bytes32[] memory idsBatch = new bytes32[](count);
            uint192[] memory amountsBatch = new uint192[](count);
            uint192 batchAmount = 1 ether;
            for (uint256 i = 0; i < count; i++) {
                idsBatch[i] = keccak256(abi.encodePacked("batch", count, i, block.number));
                amountsBatch[i] = batchAmount;
            }
            // Measure createDeposits gas
            gasBefore = gasleft();
            vm.prank(operator);
            manager.createDeposits(idsBatch, amountsBatch, address(this));
            uint256 gasUsedCreate = gasBefore - gasleft();
            _logGas(string(abi.encodePacked("createDeposits ", vm.toString(count))), gasUsedCreate);
            // Measure redeemDeposits gas
            // Immediately redeem without warping; interest will be zero but gas
            // cost of looping remains
            gasBefore = gasleft();
            vm.prank(operator);
            manager.redeemDeposits(idsBatch, receiver);
            uint256 gasUsedRedeem = gasBefore - gasleft();
            _logGas(string(abi.encodePacked("redeemDeposits ", vm.toString(count))), gasUsedRedeem);
        }
    }
}
