// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Test} from "forge-std/Test.sol";
import {LocalProver} from "../../contracts/prover/LocalProver.sol";
import {Portal} from "../../contracts/Portal.sol";
import {TestProver} from "../../contracts/test/TestProver.sol";
import {TestERC20} from "../../contracts/test/TestERC20.sol";
import {IProver} from "../../contracts/interfaces/IProver.sol";
import {ILocalProver} from "../../contracts/interfaces/ILocalProver.sol";
import {IIntentSource} from "../../contracts/interfaces/IIntentSource.sol";
import {Intent, Route, Reward, TokenAmount, Call} from "../../contracts/types/Intent.sol";

contract LocalProverTest is Test {
    LocalProver internal localProver;
    Portal internal portal;
    TestProver internal secondaryProver;
    TestERC20 internal token;

    address internal creator;
    address internal solver;
    address internal user;

    uint64 internal CHAIN_ID;
    uint64 internal constant SECONDARY_CHAIN_ID = 2;
    uint256 internal constant INITIAL_BALANCE = 100 ether;
    uint256 internal constant REWARD_AMOUNT = 10 ether;
    uint256 internal constant TOKEN_AMOUNT = 1000;

    event FlashFulfilled(
        bytes32 indexed intentHash,
        bytes32 indexed claimant,
        uint256 nativeFee
    );

    function setUp() public {
        creator = makeAddr("creator");
        solver = makeAddr("solver");
        user = makeAddr("user");

        // Set CHAIN_ID to current chain
        CHAIN_ID = uint64(block.chainid);

        // Deploy contracts
        portal = new Portal();
        localProver = new LocalProver(address(portal));
        secondaryProver = new TestProver(address(portal));
        token = new TestERC20("Test Token", "TEST");

        // Fund accounts
        vm.deal(creator, INITIAL_BALANCE);
        vm.deal(solver, INITIAL_BALANCE);
        vm.deal(user, INITIAL_BALANCE);

        // Mint tokens
        token.mint(creator, TOKEN_AMOUNT * 10);
        token.mint(solver, TOKEN_AMOUNT * 10);
    }

    function _createIntent(
        address proverAddress,
        uint256 nativeReward,
        uint256 tokenReward
    ) internal view returns (Intent memory) {
        TokenAmount[] memory routeTokens = new TokenAmount[](0);
        Call[] memory calls = new Call[](0);

        Route memory route = Route({
            salt: bytes32(uint256(1)),
            deadline: uint64(block.timestamp + 1000),
            portal: address(portal),
            nativeAmount: 0,
            tokens: routeTokens,
            calls: calls
        });

        TokenAmount[] memory rewardTokens;
        if (tokenReward > 0) {
            rewardTokens = new TokenAmount[](1);
            rewardTokens[0] = TokenAmount({token: address(token), amount: tokenReward});
        } else {
            rewardTokens = new TokenAmount[](0);
        }

        Reward memory reward = Reward({
            deadline: uint64(block.timestamp + 2000),
            creator: creator,
            prover: proverAddress,
            nativeAmount: nativeReward,
            tokens: rewardTokens
        });

        return Intent({destination: CHAIN_ID, route: route, reward: reward});
    }

    function _publishAndFundIntent(
        Intent memory _intent
    ) internal returns (bytes32 intentHash, address vault) {
        vm.startPrank(creator);

        // Approve tokens
        if (_intent.reward.tokens.length > 0) {
            token.approve(address(portal), _intent.reward.tokens[0].amount);
        }

        // Publish and fund
        (intentHash, vault) = portal.publishAndFund{value: _intent.reward.nativeAmount}(
            _intent,
            false
        );

        vm.stopPrank();
    }

    // ============ A. Core IProver Interface Tests ============

    // A1. provenIntents()
    function test_provenIntents_ReturnsClaimantFromPortalForFulfilledIntent() public {
        // Test: Returns claimant from Portal for fulfilled intent
        Intent memory _intent = _createIntent(address(localProver), REWARD_AMOUNT, 0);
        (bytes32 intentHash, ) = _publishAndFundIntent(_intent);

        // Fulfill via Portal directly (normal path)
        vm.startPrank(solver);
        vm.deal(solver, REWARD_AMOUNT);
        portal.fulfill{value: REWARD_AMOUNT}(
            intentHash,
            _intent.route,
            keccak256(abi.encode(_intent.reward)),
            bytes32(uint256(uint160(solver)))
        );
        vm.stopPrank();

        // Should return solver from Portal's claimants
        IProver.ProofData memory proof = localProver.provenIntents(intentHash);
        assertEq(proof.claimant, solver);
        assertEq(proof.destination, CHAIN_ID);
    }

    function test_provenIntents_ReturnsZeroForUnfulfilledIntent() public {
        // Test: Returns zero address for unfulfilled intent
        Intent memory _intent = _createIntent(address(localProver), REWARD_AMOUNT, 0);
        (bytes32 intentHash, ) = _publishAndFundIntent(_intent);

        // Don't fulfill it
        IProver.ProofData memory proof = localProver.provenIntents(intentHash);
        assertEq(proof.claimant, address(0));
        assertEq(proof.destination, 0);
    }

    // A2. prove()
    function test_prove_IsNoOp() public {
        // Test: prove() is a no-op (doesn't revert)
        localProver.prove{value: 0}(
            address(0),
            0,
            "",
            ""
        );
        // Should not revert
    }

    // A3. challengeIntentProof()
    function test_challengeIntentProof_IsNoOp() public {
        // Test: challengeIntentProof() is a no-op (doesn't revert)
        localProver.challengeIntentProof(0, bytes32(0), bytes32(0));
        // Should not revert
    }

    // A4. getProofType()
    function test_getProofType_ReturnsSameChain() public {
        // Test: Returns "Same chain"
        assertEq(localProver.getProofType(), "Same chain");
    }

    // ============ B. flashFulfill() Tests ============

    // B4. Validation - Reverts
    function test_flashFulfill_RevertsIfClaimantIsZero() public {
        // Test: Reverts if claimant is zero
        Intent memory _intent = _createIntent(address(localProver), REWARD_AMOUNT, 0);
        _publishAndFundIntent(_intent);

        vm.prank(solver);
        vm.expectRevert(ILocalProver.InvalidClaimant.selector);
        localProver.flashFulfill(
            _intent.route,
            _intent.reward,
            bytes32(0)
        );
    }

    function test_flashFulfill_RevertsIfIntentAlreadyFulfilled() public {
        // Test: Reverts if intent already fulfilled
        Intent memory _intent = _createIntent(address(localProver), REWARD_AMOUNT, 0);
        (bytes32 intentHash, ) = _publishAndFundIntent(_intent);

        // Fulfill via Portal first
        vm.startPrank(solver);
        vm.deal(solver, REWARD_AMOUNT);
        portal.fulfill{value: REWARD_AMOUNT}(
            intentHash,
            _intent.route,
            keccak256(abi.encode(_intent.reward)),
            bytes32(uint256(uint160(solver)))
        );

        // Try flashFulfill
        vm.expectRevert();
        localProver.flashFulfill(
            _intent.route,
            _intent.reward,
            bytes32(uint256(uint160(solver)))
        );
        vm.stopPrank();
    }

    function test_flashFulfill_RevertsIfIntentExpired() public {
        // Test: Reverts if intent expired
        Intent memory _intent = _createIntent(address(localProver), REWARD_AMOUNT, 0);
        _publishAndFundIntent(_intent);

        // Warp past deadline
        vm.warp(_intent.route.deadline + 1);

        vm.prank(solver);
        vm.expectRevert();
        localProver.flashFulfill(
            _intent.route,
            _intent.reward,
            bytes32(uint256(uint160(solver)))
        );
    }

    function test_flashFulfill_RevertsIfNativeTransferFails() public {
        // Test: Reverts when claimant can't receive native tokens
        // Deploy a contract that rejects ETH transfers
        RejectEth rejecter = new RejectEth();

        Intent memory _intent = _createIntent(address(localProver), REWARD_AMOUNT, 0);
        _publishAndFundIntent(_intent);

        bytes32 rejecterClaimant = bytes32(uint256(uint160(address(rejecter))));

        vm.prank(solver);
        vm.expectRevert(ILocalProver.NativeTransferFailed.selector);
        localProver.flashFulfill(
            _intent.route,
            _intent.reward,
            rejecterClaimant
        );
    }

    // B5. Happy Path with Route Tokens
    function test_flashFulfill_SucceedsWithRouteTokens() public {
        // Test: flashFulfill succeeds with route tokens (stablecoin)
        // Create intent with route tokens that match reward tokens
        TokenAmount[] memory routeTokens = new TokenAmount[](1);
        routeTokens[0] = TokenAmount({
            token: address(token),
            amount: TOKEN_AMOUNT
        });

        TokenAmount[] memory rewardTokens = new TokenAmount[](1);
        rewardTokens[0] = TokenAmount({
            token: address(token),
            amount: TOKEN_AMOUNT
        });

        Call[] memory calls = new Call[](0);

        Route memory route = Route({
            salt: bytes32(uint256(1)),
            deadline: uint64(block.timestamp + 1000),
            portal: address(portal),
            nativeAmount: 0,
            tokens: routeTokens,
            calls: calls
        });

        Reward memory reward = Reward({
            deadline: uint64(block.timestamp + 2000),
            creator: creator,
            prover: address(localProver),
            nativeAmount: 0,
            tokens: rewardTokens
        });

        Intent memory _intent = Intent({
            destination: CHAIN_ID,
            route: route,
            reward: reward
        });

        _publishAndFundIntent(_intent);

        bytes32 claimantBytes = bytes32(uint256(uint160(solver)));

        // FlashFulfill should succeed
        vm.prank(solver);
        localProver.flashFulfill(
            _intent.route,
            _intent.reward,
            claimantBytes
        );

        // Verify tokens transferred to executor
        assertEq(token.balanceOf(address(portal.executor())), TOKEN_AMOUNT);
    }

    function test_flashFulfill_SucceedsWithTokensAndNativeReward() public {
        // Test: flashFulfill correctly transfers both tokens and remaining native to claimant
        // Create intent with route tokens AND reward native amount
        TokenAmount[] memory routeTokens = new TokenAmount[](1);
        routeTokens[0] = TokenAmount({
            token: address(token),
            amount: TOKEN_AMOUNT
        });

        TokenAmount[] memory rewardTokens = new TokenAmount[](1);
        rewardTokens[0] = TokenAmount({
            token: address(token),
            amount: TOKEN_AMOUNT
        });

        Call[] memory calls = new Call[](0);

        Route memory route = Route({
            salt: bytes32(uint256(2)),
            deadline: uint64(block.timestamp + 1000),
            portal: address(portal),
            nativeAmount: 0,
            tokens: routeTokens,
            calls: calls
        });

        Reward memory reward = Reward({
            deadline: uint64(block.timestamp + 2000),
            creator: creator,
            prover: address(localProver),
            nativeAmount: REWARD_AMOUNT,  // Native reward for solver
            tokens: rewardTokens
        });

        Intent memory _intent = Intent({
            destination: CHAIN_ID,
            route: route,
            reward: reward
        });

        (bytes32 intentHash, ) = _publishAndFundIntent(_intent);

        bytes32 claimantBytes = bytes32(uint256(uint160(solver)));

        // Record solver's balance before flashFulfill
        uint256 solverBalanceBefore = solver.balance;

        // FlashFulfill should succeed
        vm.prank(solver);
        localProver.flashFulfill(
            _intent.route,
            _intent.reward,
            claimantBytes
        );

        // Verify tokens transferred to executor
        assertEq(token.balanceOf(address(portal.executor())), TOKEN_AMOUNT);

        // Verify native transferred to solver (claimant)
        assertEq(solver.balance, solverBalanceBefore + REWARD_AMOUNT);
    }

    function test_flashFulfill_TransfersRewardTokensToSolver() public {
        // Test: Solver receives ERC20 reward tokens, not just native
        // Route uses 500 tokens for execution, reward has 1000 tokens
        // Solver should get the 500 token remainder
        uint256 routeTokenAmount = 500;
        uint256 rewardTokenAmount = 1000;

        TokenAmount[] memory routeTokens = new TokenAmount[](1);
        routeTokens[0] = TokenAmount({
            token: address(token),
            amount: routeTokenAmount
        });

        TokenAmount[] memory rewardTokens = new TokenAmount[](1);
        rewardTokens[0] = TokenAmount({
            token: address(token),
            amount: rewardTokenAmount
        });

        Call[] memory calls = new Call[](0);

        Route memory route = Route({
            salt: bytes32(uint256(4)),
            deadline: uint64(block.timestamp + 1000),
            portal: address(portal),
            nativeAmount: 0,
            tokens: routeTokens,
            calls: calls
        });

        Reward memory reward = Reward({
            deadline: uint64(block.timestamp + 2000),
            creator: creator,
            prover: address(localProver),
            nativeAmount: 0,
            tokens: rewardTokens
        });

        Intent memory _intent = Intent({
            destination: CHAIN_ID,
            route: route,
            reward: reward
        });

        _publishAndFundIntent(_intent);

        bytes32 claimantBytes = bytes32(uint256(uint160(solver)));

        // Record solver's token balance before
        uint256 solverTokenBalanceBefore = token.balanceOf(solver);

        // FlashFulfill should succeed
        vm.prank(solver);
        localProver.flashFulfill(
            _intent.route,
            _intent.reward,
            claimantBytes
        );

        // Verify route tokens (500) transferred to executor
        assertEq(token.balanceOf(address(portal.executor())), routeTokenAmount);

        // Verify reward tokens (500 remainder) transferred to solver
        assertEq(
            token.balanceOf(solver),
            solverTokenBalanceBefore + (rewardTokenAmount - routeTokenAmount)
        );
    }

    // ============ C. Griefing Attack Tests ============

    function test_griefing_LocalProverSentinel_AllowsRefundAfterDeadline() public {
        // Test: Attacker calls Portal.fulfill with LocalProver as claimant (Vector 1)
        // Should not permanently brick the intent - refund should work after deadline

        Intent memory _intent = _createIntent(address(localProver), REWARD_AMOUNT, 0);
        (bytes32 intentHash, ) = _publishAndFundIntent(_intent);

        // Attacker fulfills with LocalProver as claimant (griefing)
        address attacker = makeAddr("attacker");
        vm.startPrank(attacker);
        vm.deal(attacker, REWARD_AMOUNT);
        bytes32 localProverAsBytes32 = bytes32(uint256(uint160(address(localProver))));
        portal.fulfill{value: REWARD_AMOUNT}(
            intentHash,
            _intent.route,
            keccak256(abi.encode(_intent.reward)),
            localProverAsBytes32
        );
        vm.stopPrank();

        // provenIntents should return address(0) (not revert)
        IProver.ProofData memory proof = localProver.provenIntents(intentHash);
        assertEq(proof.claimant, address(0));
        assertEq(proof.destination, 0);

        // Honest solver cannot flashFulfill (already fulfilled)
        vm.startPrank(solver);
        vm.expectRevert(); // Portal reverts with IntentAlreadyFulfilled
        localProver.flashFulfill(
            _intent.route,
            _intent.reward,
            bytes32(uint256(uint160(solver)))
        );
        vm.stopPrank();

        // Warp past deadline
        vm.warp(_intent.reward.deadline + 1);

        // Refund should succeed
        uint256 creatorBalanceBefore = creator.balance;
        vm.prank(user);
        portal.refund(
            _intent.destination,
            keccak256(abi.encode(_intent.route)),
            _intent.reward
        );

        // Creator should receive refund
        assertEq(creator.balance, creatorBalanceBefore + REWARD_AMOUNT);
    }

    function test_griefing_NonEVMBytes32_AllowsRefundAfterDeadline() public {
        // Test: Attacker calls Portal.fulfill with non-EVM bytes32 (Vector 2)
        // E.g., a Solana address with non-zero top 12 bytes
        // Should not permanently brick the intent - refund should work after deadline

        Intent memory _intent = _createIntent(address(localProver), REWARD_AMOUNT, 0);
        (bytes32 intentHash, ) = _publishAndFundIntent(_intent);

        // Attacker fulfills with non-EVM bytes32 (griefing)
        // Top 12 bytes are non-zero (invalid EVM address)
        address attacker = makeAddr("attacker");
        vm.startPrank(attacker);
        vm.deal(attacker, REWARD_AMOUNT);
        bytes32 nonEVMBytes32 = bytes32(uint256(type(uint256).max)); // All 1s
        portal.fulfill{value: REWARD_AMOUNT}(
            intentHash,
            _intent.route,
            keccak256(abi.encode(_intent.reward)),
            nonEVMBytes32
        );
        vm.stopPrank();

        // provenIntents should return address(0) (not revert)
        IProver.ProofData memory proof = localProver.provenIntents(intentHash);
        assertEq(proof.claimant, address(0));
        assertEq(proof.destination, 0);

        // Honest solver cannot flashFulfill (already fulfilled)
        vm.startPrank(solver);
        vm.expectRevert(); // Portal reverts with IntentAlreadyFulfilled
        localProver.flashFulfill(
            _intent.route,
            _intent.reward,
            bytes32(uint256(uint160(solver)))
        );
        vm.stopPrank();

        // Warp past deadline
        vm.warp(_intent.reward.deadline + 1);

        // Refund should succeed
        uint256 creatorBalanceBefore = creator.balance;
        vm.prank(user);
        portal.refund(
            _intent.destination,
            keccak256(abi.encode(_intent.route)),
            _intent.reward
        );

        // Creator should receive refund
        assertEq(creator.balance, creatorBalanceBefore + REWARD_AMOUNT);
    }

    function test_griefing_LocalProverSentinel_BlocksRefundBeforeDeadline() public {
        // Test: Even with griefing, refund should not work before deadline

        Intent memory _intent = _createIntent(address(localProver), REWARD_AMOUNT, 0);
        (bytes32 intentHash, ) = _publishAndFundIntent(_intent);

        // Attacker fulfills with LocalProver as claimant (griefing)
        address attacker = makeAddr("attacker");
        vm.startPrank(attacker);
        vm.deal(attacker, REWARD_AMOUNT);
        bytes32 localProverAsBytes32 = bytes32(uint256(uint160(address(localProver))));
        portal.fulfill{value: REWARD_AMOUNT}(
            intentHash,
            _intent.route,
            keccak256(abi.encode(_intent.reward)),
            localProverAsBytes32
        );
        vm.stopPrank();

        // Try to refund before deadline - should fail
        vm.prank(user);
        vm.expectRevert(); // Portal reverts with InvalidStatusForRefund
        portal.refund(
            _intent.destination,
            keccak256(abi.encode(_intent.route)),
            _intent.reward
        );
    }

    function test_griefing_WithTokenReward_AllowsRefundAfterDeadline() public {
        // Test: Griefing with token rewards - refund should recover both native and tokens

        Intent memory _intent = _createIntent(address(localProver), REWARD_AMOUNT, TOKEN_AMOUNT);
        (bytes32 intentHash, ) = _publishAndFundIntent(_intent);

        // Attacker fulfills with LocalProver as claimant (griefing)
        address attacker = makeAddr("attacker");
        vm.startPrank(attacker);
        vm.deal(attacker, REWARD_AMOUNT);
        bytes32 localProverAsBytes32 = bytes32(uint256(uint160(address(localProver))));
        portal.fulfill{value: REWARD_AMOUNT}(
            intentHash,
            _intent.route,
            keccak256(abi.encode(_intent.reward)),
            localProverAsBytes32
        );
        vm.stopPrank();

        // Warp past deadline
        vm.warp(_intent.reward.deadline + 1);

        // Refund should succeed
        uint256 creatorNativeBalanceBefore = creator.balance;
        uint256 creatorTokenBalanceBefore = token.balanceOf(creator);

        vm.prank(user);
        portal.refund(
            _intent.destination,
            keccak256(abi.encode(_intent.route)),
            _intent.reward
        );

        // Creator should receive both native and token refund
        assertEq(creator.balance, creatorNativeBalanceBefore + REWARD_AMOUNT);
        assertEq(token.balanceOf(creator), creatorTokenBalanceBefore + TOKEN_AMOUNT);
    }

    function test_flashFulfill_RevertsWithLocalProverAsClaimant() public {
        // Test that flashFulfill reverts when claimant is set to LocalProver address
        // This prevents fund stranding attacks where funds would be stuck in LocalProver

        Intent memory intent = _createIntent(address(localProver), REWARD_AMOUNT, 0);
        _publishAndFundIntent(intent);

        address attacker = makeAddr("attacker");
        bytes32 localProverAsClaimant = bytes32(uint256(uint160(address(localProver))));

        vm.startPrank(attacker);
        vm.expectRevert(ILocalProver.InvalidClaimant.selector);
        localProver.flashFulfill(
            intent.route,
            intent.reward,
            localProverAsClaimant  // Should revert - LocalProver cannot be claimant
        );
        vm.stopPrank();
    }

    // ============ Helper Functions ============

    function _encodeProofs(
        bytes32[] memory intentHashes,
        bytes32[] memory claimants
    ) internal view returns (bytes memory) {
        require(intentHashes.length == claimants.length, "Length mismatch");

        bytes memory encodedProofs = new bytes(8 + intentHashes.length * 64);
        uint64 chainId = uint64(block.chainid);

        assembly {
            mstore(add(encodedProofs, 0x20), shl(192, chainId))
        }

        for (uint256 i = 0; i < intentHashes.length; i++) {
            assembly {
                let offset := add(8, mul(i, 64))
                mstore(
                    add(add(encodedProofs, 0x20), offset),
                    mload(add(intentHashes, add(0x20, mul(i, 32))))
                )
                mstore(
                    add(add(encodedProofs, 0x20), add(offset, 32)),
                    mload(add(claimants, add(0x20, mul(i, 32))))
                )
            }
        }

        return encodedProofs;
    }

    // Allow test contract to receive ETH
    receive() external payable {}
}

/**
 * @notice Helper contract that rejects ETH transfers
 * @dev Used to test native transfer failure scenarios
 */
contract RejectEth {
    // No receive() or fallback() - will reject all ETH transfers
}
