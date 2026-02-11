// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 [Byzantine Finance]
// The implementation of this contract was inspired by Morpho Vault V2, developed by the Morpho Association in 2025.
pragma solidity ^0.8.0;

import {VaultV2Factory, IVaultV2Factory} from "../../src/VaultV2Factory.sol";
import {IVaultV2, IERC20} from "../../src/interfaces/IVaultV2.sol";
import "../../src/libraries/ConstantsLib.sol";

import {CompoundV3Adapter} from "../../src/adapters/CompoundV3Adapter.sol";
import {CompoundV3AdapterFactory} from "../../src/adapters/CompoundV3AdapterFactory.sol";
import {ICompoundV3AdapterFactory} from "../../src/adapters/interfaces/ICompoundV3AdapterFactory.sol";
import {ICompoundV3Adapter} from "../../src/adapters/interfaces/ICompoundV3Adapter.sol";

import {CometInterface} from "../../src/interfaces/CometInterface.sol";
import {CometRewardsInterface} from "../../src/interfaces/CometRewardsInterface.sol";

import {Test, console2} from "../../lib/forge-std/src/Test.sol";

contract CompoundV3IntegrationTest is Test {
    uint256 constant MAX_TEST_ASSETS = 1e18;

    // Fork variables
    string internal rpcUrl;
    uint256 internal forkId;
    uint256 internal forkBlock = 23175417;
    bool internal skipMainnetFork;

    // Addresses of Comet USDC and USDC on Ethereum Mainnet
    CometInterface internal comet = CometInterface(0xc3d688B66703497DAA19211EEdff47f25384cdc3);
    CometRewardsInterface internal cometRewards = CometRewardsInterface(0x1B0e765F6224C21223AeA2af16c1C46E38885a40);
    IERC20 internal usdc = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    IERC20 internal cbBTC = IERC20(0xcbB7C0000aB88B473b1f5aFd9ef808440eed33Bf);
    IERC20 internal wstETH = IERC20(0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0);

    // Test accounts
    address immutable owner = makeAddr("owner");
    address immutable curator = makeAddr("curator");
    address immutable allocator = makeAddr("allocator");
    address immutable sentinel = makeAddr("sentinel");
    address internal immutable receiver = makeAddr("receiver");
    address internal immutable borrower = makeAddr("borrower");

    // Expected data
    bytes32 internal expectedAdapterId;
    bytes internal expectedAdapterIdData;

    // Contracts
    IVaultV2Factory internal vaultFactory;
    IVaultV2 internal vault;
    ICompoundV3AdapterFactory internal compoundAdapterFactory;
    ICompoundV3Adapter internal compoundAdapter;

    function setUp() public virtual {
        // Create mainnet fork (is skipping not asked)
        if (!skipMainnetFork) {
            rpcUrl = vm.envString("MAINNET_RPC_URL");
            forkId = vm.createFork(rpcUrl, forkBlock);
            vm.selectFork(forkId);
        }

        vm.label(address(this), "testContract");
        vm.label(address(usdc), "usdc");
        vm.label(address(comet), "comet");
        vm.label(address(cometRewards), "cometRewards");

        /* VAULT SETUP */

        vaultFactory = IVaultV2Factory(address(new VaultV2Factory()));
        vault = IVaultV2(vaultFactory.createVaultV2(owner, address(usdc), bytes32(0)));
        vm.label(address(vault), "vault");

        compoundAdapterFactory = ICompoundV3AdapterFactory(address(new CompoundV3AdapterFactory()));
        compoundAdapter = ICompoundV3Adapter(
            compoundAdapterFactory.createCompoundV3Adapter(address(vault), address(comet), address(cometRewards))
        );
        expectedAdapterIdData = abi.encode("this", address(compoundAdapter));
        expectedAdapterId = keccak256(expectedAdapterIdData);
        vm.label(address(compoundAdapter), "compoundAdapter");

        vm.startPrank(owner);
        vault.setCurator(curator);
        vault.setIsSentinel(sentinel, true);
        vm.stopPrank();

        vm.startPrank(curator);

        vault.submit(abi.encodeCall(IVaultV2.setIsAllocator, (allocator, true)));
        vault.setIsAllocator(allocator, true);

        vault.submit(abi.encodeCall(IVaultV2.addAdapter, address(compoundAdapter)));
        vault.addAdapter(address(compoundAdapter));

        vault.submit(abi.encodeCall(IVaultV2.increaseAbsoluteCap, (expectedAdapterIdData, type(uint128).max)));
        vault.increaseAbsoluteCap(expectedAdapterIdData, type(uint128).max);

        vault.submit(abi.encodeCall(IVaultV2.increaseRelativeCap, (expectedAdapterIdData, WAD)));
        vault.increaseRelativeCap(expectedAdapterIdData, WAD);

        vm.stopPrank();

        // Set max rate for interest accrual
        vm.prank(allocator);
        vault.setMaxRate(MAX_MAX_RATE);

        // Fund user with USDC for testing
        deal(address(usdc), address(this), MAX_TEST_ASSETS);
        usdc.approve(address(vault), type(uint256).max);
    }
}
