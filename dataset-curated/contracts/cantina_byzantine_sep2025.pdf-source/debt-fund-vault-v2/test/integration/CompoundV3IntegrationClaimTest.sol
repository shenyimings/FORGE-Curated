// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 [Byzantine Finance]
// The implementation of this contract was inspired by Morpho Vault V2, developed by the Morpho Association in 2025.
pragma solidity ^0.8.0;

import {stdJson} from "../../lib/forge-std/src/StdJson.sol";
import "./CompoundV3IntegrationTest.sol";

contract CompoundV3IntegrationClaimTest is CompoundV3IntegrationTest {
    CometInterface constant baseComet = CometInterface(0xb125E6687d4313864e53df431d5425969c15Eb2F);
    CometRewardsInterface constant baseCometRewards = CometRewardsInterface(0x123964802e6ABabBE1Bc9547D72Ef1B69B00A6b1);
    IERC20 constant baseUSDC = IERC20(0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913);
    uint256 constant elapsedTime = 300 days; // Used to boost the rewards accrual

    // Claiming data (bot generated)
    uint256 internal baseForkBlock;
    address internal vaultAddr;
    address internal adapterAddr;
    address internal rewardToken;
    uint256 internal rewardAmount;
    address internal lifiDiamond;
    uint256 internal usdcMinAmountReceived;
    bytes internal swapData;
    bytes internal claimData;

    // Load quote data from JSON file
    string internal root = vm.projectRoot();
    string internal path = string.concat(root, "/test/data/claim_data_compound_base.json");

    // Test accounts
    address immutable claimer = makeAddr("claimer");

    function setUp() public virtual override {
        _loadClaimData(path);

        // Create a fork with a specific block number
        rpcUrl = vm.envString("BASE_RPC_URL");
        forkId = vm.createFork(rpcUrl, baseForkBlock);
        vm.selectFork(forkId);
        skipMainnetFork = true;

        // Set base contracts
        comet = baseComet;
        cometRewards = baseCometRewards;
        usdc = baseUSDC;

        super.setUp();

        // Deploy an apdater with parent vault being `vaultAddr` and etch code to `adapterAddr`
        compoundAdapter = ICompoundV3Adapter(
            compoundAdapterFactory.createCompoundV3Adapter(vaultAddr, address(comet), address(cometRewards))
        );
        vm.etch(adapterAddr, address(compoundAdapter).code);

        vm.expectEmit();
        emit ICompoundV3Adapter.SetClaimer(claimer);

        vm.prank(IVaultV2(vaultAddr).curator());
        ICompoundV3Adapter(adapterAddr).setClaimer(claimer);
        assertEq(ICompoundV3Adapter(adapterAddr).claimer(), claimer);
    }

    function testClaimRewards() public {
        // Get the reward token
        address compToken = cometRewards.getRewardOwed(address(comet), address(adapterAddr)).token;
        assertEq(compToken, rewardToken, "Bad reward token in test data file");

        skip(elapsedTime);

        uint256 rewardsOwed = cometRewards.getRewardOwed(address(comet), address(adapterAddr)).owed;
        assertEq(rewardsOwed, rewardAmount, "Bad reward amount in test data file");

        uint256 vaultAssetBalanceBefore = IERC20(IVaultV2(vaultAddr).asset()).balanceOf(vaultAddr);

        vm.expectEmit();
        emit ICompoundV3Adapter.Claim(rewardToken, rewardAmount);

        vm.expectEmit();
        emit ICompoundV3Adapter.SwapRewards(lifiDiamond, rewardToken, rewardAmount, swapData);

        // Claim and swap COMP rewards
        vm.prank(claimer);
        ICompoundV3Adapter(adapterAddr).claim(claimData);

        uint256 vaultAssetBalanceAfter = IERC20(IVaultV2(vaultAddr).asset()).balanceOf(vaultAddr);
        uint256 rewardsInUSDC = vaultAssetBalanceAfter - vaultAssetBalanceBefore;

        assertGe(rewardsInUSDC, usdcMinAmountReceived);

        assertEq(cometRewards.rewardsClaimed(address(comet), address(adapterAddr)), rewardAmount);
        assertEq(cometRewards.getRewardOwed(address(comet), address(adapterAddr)).owed, 0);
    }

    function _loadClaimData(string memory _path) internal {
        string memory json = vm.readFile(_path);

        baseForkBlock = stdJson.readUint(json, ".blockNumber");
        vaultAddr = stdJson.readAddress(json, ".vaultAddr");
        adapterAddr = stdJson.readAddress(json, ".adapterAddr");
        rewardToken = stdJson.readAddress(json, ".rewardToken");
        rewardAmount = stdJson.readUint(json, ".rewardAmount");
        lifiDiamond = stdJson.readAddress(json, ".lifiDiamond");
        usdcMinAmountReceived = stdJson.readUint(json, ".toAmountMin");
        swapData = stdJson.readBytes(json, ".swapCalldata");
        claimData = stdJson.readBytes(json, ".claimCalldata");

        vm.label(adapterAddr, "baseRealAdapter");
        vm.label(rewardToken, "rewardToken");
    }
}
