// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.22;

import {Test, console2} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../contracts/MerkleDistributor.sol";

contract MerkleDistributorTest is Test {
    MerkleDistributor public distributor;
    address public admin = address(0x123);

    // Vault account that has funds on all chains
    address constant VAULT_ACCOUNT = 0x82BF455e9ebd6a541EF10b683dE1edCaf05cE7A1;

    // Proofs and samples generated from ~/scripts/generate-multitoken-merkle-root.ts
    // Output files found in ~/data/{chainName}-merkle-data.json, using the ~/data/{chainName}_balances.csv files as our source of truth for
    // what each Panoptic user should be able to reclaim
    // ============ BASE CHAIN CONSTANTS ============
    bytes32 constant BASE_MERKLE_ROOT = 0xb2b025a07391f5072db59ddbd44c1f08d8c45aaf6540daab2f8a5ba21bb340d0;
    address constant BASE_WETH = 0x4200000000000000000000000000000000000006;
    address constant BASE_USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
    address constant BASE_TEST_ACCOUNT = 0x0235a7aE51301c3cb19493D7E37f9eFdd7c5c3bB;
    uint256 constant BASE_TEST_INDEX = 0;

    // ============ ETHEREUM MAINNET CONSTANTS ============
    bytes32 constant MAINNET_MERKLE_ROOT = 0xfc98cc0d1bbbbddd72b72d70d01dd5fc1bcf5bdb4286da286eb14c7174ea6895;
    address constant MAINNET_USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant MAINNET_WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address constant MAINNET_TEST_ACCOUNT = 0x00B2E0166500fe321DD72EA2CB1af23af5e30aF0;
    uint256 constant MAINNET_TEST_INDEX = 2;

    // ============ UNICHAIN CONSTANTS ============
    bytes32 constant UNICHAIN_MERKLE_ROOT = 0xbdd0e6e4a36de4cdb9aa3ff02899863cb75ce2680f1db9d9fde6c8bfb246fdb6;
    address constant UNICHAIN_USDC = 0x078D782b760474a361dDA0AF3839290b0EF57AD6;
    address constant UNICHAIN_WETH = 0x4200000000000000000000000000000000000006;
    address constant UNICHAIN_TEST_ACCOUNT = 0x045324661B1B38D32A8C5B50f1B5bdD62f5f9d86;
    uint256 constant UNICHAIN_TEST_INDEX = 3;

    uint256 withdrawableAt;

    // ============ BASE CHAIN TESTS ============

    function testBase_MerkleRoot() public {
        _setupBase();
        assertEq(distributor.merkleRoot(), BASE_MERKLE_ROOT);
    }

    function testBase_SupportedTokens() public {
        _setupBase();
        assertTrue(distributor.supportedTokens(BASE_WETH));
        assertTrue(distributor.supportedTokens(BASE_USDC));
    }

    function testBase_ValidClaim() public {
        _setupBase();

        // Set up test claim data
        address[] memory tokens = new address[](2);
        tokens[0] = BASE_WETH;
        tokens[1] = BASE_USDC;

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 2938061841488396; // WETH amount from base data
        amounts[1] = 0; // USDC amount from base data

        bytes32[] memory proof = _getBaseProof();
        uint256 initialBalance = IERC20(BASE_WETH).balanceOf(BASE_TEST_ACCOUNT);

        console2.log("initialWETHBalance of claimant:", initialBalance);

        // Execute the claim
        vm.prank(BASE_TEST_ACCOUNT);
        distributor.claim(BASE_TEST_INDEX, BASE_TEST_ACCOUNT, tokens, amounts, proof);

        console2.log("post-claim WETH Balance of claimant:", IERC20(BASE_WETH).balanceOf(BASE_TEST_ACCOUNT));

        // Verify balances updated correctly
        assertEq(IERC20(BASE_WETH).balanceOf(BASE_TEST_ACCOUNT), initialBalance + amounts[0]);

        // Verify claim is marked as claimed
        assertTrue(distributor.isClaimed(BASE_TEST_INDEX));
    }

    function testBase_CannotClaimTwice() public {
        _setupBase();

        address[] memory tokens = new address[](2);
        tokens[0] = BASE_WETH;
        tokens[1] = BASE_USDC;

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 2938061841488396;
        amounts[1] = 0;

        bytes32[] memory proof = _getBaseProof();

        // First claim should succeed
        vm.prank(BASE_TEST_ACCOUNT);
        distributor.claim(BASE_TEST_INDEX, BASE_TEST_ACCOUNT, tokens, amounts, proof);

        // Second claim should fail
        vm.prank(BASE_TEST_ACCOUNT);
        vm.expectRevert(AlreadyClaimed.selector);
        distributor.claim(BASE_TEST_INDEX, BASE_TEST_ACCOUNT, tokens, amounts, proof);
    }

    // ============ ETHEREUM MAINNET TESTS ============

    function testMainnet_MerkleRoot() public {
        _setupMainnet();
        assertEq(distributor.merkleRoot(), MAINNET_MERKLE_ROOT);
    }

    function testMainnet_SupportedTokens() public {
        _setupMainnet();
        assertTrue(distributor.supportedTokens(MAINNET_USDC));
        assertTrue(distributor.supportedTokens(MAINNET_WETH));
    }

    function testMainnet_ValidClaim() public {
        _setupMainnet();

        // Set up test claim data
        address[] memory tokens = new address[](2);
        tokens[0] = MAINNET_USDC;
        tokens[1] = MAINNET_WETH;

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 224064496; // USDC amount
        amounts[1] = 0; // WETH amount

        bytes32[] memory proof = new bytes32[](10);
        proof[0] = 0x363cba88087d853d43d49109015f03668288abdc49d919b290e3cfa7d121a8a0;
        proof[1] = 0x7a49e9fd41dc9688823abb51c7edb1e06ec0c300e268f1a3e9b10cbd05c5aa84;
        proof[2] = 0x906bc7b7ce8c55addbb68e5138d24f90e67a3f115a5399efcd8b739be9d0380d;
        proof[3] = 0x1c79464a41f0363736d95ffdd573035d95f38afad0c6048dc9779da60defe03c;
        proof[4] = 0xcd3cceefc2f4ac8fa709937b5e56de5e837b9a273e15b575fa20f5e5a189350e;
        proof[5] = 0x4aa10617259eab761dcee883261f2f9e35d4fe6903a1eb482c1249e484d8dce2;
        proof[6] = 0xca0bd0bd7b26ea0c84404649b6f8ec9a7eb6de6823848b6360a6c25d01539205;
        proof[7] = 0x15fc330cfa367ef573198d2dadc7ee8a67db1c7079cf9968325d5a339d94fed9;
        proof[8] = 0x555b67fc2291ed58234dfb9893d7c23f7af2b75d3599f2010def29a7ef56a0d1;
        proof[9] = 0x51365528c93bed96fffd163823a44f35017da3921ad36c481746bb654a81fa69;

        uint256 initialBalance = IERC20(MAINNET_USDC).balanceOf(MAINNET_TEST_ACCOUNT);
        console2.log("initialUSDCBalance of claimant:", initialBalance);

        // Execute the claim
        vm.prank(MAINNET_TEST_ACCOUNT);
        distributor.claim(MAINNET_TEST_INDEX, MAINNET_TEST_ACCOUNT, tokens, amounts, proof);
        console2.log("post-claim USDC Balance of claimant:", IERC20(MAINNET_USDC).balanceOf(MAINNET_TEST_ACCOUNT));

        // Verify balances updated correctly
        assertEq(IERC20(MAINNET_USDC).balanceOf(MAINNET_TEST_ACCOUNT), initialBalance + amounts[0]);

        // Verify claim is marked as claimed
        assertTrue(distributor.isClaimed(MAINNET_TEST_INDEX));
    }

    function testMainnet_InvalidProof() public {
        _setupMainnet();

        address[] memory tokens = new address[](2);
        tokens[0] = MAINNET_USDC;
        tokens[1] = MAINNET_WETH;

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 0;
        amounts[1] = 0;

        bytes32[] memory invalidProof = new bytes32[](1);
        invalidProof[0] = bytes32(uint256(1));

        vm.prank(MAINNET_TEST_ACCOUNT);
        vm.expectRevert(InvalidProof.selector);
        distributor.claim(MAINNET_TEST_INDEX, MAINNET_TEST_ACCOUNT, tokens, amounts, invalidProof);
    }

    // ============ UNICHAIN TESTS ============

    function testUnichain_MerkleRoot() public {
        _setupUnichain();
        assertEq(distributor.merkleRoot(), UNICHAIN_MERKLE_ROOT);
    }

    function testUnichain_SupportedTokens() public {
        _setupUnichain();
        assertTrue(distributor.supportedTokens(UNICHAIN_USDC));
        assertTrue(distributor.supportedTokens(UNICHAIN_WETH));
    }

    function testUnichain_ValidClaim() public {
        _setupUnichain();

        // Set up test claim data (note the duplicate WETH addresses in original data)
        address[] memory tokens = new address[](2);
        tokens[0] = UNICHAIN_USDC;
        tokens[1] = UNICHAIN_WETH;

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 0;
        amounts[1] = 1029089761109200;

        bytes32[] memory proof = new bytes32[](9);
        proof[0] = 0x048716ff63a8b4cf963bdb616c80daca2eb60bdca275e4761e9c3435623c1fd9;
        proof[1] = 0x69bc509a3b1de64a50df3ec92b8550e3d111812637f88dd3ddb8c0cb29c3b97f;
        proof[2] = 0x921f81e5b53611d4242d3609d8fab79f44d3dcfe1d5489f83aaecd2fad68501f;
        proof[3] = 0xcd99617124b3f50fe9f3d6cc77c1398ee53f84d72d69216d78145cd64d6e3cde;
        proof[4] = 0xdd207c72b1ab17233cbd99a7d359cba6a652bc424e80962f1be5e901ef9c3e67;
        proof[5] = 0x8ee783c12931adb244f11ca8a252b2ea58130c0d31f76442aa2f9493d81ac76e;
        proof[6] = 0xa709a44851cb2a58259c9d49a4dfb217105a33509d67011dd1d93d17cdce5812;
        proof[7] = 0xb3f3034336424dc075eb52778bdbf39c0002fc453f90b58f8446287a33ab0379;
        proof[8] = 0xb467125908b2fa01fed95f324eabb81d5ec16d6e077d54f479c3208146892ac2;

        uint256 initialUSDCBalance = IERC20(UNICHAIN_USDC).balanceOf(UNICHAIN_TEST_ACCOUNT);
        uint256 initialWETHBalance = IERC20(UNICHAIN_WETH).balanceOf(UNICHAIN_TEST_ACCOUNT);
        console2.log("initialUSDCBalance of claimant:", initialUSDCBalance);
        console2.log("initialWETHBalance of claimant:", initialWETHBalance);

        vm.prank(UNICHAIN_TEST_ACCOUNT);
        distributor.claim(UNICHAIN_TEST_INDEX, UNICHAIN_TEST_ACCOUNT, tokens, amounts, proof);
        console2.log("post-claim USDC Balance of claimant:", IERC20(UNICHAIN_USDC).balanceOf(UNICHAIN_TEST_ACCOUNT));
        console2.log("post-claim WETH Balance of claimant:", IERC20(UNICHAIN_WETH).balanceOf(UNICHAIN_TEST_ACCOUNT));

        // Verify balances updated correctly
        assertEq(IERC20(UNICHAIN_USDC).balanceOf(UNICHAIN_TEST_ACCOUNT), initialUSDCBalance + amounts[0]);
        assertEq(IERC20(UNICHAIN_WETH).balanceOf(UNICHAIN_TEST_ACCOUNT), initialWETHBalance + amounts[1]);

        // Verify claim is marked as claimed
        assertTrue(distributor.isClaimed(UNICHAIN_TEST_INDEX));
    }

    // ============ CROSS-CHAIN WITHDRAW TESTS ============

    function testBase_WithdrawUnclaimed() public {
        _setupBase();

        // Fast forward past withdrawal time
        vm.roll(withdrawableAt + 1);

        uint256 initialBalance1 = IERC20(BASE_WETH).balanceOf(admin);
        uint256 initialBalance2 = IERC20(BASE_USDC).balanceOf(admin);

        address[] memory withdrawTokens = new address[](2);
        withdrawTokens[0] = BASE_WETH;
        withdrawTokens[1] = BASE_USDC;

        vm.prank(admin);
        distributor.withdrawUnclaimed(withdrawTokens, admin);

        // Verify tokens were withdrawn
        assertTrue(IERC20(BASE_WETH).balanceOf(admin) > initialBalance1);
        assertTrue(IERC20(BASE_USDC).balanceOf(admin) >= initialBalance2);
    }

    function testMainnet_WithdrawTooEarly() public {
        _setupMainnet();

        address[] memory withdrawTokens = new address[](2);
        withdrawTokens[0] = MAINNET_USDC;
        withdrawTokens[1] = MAINNET_WETH;

        vm.prank(admin);
        vm.expectRevert(WithdrawTooEarly.selector);
        distributor.withdrawUnclaimed(withdrawTokens, admin);
    }

    function testUnichain_WithdrawOnlyAdmin() public {
        _setupUnichain();

        vm.roll(withdrawableAt + 1);

        address[] memory withdrawTokens = new address[](2);
        withdrawTokens[0] = UNICHAIN_USDC;
        withdrawTokens[1] = UNICHAIN_WETH;

        vm.prank(address(0x456));
        vm.expectRevert(OnlyAdmin.selector);
        distributor.withdrawUnclaimed(withdrawTokens, admin);
    }

    // ============ HELPER FUNCTIONS ============

    function _setupBase() internal {
        vm.createSelectFork("base");

        withdrawableAt = block.number + 100;

        address[] memory tokens = new address[](2);
        tokens[0] = BASE_WETH;
        tokens[1] = BASE_USDC;

        distributor = new MerkleDistributor(BASE_MERKLE_ROOT, tokens, withdrawableAt, admin);
        _fundDistributor(BASE_WETH, BASE_USDC);
    }

    function _setupMainnet() internal {
        vm.createSelectFork("mainnet");

        withdrawableAt = block.number + 100;

        // Note: We need to include all 22 unique tokens from the mainnet data
        // For testing purposes, we'll just include the main ones
        address[] memory tokens = new address[](2);
        tokens[0] = MAINNET_USDC;
        tokens[1] = MAINNET_WETH;

        distributor = new MerkleDistributor(MAINNET_MERKLE_ROOT, tokens, withdrawableAt, admin);
        _fundDistributorMainnet(MAINNET_USDC, MAINNET_WETH);
    }

    function _setupUnichain() internal {
        vm.createSelectFork("unichain");

        withdrawableAt = block.number + 100;

        address[] memory tokens = new address[](2);
        tokens[0] = UNICHAIN_USDC;
        tokens[1] = UNICHAIN_WETH;

        distributor = new MerkleDistributor(UNICHAIN_MERKLE_ROOT, tokens, withdrawableAt, admin);
        _fundDistributorUnichain(UNICHAIN_USDC, UNICHAIN_WETH);
    }

    function _fundDistributor(address token1, address token2) internal {
        vm.startPrank(VAULT_ACCOUNT);

        uint256 vaultBalance1 = IERC20(token1).balanceOf(VAULT_ACCOUNT);
        uint256 vaultBalance2 = IERC20(token2).balanceOf(VAULT_ACCOUNT);

        console2.log("Base: Vault token1 balance:", vaultBalance1);
        console2.log("Base: Vault token2 balance:", vaultBalance2);

        uint256 toTransfer1 = 1 ether;
        uint256 toTransfer2 = 1000 * 10**6; // For USDC

        if (vaultBalance1 >= toTransfer1) {
            IERC20(token1).transfer(address(distributor), toTransfer1);
        } else if (vaultBalance1 > 0) {
            IERC20(token1).transfer(address(distributor), vaultBalance1);
        }

        if (vaultBalance2 >= toTransfer2) {
            IERC20(token2).transfer(address(distributor), toTransfer2);
        } else if (vaultBalance2 > 0) {
            IERC20(token2).transfer(address(distributor), vaultBalance2);
        }

        vm.stopPrank();
    }

    function _fundDistributorMainnet(address usdc, address weth) internal {
        vm.startPrank(VAULT_ACCOUNT);

        uint256 vaultUsdcBalance = IERC20(usdc).balanceOf(VAULT_ACCOUNT);
        uint256 vaultWethBalance = IERC20(weth).balanceOf(VAULT_ACCOUNT);

        console2.log("Mainnet: Vault USDC balance:", vaultUsdcBalance);
        console2.log("Mainnet: Vault WETH balance:", vaultWethBalance);

        // Transfer available balances
        if (vaultUsdcBalance > 0) {
            uint256 usdcToTransfer = vaultUsdcBalance > 10000 * 10**6 ? 10000 * 10**6 : vaultUsdcBalance;
            IERC20(usdc).transfer(address(distributor), usdcToTransfer);
        }

        if (vaultWethBalance > 0) {
            uint256 wethToTransfer = vaultWethBalance > 10 ether ? 10 ether : vaultWethBalance;
            IERC20(weth).transfer(address(distributor), wethToTransfer);
        }

        vm.stopPrank();
    }

    function _fundDistributorUnichain(address usdc, address weth) internal {
        vm.startPrank(VAULT_ACCOUNT);

        // Check if tokens exist on Unichain
        uint256 vaultUsdcBalance;
        uint256 vaultWethBalance;

        // Use try-catch in case tokens don't exist on Unichain
        try IERC20(usdc).balanceOf(VAULT_ACCOUNT) returns (uint256 balance) {
            vaultUsdcBalance = balance;
        } catch {
            console2.log("Unichain: usdc doesn't exist or has no balance");
        }

        try IERC20(weth).balanceOf(VAULT_ACCOUNT) returns (uint256 balance) {
            vaultWethBalance = balance;
        } catch {
            console2.log("Unichain: WETH doesn't exist or has no balance");
        }

        console2.log("Unichain: Vault usdc balance:", vaultUsdcBalance);
        console2.log("Unichain: Vault WETH balance:", vaultWethBalance);

        if (vaultUsdcBalance > 0) {
            IERC20(usdc).transfer(address(distributor), vaultUsdcBalance);
        }

        if (vaultWethBalance > 0) {
            IERC20(weth).transfer(address(distributor), vaultWethBalance);
        }

        vm.stopPrank();
    }

    function _getBaseProof() internal pure returns (bytes32[] memory) {
        bytes32[] memory proof = new bytes32[](9);
        proof[0] = 0xb56596733e85fde5bca61ea621db418addce504637f05734b5db98486b278517;
        proof[1] = 0xce1f34c5edc3ec207842184b82c022fc3dacf4aa290202b3ec90f1beb4c6fdfb;
        proof[2] = 0xd70d2533d6340436a0e68ef7ff259a49ab016d5d6e2053475b26cb3261e7306b;
        proof[3] = 0x95f284b81e092d0136daa75dfb6bcf735cecbea5bb6e19d11a3abc174d7aea73;
        proof[4] = 0xcd93858d46b1a4ccd503f263fed6cc1dd51ccd715207e22410e28f9a499ed7eb;
        proof[5] = 0x0eb97c00b8a77089f1b2a6d47f9261d8ad1f4c4eaa640a385b1738d2b0b2c360;
        proof[6] = 0xa4862d659cf3c56690c38ff4cd853864edad28f8ef5897b5dc63941b58ec6295;
        proof[7] = 0x986faa7573bfb93eb147edc1134cd67945e565e7833e0c7d21f3871c6c2c1db8;
        proof[8] = 0xae87bcf032087f2a8461aa1555b3b125d0ddab75842c4a0aa5bc5c289998a6ea;
        return proof;
    }

    // ============ INTEGRATION TESTS ============

    function testFullScenario_AllChains() public {
        console2.log("=== Testing Base Chain ===");
        testBase_ValidClaim();

        console2.log("\n=== Testing Ethereum Mainnet ===");
        testMainnet_ValidClaim();

        console2.log("\n=== Testing Unichain ===");
        testUnichain_ValidClaim();

        console2.log("\n=== All chain tests completed successfully ===");
    }

    // ============ COMPREHENSIVE CLAIM TESTS ============

    function testAllClaims_Base() public {
        _setupBaseWithFullFunding();

        // Read the merkle data JSON
        string memory json = vm.readFile("data/base-merkle-data.json");

        // Get all claim addresses
        string[] memory claimAddresses = vm.parseJsonKeys(json, ".claims");

        console2.log("Testing", claimAddresses.length, "claims on Base");

        uint256 successfulClaims = 0;
        uint256 failedClaims = 0;

        for (uint256 i = 0; i < claimAddresses.length; i++) {
            address claimant = vm.parseAddress(claimAddresses[i]);

            // Parse claim data
            string memory claimPath = string.concat(".claims.", vm.toString(claimant));
            uint256 index = vm.parseJsonUint(json, string.concat(claimPath, ".index"));

            address[] memory tokens = vm.parseJsonAddressArray(json, string.concat(claimPath, ".tokens"));
            uint256[] memory amounts = vm.parseJsonUintArray(json, string.concat(claimPath, ".amounts"));
            bytes32[] memory proof = vm.parseJsonBytes32Array(json, string.concat(claimPath, ".proof"));

            // Track initial balances
            uint256[] memory initialBalances = new uint256[](tokens.length);
            for (uint256 j = 0; j < tokens.length; j++) {
                initialBalances[j] = IERC20(tokens[j]).balanceOf(claimant);
            }

            // Execute claim
            vm.prank(claimant);
            try distributor.claim(index, claimant, tokens, amounts, proof) {
                // Verify balances updated correctly
                bool balancesCorrect = true;
                for (uint256 j = 0; j < tokens.length; j++) {
                    uint256 expectedBalance = initialBalances[j] + amounts[j];
                    uint256 actualBalance = IERC20(tokens[j]).balanceOf(claimant);
                    if (actualBalance != expectedBalance) {
                        console2.log("Balance mismatch for token", tokens[j], "claimant", claimant);
                        console2.log("Expected:", expectedBalance, "Actual:", actualBalance);
                        balancesCorrect = false;
                    }
                }

                if (balancesCorrect && distributor.isClaimed(index)) {
                    successfulClaims++;
                } else {
                    failedClaims++;
                    console2.log("Claim verification failed for", claimant, "at index", index);
                }
            } catch Error(string memory reason) {
                failedClaims++;
                console2.log("Claim failed for", claimant, ":", reason);
            } catch {
                failedClaims++;
                console2.log("Claim failed for", claimant, "with unknown error");
            }
        }

        console2.log("Base claims completed - Success:", successfulClaims, "Failed:", failedClaims);
        assertEq(failedClaims, 0, "All claims should succeed");
    }

    function testAllClaims_Mainnet() public {
        _setupMainnetWithFullFunding();

        // Read the merkle data JSON
        string memory json = vm.readFile("data/mainnet-merkle-data.json");

        // Get all claim addresses
        string[] memory claimAddresses = vm.parseJsonKeys(json, ".claims");

        console2.log("Testing", claimAddresses.length, "claims on Mainnet");

        uint256 successfulClaims = 0;
        uint256 failedClaims = 0;

        for (uint256 i = 0; i < claimAddresses.length; i++) {
            address claimant = vm.parseAddress(claimAddresses[i]);

            // Parse claim data
            string memory claimPath = string.concat(".claims.", vm.toString(claimant));
            uint256 index = vm.parseJsonUint(json, string.concat(claimPath, ".index"));

            address[] memory tokens = vm.parseJsonAddressArray(json, string.concat(claimPath, ".tokens"));
            uint256[] memory amounts = vm.parseJsonUintArray(json, string.concat(claimPath, ".amounts"));
            bytes32[] memory proof = vm.parseJsonBytes32Array(json, string.concat(claimPath, ".proof"));

            // Track initial balances
            uint256[] memory initialBalances = new uint256[](tokens.length);
            for (uint256 j = 0; j < tokens.length; j++) {
                initialBalances[j] = IERC20(tokens[j]).balanceOf(claimant);
            }

            // Execute claim
            vm.prank(claimant);
            try distributor.claim(index, claimant, tokens, amounts, proof) {
                // Verify balances updated correctly
                bool balancesCorrect = true;
                for (uint256 j = 0; j < tokens.length; j++) {
                    uint256 expectedBalance = initialBalances[j] + amounts[j];
                    uint256 actualBalance = IERC20(tokens[j]).balanceOf(claimant);
                    if (actualBalance != expectedBalance) {
                        console2.log("Balance mismatch for token", tokens[j], "claimant", claimant);
                        console2.log("Expected:", expectedBalance, "Actual:", actualBalance);
                        balancesCorrect = false;
                    }
                }

                if (balancesCorrect && distributor.isClaimed(index)) {
                    successfulClaims++;
                } else {
                    failedClaims++;
                    console2.log("Claim verification failed for", claimant, "at index", index);
                }
            } catch Error(string memory reason) {
                failedClaims++;
                console2.log("Claim failed for", claimant, ":", reason);
            } catch {
                failedClaims++;
                console2.log("Claim failed for", claimant, "with unknown error");
            }
        }

        console2.log("Mainnet claims completed - Success:", successfulClaims, "Failed:", failedClaims);
        assertEq(failedClaims, 0, "All claims should succeed");
    }

    function testAllClaims_Unichain() public {
        _setupUnichainWithFullFunding();

        // Read the merkle data JSON
        string memory json = vm.readFile("data/unichain-merkle-data.json");

        // Get all claim addresses
        string[] memory claimAddresses = vm.parseJsonKeys(json, ".claims");

        console2.log("Testing", claimAddresses.length, "claims on Unichain");

        uint256 successfulClaims = 0;
        uint256 failedClaims = 0;

        for (uint256 i = 0; i < claimAddresses.length; i++) {
            address claimant = vm.parseAddress(claimAddresses[i]);

            // Parse claim data
            string memory claimPath = string.concat(".claims.", vm.toString(claimant));
            uint256 index = vm.parseJsonUint(json, string.concat(claimPath, ".index"));

            address[] memory tokens = vm.parseJsonAddressArray(json, string.concat(claimPath, ".tokens"));
            uint256[] memory amounts = vm.parseJsonUintArray(json, string.concat(claimPath, ".amounts"));
            bytes32[] memory proof = vm.parseJsonBytes32Array(json, string.concat(claimPath, ".proof"));

            // Track initial balances
            uint256[] memory initialBalances = new uint256[](tokens.length);
            for (uint256 j = 0; j < tokens.length; j++) {
                initialBalances[j] = IERC20(tokens[j]).balanceOf(claimant);
            }

            // Execute claim
            vm.prank(claimant);
            try distributor.claim(index, claimant, tokens, amounts, proof) {
                // Verify balances updated correctly
                bool balancesCorrect = true;
                for (uint256 j = 0; j < tokens.length; j++) {
                    uint256 expectedBalance = initialBalances[j] + amounts[j];
                    uint256 actualBalance = IERC20(tokens[j]).balanceOf(claimant);
                    if (actualBalance != expectedBalance) {
                        console2.log("Balance mismatch for token", tokens[j], "claimant", claimant);
                        console2.log("Expected:", expectedBalance, "Actual:", actualBalance);
                        balancesCorrect = false;
                    }
                }

                if (balancesCorrect && distributor.isClaimed(index)) {
                    successfulClaims++;
                } else {
                    failedClaims++;
                    console2.log("Claim verification failed for", claimant, "at index", index);
                }
            } catch Error(string memory reason) {
                failedClaims++;
                console2.log("Claim failed for", claimant, ":", reason);
            } catch {
                failedClaims++;
                console2.log("Claim failed for", claimant, "with unknown error");
            }
        }

        console2.log("Unichain claims completed - Success:", successfulClaims, "Failed:", failedClaims);
        assertEq(failedClaims, 0, "All claims should succeed");
    }

    // ============ SETUP FUNCTIONS WITH FULL FUNDING ============

    function _setupBaseWithFullFunding() internal {
        vm.createSelectFork("base");

        withdrawableAt = block.number + 100;

        // Read token list from JSON
        string memory json = vm.readFile("data/base-merkle-data.json");
        address[] memory tokens = vm.parseJsonAddressArray(json, ".tokenList");

        distributor = new MerkleDistributor(BASE_MERKLE_ROOT, tokens, withdrawableAt, admin);

        // Fund distributor with exact amounts needed
        _fundDistributorWithExactAmounts(json, tokens);
    }

    function _setupMainnetWithFullFunding() internal {
        vm.createSelectFork("mainnet");

        withdrawableAt = block.number + 100;

        // Read token list from JSON
        string memory json = vm.readFile("data/mainnet-merkle-data.json");
        address[] memory tokens = vm.parseJsonAddressArray(json, ".tokenList");

        distributor = new MerkleDistributor(MAINNET_MERKLE_ROOT, tokens, withdrawableAt, admin);

        // Fund distributor with exact amounts needed
        _fundDistributorWithExactAmounts(json, tokens);
    }

    function _setupUnichainWithFullFunding() internal {
        vm.createSelectFork("unichain");

        withdrawableAt = block.number + 100;

        // Read token list from JSON
        string memory json = vm.readFile("data/unichain-merkle-data.json");
        address[] memory tokens = vm.parseJsonAddressArray(json, ".tokenList");

        distributor = new MerkleDistributor(UNICHAIN_MERKLE_ROOT, tokens, withdrawableAt, admin);

        // Fund distributor with exact amounts needed
        _fundDistributorWithExactAmounts(json, tokens);
    }

    function _fundDistributorWithExactAmounts(string memory json, address[] memory tokens) internal {
        for (uint256 i = 0; i < tokens.length; i++) {
            address token = tokens[i];

            // Get the total amount needed for this token
            string memory amountPath = string.concat(".tokenTotals.", vm.toString(token));
            uint256 totalNeeded = vm.parseJsonUint(json, amountPath);

            if (totalNeeded > 0) {
                // Give the vault account the exact amount needed
                vm.startPrank(VAULT_ACCOUNT);

                // Use deal to set balance directly
                deal(token, VAULT_ACCOUNT, totalNeeded);

                // Transfer to distributor
                IERC20(token).transfer(address(distributor), totalNeeded);

                vm.stopPrank();

                console2.log("Funded distributor with", totalNeeded, "of token", token);
            }
        }
    }

    // ============ SECURITY TESTS ============

    function testBase_CannotClaimForOthers() public {
        _setupBase();

        address attacker = address(0xBEEF);

        // Set up legitimate claim data for BASE_TEST_ACCOUNT
        address[] memory tokens = new address[](2);
        tokens[0] = BASE_WETH;
        tokens[1] = BASE_USDC;

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 2938061841488396; // WETH amount from base data
        amounts[1] = 0; // USDC amount from base data

        bytes32[] memory proof = _getBaseProof();

        // Try to claim someone else's tokens as the attacker
        vm.prank(attacker);
        vm.expectRevert("Only the claim owner may execute their claim");
        distributor.claim(BASE_TEST_INDEX, BASE_TEST_ACCOUNT, tokens, amounts, proof);

        // Verify the legitimate account can still claim their tokens
        vm.prank(BASE_TEST_ACCOUNT);
        distributor.claim(BASE_TEST_INDEX, BASE_TEST_ACCOUNT, tokens, amounts, proof);

        // Verify claim is marked as claimed for the correct index
        assertTrue(distributor.isClaimed(BASE_TEST_INDEX));
    }

    function testMainnet_CannotClaimForOthers() public {
        _setupMainnet();

        address attacker = address(0xDEAD);

        // Set up legitimate claim data for MAINNET_TEST_ACCOUNT
        address[] memory tokens = new address[](2);
        tokens[0] = MAINNET_USDC;
        tokens[1] = MAINNET_WETH;

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 224064496; // USDC amount
        amounts[1] = 0; // WETH amount

        bytes32[] memory proof = new bytes32[](10);
        proof[0] = 0x363cba88087d853d43d49109015f03668288abdc49d919b290e3cfa7d121a8a0;
        proof[1] = 0x7a49e9fd41dc9688823abb51c7edb1e06ec0c300e268f1a3e9b10cbd05c5aa84;
        proof[2] = 0x906bc7b7ce8c55addbb68e5138d24f90e67a3f115a5399efcd8b739be9d0380d;
        proof[3] = 0x1c79464a41f0363736d95ffdd573035d95f38afad0c6048dc9779da60defe03c;
        proof[4] = 0xcd3cceefc2f4ac8fa709937b5e56de5e837b9a273e15b575fa20f5e5a189350e;
        proof[5] = 0x4aa10617259eab761dcee883261f2f9e35d4fe6903a1eb482c1249e484d8dce2;
        proof[6] = 0xca0bd0bd7b26ea0c84404649b6f8ec9a7eb6de6823848b6360a6c25d01539205;
        proof[7] = 0x15fc330cfa367ef573198d2dadc7ee8a67db1c7079cf9968325d5a339d94fed9;
        proof[8] = 0x555b67fc2291ed58234dfb9893d7c23f7af2b75d3599f2010def29a7ef56a0d1;
        proof[9] = 0x51365528c93bed96fffd163823a44f35017da3921ad36c481746bb654a81fa69;

        // Attacker tries to claim
        vm.prank(attacker);
        vm.expectRevert("Only the claim owner may execute their claim");
        distributor.claim(MAINNET_TEST_INDEX, MAINNET_TEST_ACCOUNT, tokens, amounts, proof);

        // Verify legitimate account can still claim
        vm.prank(MAINNET_TEST_ACCOUNT);
        distributor.claim(MAINNET_TEST_INDEX, MAINNET_TEST_ACCOUNT, tokens, amounts, proof);

        assertTrue(distributor.isClaimed(MAINNET_TEST_INDEX));
    }

    function testBase_InvalidProofVariations() public {
        _setupBase();

        address[] memory tokens = new address[](2);
        tokens[0] = BASE_WETH;
        tokens[1] = BASE_USDC;

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 2938061841488396;
        amounts[1] = 0;

        // Test 1: Empty proof array
        bytes32[] memory emptyProof = new bytes32[](0);
        vm.prank(BASE_TEST_ACCOUNT);
        vm.expectRevert(InvalidProof.selector);
        distributor.claim(BASE_TEST_INDEX, BASE_TEST_ACCOUNT, tokens, amounts, emptyProof);

        // Test 2: Wrong length proof (too short)
        bytes32[] memory shortProof = new bytes32[](2);
        shortProof[0] = bytes32(uint256(1));
        shortProof[1] = bytes32(uint256(2));

        vm.prank(BASE_TEST_ACCOUNT);
        vm.expectRevert(InvalidProof.selector);
        distributor.claim(BASE_TEST_INDEX, BASE_TEST_ACCOUNT, tokens, amounts, shortProof);

        // Test 3: Correct length but wrong values
        bytes32[] memory wrongProof = new bytes32[](9);
        for (uint i = 0; i < 9; i++) {
            wrongProof[i] = bytes32(uint256(i + 1));
        }

        vm.prank(BASE_TEST_ACCOUNT);
        vm.expectRevert(InvalidProof.selector);
        distributor.claim(BASE_TEST_INDEX, BASE_TEST_ACCOUNT, tokens, amounts, wrongProof);

        // Test 4: All zero proof with correct length
        bytes32[] memory zeroProof = new bytes32[](9);
        // Array is already initialized with zeros

        vm.prank(BASE_TEST_ACCOUNT);
        vm.expectRevert(InvalidProof.selector);
        distributor.claim(BASE_TEST_INDEX, BASE_TEST_ACCOUNT, tokens, amounts, zeroProof);
    }

    function testMainnet_WrongAmountsCantClaim() public {
        _setupMainnet();

        address[] memory tokens = new address[](2);
        tokens[0] = MAINNET_USDC;
        tokens[1] = MAINNET_WETH;

        // Correct proof but wrong amounts
        uint256[] memory wrongAmounts = new uint256[](2);
        wrongAmounts[0] = 224064496 + 1; // USDC amount + 1 (wrong!)
        wrongAmounts[1] = 0;

        bytes32[] memory proof = new bytes32[](10);
        proof[0] = 0x363cba88087d853d43d49109015f03668288abdc49d919b290e3cfa7d121a8a0;
        proof[1] = 0x7a49e9fd41dc9688823abb51c7edb1e06ec0c300e268f1a3e9b10cbd05c5aa84;
        proof[2] = 0x906bc7b7ce8c55addbb68e5138d24f90e67a3f115a5399efcd8b739be9d0380d;
        proof[3] = 0x1c79464a41f0363736d95ffdd573035d95f38afad0c6048dc9779da60defe03c;
        proof[4] = 0xcd3cceefc2f4ac8fa709937b5e56de5e837b9a273e15b575fa20f5e5a189350e;
        proof[5] = 0x4aa10617259eab761dcee883261f2f9e35d4fe6903a1eb482c1249e484d8dce2;
        proof[6] = 0xca0bd0bd7b26ea0c84404649b6f8ec9a7eb6de6823848b6360a6c25d01539205;
        proof[7] = 0x15fc330cfa367ef573198d2dadc7ee8a67db1c7079cf9968325d5a339d94fed9;
        proof[8] = 0x555b67fc2291ed58234dfb9893d7c23f7af2b75d3599f2010def29a7ef56a0d1;
        proof[9] = 0x51365528c93bed96fffd163823a44f35017da3921ad36c481746bb654a81fa69;

        // Should fail with wrong amounts
        vm.prank(MAINNET_TEST_ACCOUNT);
        vm.expectRevert(InvalidProof.selector);
        distributor.claim(MAINNET_TEST_INDEX, MAINNET_TEST_ACCOUNT, tokens, wrongAmounts, proof);
    }

    function testBase_WrongIndexCantClaim() public {
        _setupBase();

        address[] memory tokens = new address[](2);
        tokens[0] = BASE_WETH;
        tokens[1] = BASE_USDC;

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 2938061841488396;
        amounts[1] = 0;

        bytes32[] memory proof = _getBaseProof();

        // Try to claim with wrong index (BASE_TEST_INDEX + 1)
        vm.prank(BASE_TEST_ACCOUNT);
        vm.expectRevert(InvalidProof.selector);
        distributor.claim(BASE_TEST_INDEX + 1, BASE_TEST_ACCOUNT, tokens, amounts, proof);
    }

    function testUnichain_CannotClaimForOthers() public {
        _setupUnichain();

        address attacker = address(0xCAFE);

        address[] memory tokens = new address[](2);
        tokens[0] = UNICHAIN_USDC;
        tokens[1] = UNICHAIN_WETH;

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 0;
        amounts[1] = 1029089761109200;

        bytes32[] memory proof = new bytes32[](9);
        proof[0] = 0x048716ff63a8b4cf963bdb616c80daca2eb60bdca275e4761e9c3435623c1fd9;
        proof[1] = 0x69bc509a3b1de64a50df3ec92b8550e3d111812637f88dd3ddb8c0cb29c3b97f;
        proof[2] = 0x921f81e5b53611d4242d3609d8fab79f44d3dcfe1d5489f83aaecd2fad68501f;
        proof[3] = 0xcd99617124b3f50fe9f3d6cc77c1398ee53f84d72d69216d78145cd64d6e3cde;
        proof[4] = 0xdd207c72b1ab17233cbd99a7d359cba6a652bc424e80962f1be5e901ef9c3e67;
        proof[5] = 0x8ee783c12931adb244f11ca8a252b2ea58130c0d31f76442aa2f9493d81ac76e;
        proof[6] = 0xa709a44851cb2a58259c9d49a4dfb217105a33509d67011dd1d93d17cdce5812;
        proof[7] = 0xb3f3034336424dc075eb52778bdbf39c0002fc453f90b58f8446287a33ab0379;
        proof[8] = 0xb467125908b2fa01fed95f324eabb81d5ec16d6e077d54f479c3208146892ac2;

        // Attacker tries to claim someone else's tokens
        vm.prank(attacker);
        vm.expectRevert("Only the claim owner may execute their claim");
        distributor.claim(UNICHAIN_TEST_INDEX, UNICHAIN_TEST_ACCOUNT, tokens, amounts, proof);

        // Legitimate user can still claim
        vm.prank(UNICHAIN_TEST_ACCOUNT);
        distributor.claim(UNICHAIN_TEST_INDEX, UNICHAIN_TEST_ACCOUNT, tokens, amounts, proof);

        assertTrue(distributor.isClaimed(UNICHAIN_TEST_INDEX));
    }

    function testBase_ProofIsAddressSpecific() public {
        _setupBase();

        address[] memory tokens = new address[](2);
        tokens[0] = BASE_WETH;
        tokens[1] = BASE_USDC;

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 2938061841488396;
        amounts[1] = 0;

        bytes32[] memory proof = _getBaseProof();

        // Try to use BASE_TEST_ACCOUNT's proof but claim to a different address
        address wrongRecipient = address(0x9999);

        vm.prank(BASE_TEST_ACCOUNT);
        vm.expectRevert("Only the claim owner may execute their claim");
        distributor.claim(BASE_TEST_INDEX, wrongRecipient, tokens, amounts, proof);
    }
}
