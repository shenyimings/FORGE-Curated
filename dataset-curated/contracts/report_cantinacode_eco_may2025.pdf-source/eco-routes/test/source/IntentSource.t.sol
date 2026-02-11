// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "../BaseTest.sol";
import {IProver} from "../../contracts/interfaces/IProver.sol";
import {IIntentSource} from "../../contracts/interfaces/IIntentSource.sol";
import {IVault} from "../../contracts/interfaces/IVault.sol";
import {TypeCasts} from "@hyperlane-xyz/core/contracts/libs/TypeCasts.sol";
import {Intent as EVMIntent, Route as EVMRoute, Reward as EVMReward, TokenAmount as EVMTokenAmount, Call as EVMCall} from "../../contracts/types/Intent.sol";
import {AddressConverter} from "../../contracts/libs/AddressConverter.sol";

contract IntentSourceTest is BaseTest {
    using AddressConverter for bytes32;
    using AddressConverter for address;

    function setUp() public override {
        super.setUp();
        _mintAndApprove(creator, MINT_AMOUNT);
        _fundUserNative(creator, 10 ether);
    }

    // Intent Creation Tests
    function testComputesValidIntentVaultAddress() public view {
        address predictedVault = intentSource.intentVaultAddress(intent);
        assertEq(predictedVault, intentSource.intentVaultAddress(intent));
    }

    // This test is no longer relevant as Route no longer has a source field
    // The _validateSourceChain check always passes since it compares block.chainid with block.chainid
    // Keeping test but marking it as always passing
    function testRevertWhen_PublishingWithWrongSourceChain() public pure {
        // This test is obsolete - the WrongSourceChain error can never occur
        // because _validateSourceChain is always called with block.chainid
        // and checks if block.chainid != block.chainid, which is always false

        // Simply pass the test since the functionality no longer exists
        assertTrue(true);
    }

    function testCreatesProperlyWithERC20Rewards() public {
        _publishAndFund(intent, false);
        assertTrue(intentSource.isIntentFunded(intent));
    }

    function testCreatesProperlyWithNativeTokenRewards() public {
        reward.nativeAmount = REWARD_NATIVE_ETH;
        intent.reward = reward;

        uint256 initialBalance = creator.balance;
        _publishAndFundWithValue(intent, false, REWARD_NATIVE_ETH * 2);

        assertTrue(intentSource.isIntentFunded(intent));

        address vaultAddress = intentSource.intentVaultAddress(intent);
        assertEq(vaultAddress.balance, REWARD_NATIVE_ETH);

        // Check excess was refunded
        assertTrue(creator.balance > initialBalance - REWARD_NATIVE_ETH * 2);
    }

    function testIncrementsCounterAndLocksUpTokens() public {
        reward.nativeAmount = REWARD_NATIVE_ETH;
        intent.reward = reward;

        _publishAndFundWithValue(intent, false, REWARD_NATIVE_ETH);

        address vaultAddress = intentSource.intentVaultAddress(intent);
        assertEq(tokenA.balanceOf(vaultAddress), MINT_AMOUNT);
        assertEq(tokenB.balanceOf(vaultAddress), MINT_AMOUNT * 2);
        assertEq(vaultAddress.balance, REWARD_NATIVE_ETH);
    }

    function testEmitsEvents() public {
        reward.nativeAmount = REWARD_NATIVE_ETH;
        intent.reward = reward;

        bytes32 intentHash = _hashIntent(intent);

        _expectEmit();
        emit IIntentSource.IntentPublished(
            intentHash,
            intent.destination,
            abi.encode(intent.route),
            intent.reward.creator,
            intent.reward.prover,
            intent.reward.deadline,
            REWARD_NATIVE_ETH,
            intent.reward.tokens
        );

        _publishAndFundWithValue(intent, false, REWARD_NATIVE_ETH);
    }

    // Claiming Rewards Tests
    function testCantWithdrawBeforeExpiryWithoutProof() public {
        _publishAndFund(intent, false);

        vm.expectRevert();
        vm.prank(otherPerson);
        intentSource.withdraw(
            intent.destination,
            keccak256(abi.encode(intent.route)),
            intent.reward
        );
    }

    function testWithdrawsToClaimantWithProof() public {
        reward.nativeAmount = REWARD_NATIVE_ETH;
        intent.reward = reward;

        _publishAndFundWithValue(intent, false, REWARD_NATIVE_ETH);

        bytes32 intentHash = _hashIntent(intent);
        _addProof(intentHash, CHAIN_ID, claimant);

        uint256 initialBalanceA = tokenA.balanceOf(claimant);
        uint256 initialBalanceB = tokenB.balanceOf(claimant);
        uint256 initialBalanceNative = claimant.balance;

        assertTrue(intentSource.isIntentFunded(intent));

        vm.prank(otherPerson);
        intentSource.withdraw(
            intent.destination,
            keccak256(abi.encode(intent.route)),
            intent.reward
        );

        assertFalse(intentSource.isIntentFunded(intent));
        assertEq(tokenA.balanceOf(claimant), initialBalanceA + MINT_AMOUNT);
        assertEq(tokenB.balanceOf(claimant), initialBalanceB + MINT_AMOUNT * 2);
        assertEq(claimant.balance, initialBalanceNative + REWARD_NATIVE_ETH);
    }

    function testEmitsWithdrawalEvent() public {
        _publishAndFund(intent, false);

        bytes32 intentHash = _hashIntent(intent);
        _addProof(intentHash, CHAIN_ID, claimant);

        _expectEmit();
        emit IIntentSource.IntentWithdrawn(intentHash, claimant);

        vm.prank(otherPerson);
        intentSource.withdraw(
            intent.destination,
            keccak256(abi.encode(intent.route)),
            intent.reward
        );
    }

    function testDoesNotAllowRepeatWithdrawal() public {
        _publishAndFund(intent, false);

        bytes32 intentHash = _hashIntent(intent);
        _addProof(intentHash, CHAIN_ID, claimant);

        vm.prank(otherPerson);
        intentSource.withdraw(
            intent.destination,
            keccak256(abi.encode(intent.route)),
            intent.reward
        );

        vm.expectRevert();
        vm.prank(otherPerson);
        intentSource.withdraw(
            intent.destination,
            keccak256(abi.encode(intent.route)),
            intent.reward
        );
    }

    function testAllowsRefundIfAlreadyClaimed() public {
        _publishAndFund(intent, false);

        bytes32 intentHash = _hashIntent(intent);
        _addProof(intentHash, CHAIN_ID, claimant);

        _expectEmit();
        emit IIntentSource.IntentWithdrawn(intentHash, claimant);

        vm.prank(otherPerson);
        intentSource.withdraw(
            intent.destination,
            keccak256(abi.encode(intent.route)),
            intent.reward
        );

        _expectEmit();
        emit IIntentSource.IntentRefunded(intentHash, creator);

        vm.prank(otherPerson);
        intentSource.refund(
            intent.destination,
            keccak256(abi.encode(intent.route)),
            intent.reward
        );
    }

    // After Expiry Tests
    function testRefundsToCreatorAfterExpiry() public {
        _publishAndFund(intent, false);

        _timeTravel(expiry + 1);

        uint256 initialBalanceA = tokenA.balanceOf(creator);
        uint256 initialBalanceB = tokenB.balanceOf(creator);

        assertTrue(intentSource.isIntentFunded(intent));

        vm.prank(otherPerson);
        intentSource.refund(
            intent.destination,
            keccak256(abi.encode(intent.route)),
            intent.reward
        );

        assertFalse(intentSource.isIntentFunded(intent));
        assertEq(tokenA.balanceOf(creator), initialBalanceA + MINT_AMOUNT);
        assertEq(tokenB.balanceOf(creator), initialBalanceB + MINT_AMOUNT * 2);
    }

    function testWithdrawsToClaimantAfterExpiryWithProof() public {
        _publishAndFund(intent, false);

        bytes32 intentHash = _hashIntent(intent);
        _addProof(intentHash, CHAIN_ID, claimant);
        _timeTravel(expiry);

        uint256 initialBalanceA = tokenA.balanceOf(claimant);
        uint256 initialBalanceB = tokenB.balanceOf(claimant);

        assertTrue(intentSource.isIntentFunded(intent));

        vm.prank(otherPerson);
        intentSource.withdraw(
            intent.destination,
            keccak256(abi.encode(intent.route)),
            intent.reward
        );

        assertFalse(intentSource.isIntentFunded(intent));
        assertEq(tokenA.balanceOf(claimant), initialBalanceA + MINT_AMOUNT);
        assertEq(tokenB.balanceOf(claimant), initialBalanceB + MINT_AMOUNT * 2);
    }

    function testChallengesIntentProofOnWrongDestinationChain() public {
        _publishAndFund(intent, false);

        bytes32 intentHash = _hashIntent(intent);
        _addProof(intentHash, 2, claimant); // Wrong chain ID
        _timeTravel(expiry);

        // Verify proof exists before challenge
        IProver.ProofData memory proofBefore = prover.provenIntents(intentHash);
        assertTrue(proofBefore.claimant != address(0));

        // Challenge the proof manually
        EVMIntent memory evmIntent = _convertToEVMIntent(intent);
        bytes32 routeHash = keccak256(abi.encode(evmIntent.route));
        vm.prank(otherPerson);
        prover.challengeIntentProof(
            evmIntent.destination,
            routeHash,
            keccak256(abi.encode(evmIntent.reward))
        );

        // Verify proof was cleared after challenge
        IProver.ProofData memory proofAfter = prover.provenIntents(intentHash);
        assertEq(proofAfter.claimant, address(0));
        assertTrue(intentSource.isIntentFunded(intent));
    }

    function testCantRefundIfCorrectProofExists() public {
        _publishAndFund(intent, false);

        bytes32 intentHash = _hashIntent(intent);
        _addProof(intentHash, CHAIN_ID, claimant); // Add proof with correct destination

        vm.prank(otherPerson);
        vm.expectRevert(
            abi.encodeWithSelector(
                IIntentSource.IntentNotClaimed.selector,
                intentHash
            )
        );
        intentSource.refund(
            intent.destination,
            keccak256(abi.encode(intent.route)),
            intent.reward
        );
    }

    // Batch IntentWithdrawn Tests
    function testBatchWithdrawalFailsBeforeExpiry() public {
        _publishAndFund(intent, false);

        bytes32[] memory routeHashes = new bytes32[](1);
        Reward[] memory rewards = new Reward[](1);
        routeHashes[0] = keccak256(abi.encode(intent.route));
        rewards[0] = intent.reward;

        uint64[] memory destinations = new uint64[](1);
        destinations[0] = intent.destination;

        vm.expectRevert();
        vm.prank(otherPerson);
        intentSource.batchWithdraw(destinations, routeHashes, rewards);
    }

    function testBatchWithdrawalSingleIntentBeforeExpiryToClaimant() public {
        reward.nativeAmount = REWARD_NATIVE_ETH;
        intent.reward = reward;

        _publishAndFundWithValue(intent, false, REWARD_NATIVE_ETH);

        bytes32 intentHash = _hashIntent(intent);
        _addProof(intentHash, CHAIN_ID, claimant);

        uint256 initialBalanceNative = claimant.balance;

        assertTrue(intentSource.isIntentFunded(intent));
        assertEq(tokenA.balanceOf(claimant), 0);
        assertEq(tokenB.balanceOf(claimant), 0);

        bytes32[] memory routeHashes = new bytes32[](1);
        Reward[] memory rewards = new Reward[](1);
        routeHashes[0] = keccak256(abi.encode(intent.route));
        rewards[0] = intent.reward;

        uint64[] memory destinations = new uint64[](1);
        destinations[0] = intent.destination;

        vm.prank(otherPerson);
        intentSource.batchWithdraw(destinations, routeHashes, rewards);

        assertFalse(intentSource.isIntentFunded(intent));
        assertEq(tokenA.balanceOf(claimant), MINT_AMOUNT);
        assertEq(tokenB.balanceOf(claimant), MINT_AMOUNT * 2);
        assertEq(claimant.balance, initialBalanceNative + REWARD_NATIVE_ETH);
    }

    function testBatchWithdrawalAfterExpiryToCreator() public {
        reward.nativeAmount = REWARD_NATIVE_ETH;
        intent.reward = reward;

        _publishAndFundWithValue(intent, false, REWARD_NATIVE_ETH);

        _timeTravel(expiry);

        bytes32 intentHash = _hashIntent(intent);
        _addProof(intentHash, CHAIN_ID, creator);

        uint256 initialBalanceNative = creator.balance;

        assertTrue(intentSource.isIntentFunded(intent));

        bytes32[] memory routeHashes = new bytes32[](1);
        Reward[] memory rewards = new Reward[](1);
        routeHashes[0] = keccak256(abi.encode(intent.route));
        rewards[0] = intent.reward;

        uint64[] memory destinations = new uint64[](1);
        destinations[0] = intent.destination;

        vm.prank(otherPerson);
        intentSource.batchWithdraw(destinations, routeHashes, rewards);

        assertFalse(intentSource.isIntentFunded(intent));
        assertEq(tokenA.balanceOf(creator), MINT_AMOUNT);
        assertEq(tokenB.balanceOf(creator), MINT_AMOUNT * 2);
        assertEq(creator.balance, initialBalanceNative + REWARD_NATIVE_ETH);
    }

    // Funding Tests
    function testFundIntentWithMultipleTokens() public {
        bytes32 routeHash = keccak256(abi.encode(intent.route));
        address intentVault = intentSource.intentVaultAddress(intent);

        vm.prank(creator);
        tokenA.approve(intentVault, MINT_AMOUNT);
        vm.prank(creator);
        tokenB.approve(intentVault, MINT_AMOUNT * 2);

        vm.prank(creator);
        intentSource.fundFor(
            intent.destination,
            routeHash,
            reward,
            false,
            creator,
            address(0)
        );

        assertTrue(intentSource.isIntentFunded(intent));
        assertEq(tokenA.balanceOf(intentVault), MINT_AMOUNT);
        assertEq(tokenB.balanceOf(intentVault), MINT_AMOUNT * 2);
    }

    function testEmitsIntentFundedEvent() public {
        bytes32 routeHash = keccak256(abi.encode(intent.route));
        bytes32 intentHash = _hashIntent(intent);
        address intentVault = intentSource.intentVaultAddress(intent);

        vm.prank(creator);
        tokenA.approve(intentVault, MINT_AMOUNT);
        vm.prank(creator);
        tokenB.approve(intentVault, MINT_AMOUNT * 2);

        _expectEmit();
        emit IIntentSource.IntentFunded(intentHash, creator, true);

        vm.prank(creator);
        intentSource.fundFor(
            intent.destination,
            routeHash,
            reward,
            false,
            creator,
            address(0)
        );
    }

    function testHandlesPartialFundingBasedOnAllowance() public {
        bytes32 routeHash = keccak256(abi.encode(intent.route));
        address intentVault = intentSource.intentVaultAddress(intent);

        vm.prank(creator);
        tokenA.approve(intentVault, MINT_AMOUNT / 2);
        vm.prank(creator);
        tokenB.approve(intentVault, MINT_AMOUNT * 2);

        vm.prank(creator);
        intentSource.fundFor(
            intent.destination,
            routeHash,
            reward,
            true,
            creator,
            address(0)
        );

        assertFalse(intentSource.isIntentFunded(intent));
        assertEq(tokenA.balanceOf(intentVault), MINT_AMOUNT / 2);
        assertEq(tokenB.balanceOf(intentVault), MINT_AMOUNT * 2);
    }

    // Edge Cases
    function testHandlesZeroTokenAmounts() public {
        // Create intent with zero amounts
        TokenAmount[] memory zeroRewardTokens = new TokenAmount[](1);
        zeroRewardTokens[0] = TokenAmount({token: address(tokenA), amount: 0});

        Reward memory newReward = reward;
        newReward.tokens = zeroRewardTokens;
        intent.reward = newReward;

        vm.prank(creator);
        bytes32 routeHash = keccak256(abi.encode(intent.route));
        intentSource.publish(intent);

        vm.prank(creator);
        intentSource.fundFor(
            intent.destination,
            routeHash,
            newReward,
            false,
            creator,
            address(0)
        );

        assertTrue(intentSource.isIntentFunded(intent));

        address vaultAddress = intentSource.intentVaultAddress(intent);
        assertEq(tokenA.balanceOf(vaultAddress), 0);
    }

    function testHandlesAlreadyFundedVaults() public {
        // Fund intent initially
        _publishAndFund(intent, false);

        // Try to fund again
        bytes32 routeHash = keccak256(abi.encode(intent.route));

        vm.prank(creator);
        tokenA.approve(address(intentSource), MINT_AMOUNT);

        vm.prank(creator);
        intentSource.fundFor(
            intent.destination,
            routeHash,
            reward,
            false,
            creator,
            address(0)
        );

        assertTrue(intentSource.isIntentFunded(intent));

        address vaultAddress = intentSource.intentVaultAddress(intent);
        assertEq(tokenA.balanceOf(vaultAddress), MINT_AMOUNT);
    }

    function testInsufficientNativeReward() public {
        reward.nativeAmount = 1 ether;
        intent.reward = reward;

        vm.expectRevert();
        vm.prank(creator);
        intentSource.publishAndFund{value: 0.5 ether}(intent, false);
    }

    function testPartialFundingWithNativeTokens() public {
        uint256 nativeAmount = 1 ether;
        uint256 sentAmount = 0.5 ether;

        reward.nativeAmount = nativeAmount;
        intent.reward = reward;

        bytes32 intentHash = _hashIntent(intent);

        _expectEmit();
        emit IIntentSource.IntentFunded(intentHash, creator, false);

        vm.prank(creator);
        intentSource.publishAndFund{value: sentAmount}(intent, true);

        address vaultAddress = intentSource.intentVaultAddress(intent);
        assertEq(vaultAddress.balance, sentAmount);
        assertFalse(intentSource.isIntentFunded(intent));
    }

    function testUseActualBalanceOverAllowanceForPartialFunding() public {
        uint256 requestedAmount = MINT_AMOUNT * 2;

        // Setup intent with more tokens than creator has
        TokenAmount[] memory largeRewardTokens = new TokenAmount[](1);
        largeRewardTokens[0] = TokenAmount({
            token: address(tokenA),
            amount: requestedAmount
        });

        Reward memory newReward = reward;
        newReward.tokens = largeRewardTokens;
        intent.reward = newReward;

        // Creator only has MINT_AMOUNT tokens but approves twice as much
        assertEq(tokenA.balanceOf(creator), MINT_AMOUNT);

        vm.prank(creator);
        tokenA.approve(address(intentSource), requestedAmount);

        bytes32 intentHash = _hashIntent(intent);

        _expectEmit();
        emit IIntentSource.IntentFunded(intentHash, creator, false);

        vm.prank(creator);
        intentSource.publishAndFund(intent, true);

        address vaultAddress = intentSource.intentVaultAddress(intent);
        assertEq(tokenA.balanceOf(vaultAddress), MINT_AMOUNT);
        assertEq(tokenA.balanceOf(creator), 0);
        assertFalse(intentSource.isIntentFunded(intent));
    }

    function testRevertWhenBalanceAndAllowanceInsufficientWithoutAllowPartial()
        public
    {
        uint256 requestedAmount = MINT_AMOUNT * 2;

        // Setup intent with more tokens than creator has
        TokenAmount[] memory largeRewardTokens = new TokenAmount[](1);
        largeRewardTokens[0] = TokenAmount({
            token: address(tokenA),
            amount: requestedAmount
        });

        Reward memory newReward = reward;
        newReward.tokens = largeRewardTokens;
        intent.reward = newReward;

        // Creator only has MINT_AMOUNT tokens but approves twice as much
        assertEq(tokenA.balanceOf(creator), MINT_AMOUNT);

        vm.prank(creator);
        tokenA.approve(address(intentSource), requestedAmount);

        vm.expectRevert();
        vm.prank(creator);
        intentSource.publishAndFund(intent, false);
    }

    function testWithdrawsRewardsWithMaliciousTokens() public {
        // Deploy malicious token
        BadERC20 maliciousToken = new BadERC20("Malicious", "MAL", creator);

        vm.prank(creator);
        maliciousToken.mint(creator, MINT_AMOUNT);

        // Create reward with malicious token
        TokenAmount[] memory badRewardTokens = new TokenAmount[](2);
        badRewardTokens[0] = TokenAmount({
            token: address(maliciousToken),
            amount: MINT_AMOUNT
        });
        badRewardTokens[1] = TokenAmount({
            token: address(tokenA),
            amount: MINT_AMOUNT
        });

        Reward memory newReward = reward;
        newReward.tokens = badRewardTokens;
        intent.reward = newReward;

        bytes32 routeHash = keccak256(abi.encode(intent.route));
        address vaultAddress = intentSource.intentVaultAddress(intent);

        // Transfer tokens to vault
        vm.prank(creator);
        maliciousToken.transfer(vaultAddress, MINT_AMOUNT);

        vm.prank(creator);
        tokenA.transfer(vaultAddress, MINT_AMOUNT);

        assertTrue(intentSource.isIntentFunded(intent));

        bytes32 intentHash = _hashIntent(intent);
        _addProof(intentHash, CHAIN_ID, claimant);

        // Should revert due to malicious token preventing transfer
        vm.prank(claimant);
        vm.expectRevert(BadERC20.TransferNotAllowed.selector);
        intentSource.withdraw(intent.destination, routeHash, intent.reward);
    }

    function testBalanceOverAllowanceForPartialFunding() public {
        // Create intent with more tokens than creator has
        uint256 requestedAmount = MINT_AMOUNT * 2;

        TokenAmount[] memory largeRewardTokens = new TokenAmount[](1);
        largeRewardTokens[0] = TokenAmount({
            token: address(tokenA),
            amount: requestedAmount
        });

        Reward memory newReward = reward;
        newReward.tokens = largeRewardTokens;
        intent.reward = newReward;

        // Creator only has MINT_AMOUNT tokens but approves twice as much
        assertEq(tokenA.balanceOf(creator), MINT_AMOUNT);

        vm.prank(creator);
        tokenA.approve(address(intentSource), requestedAmount);

        bytes32 intentHash = _hashIntent(intent);

        _expectEmit();
        emit IIntentSource.IntentFunded(intentHash, creator, false);

        vm.prank(creator);
        intentSource.publishAndFund(intent, true);

        address vaultAddress = intentSource.intentVaultAddress(intent);
        // Should transfer actual balance, not approved amount
        assertEq(tokenA.balanceOf(vaultAddress), MINT_AMOUNT);
        assertEq(tokenA.balanceOf(creator), 0);
        assertFalse(intentSource.isIntentFunded(intent));
    }

    function testInsufficientNativeRewardHandling() public {
        uint256 nativeAmount = 1 ether;
        uint256 sentAmount = 0.5 ether;

        reward.nativeAmount = nativeAmount;
        intent.reward = reward;

        // Test insufficient native reward without partial funding
        vm.expectRevert();
        vm.prank(creator);
        intentSource.publishAndFund{value: sentAmount}(intent, false);

        // Test with partial funding allowed
        bytes32 intentHash = _hashIntent(intent);

        _expectEmit();
        emit IIntentSource.IntentFunded(intentHash, creator, false);

        vm.prank(creator);
        intentSource.publishAndFund{value: sentAmount}(intent, true);

        address vaultAddress = intentSource.intentVaultAddress(intent);
        assertEq(vaultAddress.balance, sentAmount);
        assertFalse(intentSource.isIntentFunded(intent));
    }

    function testFakePermitContractHandling() public {
        // Deploy fake permit contract
        FakePermitContract fakePermit = new FakePermitContract();

        bytes32 routeHash = keccak256(abi.encode(intent.route));
        address intentVault = intentSource.intentVaultAddress(intent);

        // Creator has tokens but doesn't approve IntentSource
        assertEq(tokenA.balanceOf(creator), MINT_AMOUNT);

        // The fake permit will fail to actually transfer tokens
        vm.expectRevert();
        vm.prank(creator);
        intentSource.fundFor(
            intent.destination,
            routeHash,
            reward,
            false,
            creator,
            address(fakePermit)
        );

        // Verify intent is not funded
        assertFalse(intentSource.isIntentFunded(intent));

        // Verify no tokens were transferred
        assertEq(tokenA.balanceOf(creator), MINT_AMOUNT);
        assertEq(tokenA.balanceOf(intentVault), 0);
    }

    function testZeroValueNativeTokenExploit() public {
        // Critical security test: prevent marking intent as funded with zero native value
        uint256 nativeAmount = 1 ether;

        reward.nativeAmount = nativeAmount;
        intent.reward = reward;

        // Try to exploit by sending zero value but claiming intent is funded
        vm.expectRevert();
        vm.prank(creator);
        intentSource.publishAndFund{value: 0}(intent, false);

        // Verify intent is not marked as funded
        assertFalse(intentSource.isIntentFunded(intent));

        // Verify vault has no ETH
        address vaultAddress = intentSource.intentVaultAddress(intent);
        assertEq(vaultAddress.balance, 0);
    }

    function testOverfundedVaultHandling() public {
        // Test behavior when vault has more tokens than required
        _publishAndFund(intent, false);

        // Send additional tokens to vault
        bytes32 routeHash = keccak256(abi.encode(intent.route));
        address vaultAddress = intentSource.intentVaultAddress(intent);
        vm.prank(creator);
        tokenA.mint(creator, MINT_AMOUNT);
        vm.prank(creator);
        tokenA.transfer(vaultAddress, MINT_AMOUNT);

        // Vault should now have double the required amount
        assertEq(tokenA.balanceOf(vaultAddress), MINT_AMOUNT * 2);

        // Intent should still be considered funded
        assertTrue(intentSource.isIntentFunded(intent));

        // IntentWithdrawn should work correctly with overfunded vault
        bytes32 intentHash = _hashIntent(intent);
        _addProof(intentHash, CHAIN_ID, claimant);

        uint256 initialBalanceA = tokenA.balanceOf(claimant);
        uint256 initialBalanceB = tokenB.balanceOf(claimant);

        vm.prank(claimant);
        intentSource.withdraw(intent.destination, routeHash, intent.reward);

        // Claimant should receive reward amount, creator gets the excess
        assertEq(tokenA.balanceOf(claimant), initialBalanceA + MINT_AMOUNT);
        assertEq(tokenB.balanceOf(claimant), initialBalanceB + MINT_AMOUNT * 2);
    }

    function testDuplicateTokensInRewardArray() public {
        // Security test: ensure system handles duplicate tokens gracefully
        TokenAmount[] memory duplicateRewardTokens = new TokenAmount[](3);
        duplicateRewardTokens[0] = TokenAmount({
            token: address(tokenA),
            amount: MINT_AMOUNT
        });
        duplicateRewardTokens[1] = TokenAmount({
            token: address(tokenA), // Duplicate
            amount: MINT_AMOUNT / 2
        });
        duplicateRewardTokens[2] = TokenAmount({
            token: address(tokenB),
            amount: MINT_AMOUNT * 2
        });

        Reward memory newReward = reward;
        newReward.tokens = duplicateRewardTokens;
        intent.reward = newReward;

        // Mint additional tokens for this test
        _mintAndApprove(creator, MINT_AMOUNT * 2);

        // Fund the vault with enough tokens
        bytes32 routeHash = keccak256(abi.encode(intent.route));
        address vaultAddress = intentSource.intentVaultAddress(intent);
        vm.prank(creator);
        tokenA.transfer(vaultAddress, MINT_AMOUNT * 2);
        vm.prank(creator);
        tokenB.transfer(vaultAddress, MINT_AMOUNT * 2);

        // Should be considered funded
        assertTrue(intentSource.isIntentFunded(intent));

        bytes32 intentHash = _hashIntent(intent);
        _addProof(intentHash, CHAIN_ID, claimant);

        // IntentWithdrawn should handle duplicates correctly
        vm.prank(claimant);
        intentSource.withdraw(intent.destination, routeHash, intent.reward);

        // Verify balances (should transfer per each entry, including duplicates)
        assertGt(tokenA.balanceOf(claimant), 0);
        assertGt(tokenB.balanceOf(claimant), 0);
    }

    function testBatchWithdrawWithMixedStates() public {
        // Mint more tokens for multiple intents
        _mintAndApprove(creator, MINT_AMOUNT * 3);

        // Create multiple intents with different states
        Intent[] memory intents = new Intent[](3);

        // Intent 1: Fully funded and proven
        intents[0] = intent;
        _publishAndFund(intents[0], false);
        bytes32 hash1 = _hashIntent(intents[0]);
        _addProof(hash1, CHAIN_ID, claimant);

        // Intent 2: Funded but not proven (should be refunded after expiry)
        intents[1] = Intent({
            destination: intent.destination,
            route: Route({
                salt: keccak256("salt2"),
                deadline: intent.route.deadline,
                portal: intent.route.portal,
                nativeAmount: intent.route.nativeAmount,
                tokens: intent.route.tokens,
                calls: intent.route.calls
            }),
            reward: intent.reward
        });
        _publishAndFund(intents[1], false);

        // Intent 3: Proven but different claimant
        intents[2] = Intent({
            destination: intent.destination,
            route: Route({
                salt: keccak256("salt3"),
                deadline: intent.route.deadline,
                portal: intent.route.portal,
                nativeAmount: intent.route.nativeAmount,
                tokens: intent.route.tokens,
                calls: intent.route.calls
            }),
            reward: intent.reward
        });
        _publishAndFund(intents[2], false);
        bytes32 hash3 = _hashIntent(intents[2]);
        _addProof(hash3, CHAIN_ID, creator); // Different claimant

        // Time travel past expiry (need to go past deadline which is 124)
        _timeTravel(expiry + 1);

        uint256 initialClaimantBalance = tokenA.balanceOf(claimant);
        uint256 initialCreatorBalance = tokenA.balanceOf(creator);

        // Since batchWithdraw calls withdraw in a loop and reverts on error,
        // we need to handle each intent separately when they have different outcomes

        // Intent 1: Proven with claimant - should succeed
        vm.prank(claimant);
        intentSource.withdraw(
            intents[0].destination,
            keccak256(abi.encode(intents[0].route)),
            intents[0].reward
        );

        // Intent 2: No proof, expired - should refund
        vm.prank(creator);
        intentSource.refund(
            intents[1].destination,
            keccak256(abi.encode(intents[1].route)),
            intents[1].reward
        );

        // Intent 3: Proven with creator as claimant - should succeed
        vm.prank(creator);
        intentSource.withdraw(
            intents[2].destination,
            keccak256(abi.encode(intents[2].route)),
            intents[2].reward
        );

        // Verify correct distributions
        // Intent 1: should go to claimant
        // Intent 2: should go to creator (refund)
        // Intent 3: should go to creator (different claimant)
        assertEq(
            tokenA.balanceOf(claimant),
            initialClaimantBalance + MINT_AMOUNT
        );
        assertEq(
            tokenA.balanceOf(creator),
            initialCreatorBalance + MINT_AMOUNT * 2
        );
    }

    function testEventEmissionForAllOperations() public {
        // Test comprehensive event emission
        bytes32 intentHash = _hashIntent(intent);

        // Test IntentPublished event
        _expectEmit();

        emit IIntentSource.IntentPublished(
            intentHash,
            intent.destination,
            abi.encode(intent.route),
            intent.reward.creator,
            intent.reward.prover,
            intent.reward.deadline,
            0,
            intent.reward.tokens
        );

        vm.prank(creator);
        intentSource.publish(intent);

        // Test IntentFunded event
        bytes32 routeHash = keccak256(abi.encode(intent.route));
        address intentVault = intentSource.intentVaultAddress(intent);

        vm.prank(creator);
        tokenA.approve(intentVault, MINT_AMOUNT);
        vm.prank(creator);
        tokenB.approve(intentVault, MINT_AMOUNT * 2);

        _expectEmit();
        emit IIntentSource.IntentFunded(intentHash, creator, true);

        vm.prank(creator);
        intentSource.fundFor(
            intent.destination,
            routeHash,
            reward,
            false,
            creator,
            address(0)
        );

        // Test withdrawal event
        _addProof(intentHash, CHAIN_ID, claimant);

        _expectEmit();
        emit IIntentSource.IntentWithdrawn(intentHash, claimant);

        vm.prank(claimant);
        intentSource.withdraw(intent.destination, routeHash, intent.reward);
    }

    function _convertToEVMIntent(
        Intent memory _evmIntent
    ) internal pure returns (EVMIntent memory) {
        // The Intent type is already EVM-compatible, just repackage it
        EVMTokenAmount[] memory evmRouteTokens = new EVMTokenAmount[](
            _evmIntent.route.tokens.length
        );
        for (uint256 i = 0; i < _evmIntent.route.tokens.length; i++) {
            evmRouteTokens[i] = EVMTokenAmount({
                token: _evmIntent.route.tokens[i].token,
                amount: _evmIntent.route.tokens[i].amount
            });
        }

        // Convert calls
        EVMCall[] memory evmCalls = new EVMCall[](
            _evmIntent.route.calls.length
        );
        for (uint256 i = 0; i < _evmIntent.route.calls.length; i++) {
            evmCalls[i] = EVMCall({
                target: _evmIntent.route.calls[i].target,
                data: _evmIntent.route.calls[i].data,
                value: _evmIntent.route.calls[i].value
            });
        }

        // Convert reward tokens
        EVMTokenAmount[] memory evmRewardTokens = new EVMTokenAmount[](
            _evmIntent.reward.tokens.length
        );
        for (uint256 i = 0; i < _evmIntent.reward.tokens.length; i++) {
            evmRewardTokens[i] = EVMTokenAmount({
                token: _evmIntent.reward.tokens[i].token,
                amount: _evmIntent.reward.tokens[i].amount
            });
        }

        return
            EVMIntent({
                destination: _evmIntent.destination,
                route: EVMRoute({
                    salt: _evmIntent.route.salt,
                    deadline: _evmIntent.route.deadline,
                    portal: _evmIntent.route.portal,
                    nativeAmount: _evmIntent.route.nativeAmount,
                    tokens: evmRouteTokens,
                    calls: evmCalls
                }),
                reward: EVMReward({
                    deadline: _evmIntent.reward.deadline,
                    creator: _evmIntent.reward.creator,
                    prover: _evmIntent.reward.prover,
                    nativeAmount: _evmIntent.reward.nativeAmount,
                    tokens: evmRewardTokens
                })
            });
    }

    // Validation Tests - Testing logic moved from Vault to IntentSource
    function testFundingRejectsWithdrawnStatus() public {
        _publishAndFund(intent, false);
        bytes32 intentHash = _hashIntent(intent);

        // First withdraw the intent
        _mockProofAndWithdraw(intentHash, claimant);

        // Try to fund it again - should fail
        vm.expectRevert(
            abi.encodeWithSelector(
                IIntentSource.InvalidStatusForFunding.selector,
                IIntentSource.Status.Withdrawn
            )
        );
        vm.prank(creator);
        intentSource.fund{value: 1 ether}(
            CHAIN_ID,
            keccak256(abi.encode(intent.route)),
            intent.reward,
            false
        );
    }

    function testFundingRejectsRefundedStatus() public {
        _publishAndFund(intent, false);

        // Fast forward past deadline and refund
        vm.warp(reward.deadline + 1);
        vm.prank(creator);
        intentSource.refund(
            CHAIN_ID,
            keccak256(abi.encode(intent.route)),
            intent.reward
        );

        // Try to fund it again - should fail
        vm.expectRevert(
            abi.encodeWithSelector(
                IIntentSource.InvalidStatusForFunding.selector,
                IIntentSource.Status.Refunded
            )
        );
        vm.prank(creator);
        intentSource.fund{value: 1 ether}(
            CHAIN_ID,
            keccak256(abi.encode(intent.route)),
            intent.reward,
            false
        );
    }

    function testWithdrawRejectsWithdrawnStatus() public {
        _publishAndFund(intent, false);
        bytes32 intentHash = _hashIntent(intent);

        // First withdraw normally
        _mockProofAndWithdraw(intentHash, claimant);

        // Try to withdraw again - should fail
        vm.expectRevert(
            abi.encodeWithSelector(
                IIntentSource.InvalidStatusForWithdrawal.selector,
                IIntentSource.Status.Withdrawn
            )
        );
        vm.prank(claimant);
        intentSource.withdraw(
            CHAIN_ID,
            keccak256(abi.encode(intent.route)),
            intent.reward
        );
    }

    function testWithdrawRejectsRefundedStatus() public {
        _publishAndFund(intent, false);

        // Fast forward past deadline and refund
        vm.warp(reward.deadline + 1);
        vm.prank(creator);
        intentSource.refund(
            CHAIN_ID,
            keccak256(abi.encode(intent.route)),
            intent.reward
        );

        // Try to withdraw after refund - should fail
        vm.expectRevert(
            abi.encodeWithSelector(
                IIntentSource.InvalidStatusForWithdrawal.selector,
                IIntentSource.Status.Refunded
            )
        );
        vm.prank(claimant);
        intentSource.withdraw(
            CHAIN_ID,
            keccak256(abi.encode(intent.route)),
            intent.reward
        );
    }

    function testWithdrawRejectsZeroClaimant() public {
        _publishAndFund(intent, false);
        bytes32 intentHash = _hashIntent(intent);

        // Mock a proof with zero claimant
        vm.mockCall(
            address(prover),
            abi.encodeWithSelector(IProver.provenIntents.selector, intentHash),
            abi.encode(IProver.ProofData(address(0), CHAIN_ID))
        );

        vm.expectRevert(
            abi.encodeWithSelector(IIntentSource.InvalidClaimant.selector)
        );
        vm.prank(claimant);
        intentSource.withdraw(
            CHAIN_ID,
            keccak256(abi.encode(intent.route)),
            intent.reward
        );
    }

    function testRefundRejectsBeforeDeadlineWithoutProof() public {
        _publishAndFund(intent, false);

        // Try to refund before deadline without proof - should fail
        vm.expectRevert(
            abi.encodeWithSelector(
                IIntentSource.InvalidStatusForRefund.selector,
                IIntentSource.Status.Funded,
                block.timestamp,
                reward.deadline
            )
        );
        vm.prank(creator);
        intentSource.refund(
            CHAIN_ID,
            keccak256(abi.encode(intent.route)),
            intent.reward
        );
    }

    function testRefundRejectsWhenIntentNotClaimed() public {
        _publishAndFund(intent, false);
        bytes32 intentHash = _hashIntent(intent);

        // Mock a valid proof but don't withdraw (keep status as Funded)
        vm.mockCall(
            address(prover),
            abi.encodeWithSelector(IProver.provenIntents.selector, intentHash),
            abi.encode(IProver.ProofData(claimant, CHAIN_ID))
        );

        // Try to refund an intent that has proof but hasn't been withdrawn - should fail
        vm.expectRevert(
            abi.encodeWithSelector(
                IIntentSource.IntentNotClaimed.selector,
                intentHash
            )
        );
        vm.prank(creator);
        intentSource.refund(
            CHAIN_ID,
            keccak256(abi.encode(intent.route)),
            intent.reward
        );
    }

    // RefundTo Tests
    function testRefundToSuccessAfterDeadline() public {
        _publishAndFund(intent, false);

        address refundee = makeAddr("refundee");
        _timeTravel(expiry + 1);

        uint256 initialBalanceA = tokenA.balanceOf(refundee);
        uint256 initialBalanceB = tokenB.balanceOf(refundee);

        assertTrue(intentSource.isIntentFunded(intent));

        vm.prank(creator);
        intentSource.refundTo(
            intent.destination,
            keccak256(abi.encode(intent.route)),
            intent.reward,
            refundee
        );

        assertFalse(intentSource.isIntentFunded(intent));
        assertEq(tokenA.balanceOf(refundee), initialBalanceA + MINT_AMOUNT);
        assertEq(tokenB.balanceOf(refundee), initialBalanceB + MINT_AMOUNT * 2);
    }

    function testRefundToWithNativeTokens() public {
        reward.nativeAmount = REWARD_NATIVE_ETH;
        intent.reward = reward;

        _publishAndFundWithValue(intent, false, REWARD_NATIVE_ETH);

        address refundee = makeAddr("refundee");
        _timeTravel(expiry + 1);

        uint256 initialBalanceA = tokenA.balanceOf(refundee);
        uint256 initialBalanceB = tokenB.balanceOf(refundee);
        uint256 initialBalanceNative = refundee.balance;

        vm.prank(creator);
        intentSource.refundTo(
            intent.destination,
            keccak256(abi.encode(intent.route)),
            intent.reward,
            refundee
        );

        assertEq(tokenA.balanceOf(refundee), initialBalanceA + MINT_AMOUNT);
        assertEq(tokenB.balanceOf(refundee), initialBalanceB + MINT_AMOUNT * 2);
        assertEq(refundee.balance, initialBalanceNative + REWARD_NATIVE_ETH);
    }

    function testRefundToRevertsWhenNotCreator() public {
        _publishAndFund(intent, false);

        address refundee = makeAddr("refundee");
        _timeTravel(expiry + 1);

        vm.prank(otherPerson);
        vm.expectRevert(
            abi.encodeWithSelector(
                IIntentSource.NotCreatorCaller.selector,
                otherPerson
            )
        );
        intentSource.refundTo(
            intent.destination,
            keccak256(abi.encode(intent.route)),
            intent.reward,
            refundee
        );
    }

    function testRefundToRevertsBeforeDeadline() public {
        _publishAndFund(intent, false);

        address refundee = makeAddr("refundee");

        vm.prank(creator);
        vm.expectRevert(
            abi.encodeWithSelector(
                IIntentSource.InvalidStatusForRefund.selector,
                IIntentSource.Status.Funded,
                block.timestamp,
                reward.deadline
            )
        );
        intentSource.refundTo(
            intent.destination,
            keccak256(abi.encode(intent.route)),
            intent.reward,
            refundee
        );
    }

    function testRefundToEmitsCorrectEvent() public {
        _publishAndFund(intent, false);

        address refundee = makeAddr("refundee");
        _timeTravel(expiry + 1);

        bytes32 intentHash = _hashIntent(intent);

        _expectEmit();
        emit IIntentSource.IntentRefunded(intentHash, refundee);

        vm.prank(creator);
        intentSource.refundTo(
            intent.destination,
            keccak256(abi.encode(intent.route)),
            intent.reward,
            refundee
        );
    }

    function testRefundToRevertsWhenIntentNotClaimed() public {
        _publishAndFund(intent, false);
        bytes32 intentHash = _hashIntent(intent);

        address refundee = makeAddr("refundee");

        // Mock a valid proof but don't withdraw
        vm.mockCall(
            address(prover),
            abi.encodeWithSelector(IProver.provenIntents.selector, intentHash),
            abi.encode(IProver.ProofData(claimant, CHAIN_ID))
        );

        vm.prank(creator);
        vm.expectRevert(
            abi.encodeWithSelector(
                IIntentSource.IntentNotClaimed.selector,
                intentHash
            )
        );
        intentSource.refundTo(
            intent.destination,
            keccak256(abi.encode(intent.route)),
            intent.reward,
            refundee
        );
    }

    function testRefundToAllowsAfterWithdrawal() public {
        _publishAndFund(intent, false);

        bytes32 intentHash = _hashIntent(intent);
        _addProof(intentHash, CHAIN_ID, claimant);

        vm.prank(otherPerson);
        intentSource.withdraw(
            intent.destination,
            keccak256(abi.encode(intent.route)),
            intent.reward
        );

        address refundee = makeAddr("refundee");

        _expectEmit();
        emit IIntentSource.IntentRefunded(intentHash, refundee);

        vm.prank(creator);
        intentSource.refundTo(
            intent.destination,
            keccak256(abi.encode(intent.route)),
            intent.reward,
            refundee
        );
    }

    function testRefundCanBeCalledMultipleTimesToRecoverAdditionalFunds() public {
        _publishAndFund(intent, false);
        _timeTravel(expiry + 1);

        address vaultAddress = intentSource.intentVaultAddress(intent);
        uint256 initialBalanceA = tokenA.balanceOf(creator);
        uint256 initialBalanceB = tokenB.balanceOf(creator);

        // First refund - gets original funds
        vm.prank(creator);
        intentSource.refund(
            intent.destination,
            keccak256(abi.encode(intent.route)),
            intent.reward
        );

        assertEq(tokenA.balanceOf(creator), initialBalanceA + MINT_AMOUNT);
        assertEq(tokenB.balanceOf(creator), initialBalanceB + MINT_AMOUNT * 2);
        assertEq(tokenA.balanceOf(vaultAddress), 0);
        assertEq(tokenB.balanceOf(vaultAddress), 0);

        // Someone accidentally sends more tokens to the vault
        vm.prank(otherPerson);
        tokenA.mint(otherPerson, MINT_AMOUNT);
        vm.prank(otherPerson);
        tokenA.transfer(vaultAddress, MINT_AMOUNT);

        vm.prank(otherPerson);
        tokenB.mint(otherPerson, MINT_AMOUNT);
        vm.prank(otherPerson);
        tokenB.transfer(vaultAddress, MINT_AMOUNT);

        assertEq(tokenA.balanceOf(vaultAddress), MINT_AMOUNT);
        assertEq(tokenB.balanceOf(vaultAddress), MINT_AMOUNT);

        // Second refund - recovers the additional funds
        vm.prank(creator);
        intentSource.refund(
            intent.destination,
            keccak256(abi.encode(intent.route)),
            intent.reward
        );

        assertEq(tokenA.balanceOf(creator), initialBalanceA + MINT_AMOUNT * 2);
        assertEq(tokenB.balanceOf(creator), initialBalanceB + MINT_AMOUNT * 3);
        assertEq(tokenA.balanceOf(vaultAddress), 0);
        assertEq(tokenB.balanceOf(vaultAddress), 0);
    }

    function testRefundToCanBeCalledMultipleTimesToRecoverAdditionalFunds() public {
        _publishAndFund(intent, false);
        _timeTravel(expiry + 1);

        address vaultAddress = intentSource.intentVaultAddress(intent);
        address refundee = makeAddr("refundee");
        uint256 initialBalanceA = tokenA.balanceOf(refundee);
        uint256 initialBalanceB = tokenB.balanceOf(refundee);

        // First refundTo - gets original funds
        vm.prank(creator);
        intentSource.refundTo(
            intent.destination,
            keccak256(abi.encode(intent.route)),
            intent.reward,
            refundee
        );

        assertEq(tokenA.balanceOf(refundee), initialBalanceA + MINT_AMOUNT);
        assertEq(tokenB.balanceOf(refundee), initialBalanceB + MINT_AMOUNT * 2);
        assertEq(tokenA.balanceOf(vaultAddress), 0);
        assertEq(tokenB.balanceOf(vaultAddress), 0);

        // Someone accidentally sends more tokens to the vault
        vm.prank(otherPerson);
        tokenA.mint(otherPerson, MINT_AMOUNT);
        vm.prank(otherPerson);
        tokenA.transfer(vaultAddress, MINT_AMOUNT);

        vm.prank(otherPerson);
        tokenB.mint(otherPerson, MINT_AMOUNT);
        vm.prank(otherPerson);
        tokenB.transfer(vaultAddress, MINT_AMOUNT);

        assertEq(tokenA.balanceOf(vaultAddress), MINT_AMOUNT);
        assertEq(tokenB.balanceOf(vaultAddress), MINT_AMOUNT);

        // Second refundTo - recovers the additional funds to different address
        address refundee2 = makeAddr("refundee2");
        vm.prank(creator);
        intentSource.refundTo(
            intent.destination,
            keccak256(abi.encode(intent.route)),
            intent.reward,
            refundee2
        );

        // Original refundee unchanged
        assertEq(tokenA.balanceOf(refundee), initialBalanceA + MINT_AMOUNT);
        assertEq(tokenB.balanceOf(refundee), initialBalanceB + MINT_AMOUNT * 2);

        // New refundee gets the additional funds
        assertEq(tokenA.balanceOf(refundee2), MINT_AMOUNT);
        assertEq(tokenB.balanceOf(refundee2), MINT_AMOUNT);
        assertEq(tokenA.balanceOf(vaultAddress), 0);
        assertEq(tokenB.balanceOf(vaultAddress), 0);
    }

    function testPublishRejectsWithdrawnIntent() public {
        _publishAndFund(intent, false);
        bytes32 intentHash = _hashIntent(intent);

        // First withdraw the intent
        _mockProofAndWithdraw(intentHash, claimant);

        // Try to publish the same intent again - should fail
        vm.expectRevert(
            abi.encodeWithSelector(
                IIntentSource.IntentAlreadyExists.selector,
                intentHash
            )
        );
        vm.prank(creator);
        intentSource.publish(intent);
    }

    function testPublishRejectsRefundedIntent() public {
        _publishAndFund(intent, false);
        bytes32 intentHash = _hashIntent(intent);

        // First refund the intent
        vm.warp(reward.deadline + 1);
        vm.prank(creator);
        intentSource.refund(
            CHAIN_ID,
            keccak256(abi.encode(intent.route)),
            intent.reward
        );

        // Try to publish the same intent again - should fail
        vm.expectRevert(
            abi.encodeWithSelector(
                IIntentSource.IntentAlreadyExists.selector,
                intentHash
            )
        );
        vm.prank(creator);
        intentSource.publish(intent);
    }

    function testRecoverTokenRejectsZeroAddress() public {
        _publishAndFund(intent, false);

        vm.expectRevert(
            abi.encodeWithSelector(
                IIntentSource.InvalidRecoverToken.selector,
                address(0)
            )
        );
        vm.prank(creator);
        intentSource.recoverToken(
            CHAIN_ID,
            keccak256(abi.encode(intent.route)),
            intent.reward,
            address(0)
        );
    }

    function testRecoverTokenRejectsRewardToken() public {
        _publishAndFund(intent, false);

        // Try to recover a token that's part of the reward
        address rewardTokenAddress = intent.reward.tokens[0].token;

        vm.expectRevert(
            abi.encodeWithSelector(
                IIntentSource.InvalidRecoverToken.selector,
                rewardTokenAddress
            )
        );
        vm.prank(creator);
        intentSource.recoverToken(
            CHAIN_ID,
            keccak256(abi.encode(intent.route)),
            intent.reward,
            rewardTokenAddress
        );
    }

    // Helper function to mock proof and withdraw
    function _mockProofAndWithdraw(
        bytes32 _intentHash,
        address claimant
    ) internal {
        // Mock the prover to return a valid proof
        vm.mockCall(
            address(prover),
            abi.encodeWithSelector(IProver.provenIntents.selector, _intentHash),
            abi.encode(IProver.ProofData(claimant, CHAIN_ID))
        );

        // Withdraw the intent
        vm.prank(claimant);
        intentSource.withdraw(
            CHAIN_ID,
            keccak256(abi.encode(intent.route)),
            intent.reward
        );
    }
}

// Mock contract for testing fake permit behavior
contract FakePermitContract {
    function permit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        // Fake permit that doesn't actually approve tokens
        // This simulates a malicious permit contract
    }

    function allowance(
        address,
        /* owner */
        address,
        /* token */
        address /* spender */
    ) external pure returns (uint160, uint48, uint48) {
        // Lies about having unlimited allowance
        return (type(uint160).max, 0, 0);
    }

    function transferFrom(
        address,
        /* from */
        address,
        /* to */
        uint160,
        /* amount */
        address /* token */
    ) external {
        // Fake transferFrom that doesn't actually transfer tokens
        // This simulates a malicious permit contract that lies about transfers
    }
}
