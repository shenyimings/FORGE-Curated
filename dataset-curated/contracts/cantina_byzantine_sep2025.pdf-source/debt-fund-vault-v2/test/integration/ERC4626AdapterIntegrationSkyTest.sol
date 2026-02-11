// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 [Byzantine Finance]
// The implementation of this contract was inspired by Morpho Vault V2, developed by the Morpho Association in 2025.
pragma solidity ^0.8.0;

import "./MorphoVaultV1_1IntegrationTest.sol";

contract ERC4626AdapterIntegrationSkyTest is MorphoVaultV1_1IntegrationTest {
    uint256 constant MAX_TEST_ASSETS_SKY = 1e12;

    // Addresses of Sky sUSDC, sUSDS, USDC and USDS on Ethereum Mainnet
    IERC20 internal usdc = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    IERC4626 internal sUSDC = IERC4626(0xBc65ad17c5C0a2A4D159fa5a503f4992c7B545FE);
    IERC4626 internal sUSDS = IERC4626(0xa3931d71877C0E7a3148CB7Eb4463524FEc27fbD);
    IERC20 internal usds = IERC20(0xdC035D45d973E3EC169d2276DDab16f1e407384F);

    // Sky Adapter data
    MorphoVaultV1Adapter internal skyAdapter;
    bytes32 internal expectedSkyAdapterId;
    bytes internal expectedSkyAdapterIdData;

    // Test account
    address immutable receiver = makeAddr("receiver");

    function setUp() public virtual override {
        string memory rpcUrl = vm.envString("MAINNET_RPC_URL");
        uint256 forkId = vm.createFork(rpcUrl);
        vm.selectFork(forkId);

        super.setUp();

        vm.label(address(sUSDC), "sUSDC");
        vm.label(address(sUSDS), "sUSDS");
        vm.label(address(usds), "usds");

        vault = _createUSDCVault();

        skyAdapter =
            MorphoVaultV1Adapter(morphoVaultV1AdapterFactory.createMorphoVaultV1Adapter(address(vault), address(sUSDC)));
        expectedSkyAdapterIdData = abi.encode("this", address(skyAdapter));
        expectedSkyAdapterId = keccak256(expectedSkyAdapterIdData);
        vm.label(address(skyAdapter), "skyAdapter");

        vm.prank(curator);
        vault.submit(abi.encodeCall(IVaultV2.addAdapter, address(skyAdapter)));
        vault.addAdapter(address(skyAdapter));
        increaseAbsoluteCap(expectedSkyAdapterIdData, type(uint128).max);
        increaseRelativeCap(expectedSkyAdapterIdData, WAD);

        // Set Sky as liquidity adapter
        vm.prank(allocator);
        vault.setLiquidityAdapterAndData(address(skyAdapter), "");

        // Fund user with USDC for testing
        deal(address(usdc), address(this), MAX_TEST_ASSETS_SKY);
        usdc.approve(address(vault), type(uint256).max);
    }

    function testsUSDCDeposit(uint256 assets) public {
        assets = bound(assets, 0, MAX_TEST_ASSETS_SKY);

        uint256 USDSBalanceBefore = usds.balanceOf(address(sUSDC));
        uint256 expectedReceivedShares = sUSDC.previewDeposit(assets);
        // USDC are swapped to USDS that are deposited to sUSDS
        vault.deposit(assets, address(this));

        assertEq(sUSDC.balanceOf(address(skyAdapter)), expectedReceivedShares, "adapter sUSDC balance");
        assertApproxEqAbs(
            sUSDC.convertToAssets(sUSDC.balanceOf(address(skyAdapter))), assets, 1 wei, "adapter sUSDC conversion"
        );

        uint256 USDSBalanceAfter = usds.balanceOf(address(sUSDC));
        assertGe(USDSBalanceBefore + assets, USDSBalanceAfter, "sUSDS USDS balance");
    }

    /// forge-config: default.isolate = true
    function testsUSDCWithdrawInterest(uint256 assets, uint256 elapsed) public {
        assets = bound(assets, 0, MAX_TEST_ASSETS_SKY);
        elapsed = bound(elapsed, 1, 10 * 365 days);

        vault.deposit(assets, address(this));

        skip(elapsed);

        uint256 newAssets = sUSDC.convertToAssets(sUSDC.balanceOf(address(skyAdapter)));
        uint256 interest = newAssets - assets;

        vault.redeem(vault.balanceOf(address(this)), receiver, address(this));
        assertApproxEqAbs(usdc.balanceOf(receiver), assets + interest, 1 wei, "withdraw all");
    }

    function _createUSDCVault() internal returns (IVaultV2) {
        IVaultV2 usdcVault = IVaultV2(vaultFactory.createVaultV2(owner, address(usdc), bytes32(0)));
        vm.label(address(usdcVault), "usdcVault");

        // Set up usdcVault roles
        vm.startPrank(owner);
        usdcVault.setCurator(curator);
        usdcVault.setIsSentinel(sentinel, true);
        vm.stopPrank();

        vm.startPrank(curator);

        // Set up allocator
        usdcVault.submit(abi.encodeCall(IVaultV2.setIsAllocator, (allocator, true)));
        usdcVault.setIsAllocator(allocator, true);

        vm.stopPrank();

        // Set max rate for interest accrual
        vm.prank(allocator);
        usdcVault.setMaxRate(MAX_MAX_RATE);

        return usdcVault;
    }
}
