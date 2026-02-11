// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {BaseTest} from "../BaseTest.sol";
import {IInbox} from "../../contracts/interfaces/IInbox.sol";
import {Intent, Route, Reward, TokenAmount, Call} from "../../contracts/types/Intent.sol";
import {TypeCasts} from "@hyperlane-xyz/core/contracts/libs/TypeCasts.sol";
import {BadERC20} from "../../contracts/test/BadERC20.sol";
import {TestUSDT} from "../../contracts/test/TestUSDT.sol";

/**
 * @title Advanced Inbox Tests
 * @notice Tests for advanced inbox functionality including complex message routing,
 * multi-token handling, and edge cases for system reliability
 */
contract InboxAdvancedTest is BaseTest {
    address internal solver;
    address internal recipient;
    address internal recipient2;
    BadERC20 internal badToken;
    TestUSDT internal usdtToken;

    function setUp() public override {
        super.setUp();
        solver = makeAddr("solver");
        recipient = makeAddr("recipient");
        recipient2 = makeAddr("recipient2");

        // Deploy bad token for testing edge cases
        vm.prank(deployer);
        badToken = new BadERC20("BadToken", "BAD", deployer);

        // Deploy USDT-like token for testing
        vm.prank(deployer);
        usdtToken = new TestUSDT("USDT", "USDT");

        _mintAndApprove(creator, MINT_AMOUNT);
        _mintAndApprove(solver, MINT_AMOUNT);
        _fundUserNative(creator, 10 ether);
        _fundUserNative(solver, 10 ether);

        // Mint and approve bad tokens (use deployer as god for BadERC20)
        vm.startPrank(deployer);
        badToken.mint(deployer, MINT_AMOUNT * 10);
        badToken.approve(address(portal), MINT_AMOUNT * 10);
        // Allow portal to spend badToken on behalf of deployer
        vm.stopPrank();

        vm.startPrank(solver);
        usdtToken.mint(solver, MINT_AMOUNT * 10);
        usdtToken.approve(address(portal), MINT_AMOUNT * 10);
        vm.stopPrank();
    }

    // ===== MESSAGE ROUTING TESTS =====

    function testMessageRoutingWithMultipleRecipients() public {
        // Create intent with multiple recipients
        TokenAmount[] memory tokens = new TokenAmount[](2);
        tokens[0] = TokenAmount({
            token: address(tokenA),
            amount: MINT_AMOUNT / 2
        });
        tokens[1] = TokenAmount({token: address(tokenB), amount: MINT_AMOUNT});

        Call[] memory calls = new Call[](2);
        calls[0] = Call({
            target: address(tokenA),
            data: abi.encodeWithSignature(
                "transfer(address,uint256)",
                recipient,
                MINT_AMOUNT / 2
            ),
            value: 0
        });
        calls[1] = Call({
            target: address(tokenB),
            data: abi.encodeWithSignature(
                "transfer(address,uint256)",
                recipient2,
                MINT_AMOUNT
            ),
            value: 0
        });

        Intent memory intent = Intent({
            destination: uint64(block.chainid),
            route: Route({
                salt: salt,
                deadline: uint64(expiry),
                portal: address(portal),
                nativeAmount: 0,
                tokens: tokens,
                calls: calls
            }),
            reward: Reward({
                deadline: uint64(expiry),
                creator: creator,
                prover: address(prover),
                nativeAmount: 0,
                tokens: new TokenAmount[](0)
            })
        });

        bytes32 routeHash = keccak256(abi.encode(intent.route));
        bytes32 rewardHash = keccak256(abi.encode(intent.reward));
        bytes32 intentHash = keccak256(
            abi.encodePacked(intent.destination, routeHash, rewardHash)
        );

        vm.prank(solver);
        portal.fulfill(
            intentHash,
            intent.route,
            rewardHash,
            bytes32(uint256(uint160(recipient)))
        );

        // Verify tokens were transferred to correct recipients
        assertEq(tokenA.balanceOf(recipient), MINT_AMOUNT / 2);
        assertEq(tokenB.balanceOf(recipient2), MINT_AMOUNT);
    }

    function testMessageRoutingWithComplexCallData() public {
        // Create intent with complex call data
        bytes memory complexData = abi.encodeWithSignature(
            "transfer(address,uint256)",
            recipient,
            MINT_AMOUNT
        );

        TokenAmount[] memory tokens = new TokenAmount[](1);
        tokens[0] = TokenAmount({token: address(tokenA), amount: MINT_AMOUNT});

        Call[] memory calls = new Call[](1);
        calls[0] = Call({target: address(tokenA), data: complexData, value: 0});

        Intent memory intent = Intent({
            destination: uint64(block.chainid),
            route: Route({
                salt: salt,
                deadline: uint64(expiry),
                portal: address(portal),
                nativeAmount: 0,
                tokens: tokens,
                calls: calls
            }),
            reward: Reward({
                deadline: uint64(expiry),
                creator: creator,
                prover: address(prover),
                nativeAmount: 0,
                tokens: new TokenAmount[](0)
            })
        });

        bytes32 routeHash = keccak256(abi.encode(intent.route));
        bytes32 rewardHash = keccak256(abi.encode(intent.reward));
        bytes32 intentHash = keccak256(
            abi.encodePacked(intent.destination, routeHash, rewardHash)
        );

        vm.prank(solver);
        portal.fulfill(
            intentHash,
            intent.route,
            rewardHash,
            bytes32(uint256(uint160(recipient)))
        );

        // Verify complex call was executed
        assertEq(tokenA.balanceOf(recipient), MINT_AMOUNT);
    }

    function testMessageRoutingWithNativeETHAndTokens() public {
        uint256 ethAmount = 1 ether;

        TokenAmount[] memory tokens = new TokenAmount[](1);
        tokens[0] = TokenAmount({token: address(tokenA), amount: MINT_AMOUNT});

        Call[] memory calls = new Call[](2);
        calls[0] = Call({
            target: address(tokenA),
            data: abi.encodeWithSignature(
                "transfer(address,uint256)",
                recipient,
                MINT_AMOUNT
            ),
            value: 0
        });
        calls[1] = Call({target: recipient2, data: "", value: ethAmount});

        Intent memory intent = Intent({
            destination: uint64(block.chainid),
            route: Route({
                salt: salt,
                deadline: uint64(expiry),
                portal: address(portal),
                nativeAmount: ethAmount,
                tokens: tokens,
                calls: calls
            }),
            reward: Reward({
                deadline: uint64(expiry),
                creator: creator,
                prover: address(prover),
                nativeAmount: 0,
                tokens: new TokenAmount[](0)
            })
        });

        // Fund portal with ETH
        vm.deal(address(portal), ethAmount);

        bytes32 routeHash = keccak256(abi.encode(intent.route));
        bytes32 rewardHash = keccak256(abi.encode(intent.reward));
        bytes32 intentHash = keccak256(
            abi.encodePacked(intent.destination, routeHash, rewardHash)
        );

        uint256 initialBalance = recipient2.balance;

        vm.prank(solver);
        vm.deal(solver, ethAmount);
        portal.fulfill{value: ethAmount}(
            intentHash,
            intent.route,
            rewardHash,
            bytes32(uint256(uint160(recipient)))
        );

        // Verify both token and ETH transfers
        assertEq(tokenA.balanceOf(recipient), MINT_AMOUNT);
        assertEq(recipient2.balance, initialBalance + ethAmount);
    }

    // ===== VALIDATION TESTS =====

    function testValidationWithMalformedIntentHash() public {
        Intent memory intent = _createBasicIntent();
        // bytes32 routeHash = keccak256(abi.encode(intent.route)); // unused
        bytes32 rewardHash = keccak256(abi.encode(intent.reward));

        // Create malformed intent hash
        bytes32 malformedHash = keccak256(abi.encodePacked("malformed"));

        vm.expectRevert();
        vm.prank(solver);
        portal.fulfill(
            malformedHash,
            intent.route,
            rewardHash,
            bytes32(uint256(uint160(recipient)))
        );
    }

    function testValidationWithMismatchedRouteData() public {
        Intent memory intent = _createBasicIntent();
        bytes32 rewardHash = keccak256(abi.encode(intent.reward));
        bytes32 intentHash = keccak256(
            abi.encodePacked(
                intent.destination,
                keccak256(abi.encode(intent.route)),
                rewardHash
            )
        );

        // Create mismatched route
        Route memory mismatchedRoute = intent.route;
        mismatchedRoute.salt = keccak256("different");

        vm.expectRevert();
        vm.prank(solver);
        portal.fulfill(
            intentHash,
            mismatchedRoute,
            rewardHash,
            bytes32(uint256(uint160(recipient)))
        );
    }

    function testValidationWithExpiredDeadline() public {
        Intent memory intent = _createBasicIntent();
        intent.route.deadline = uint64(block.timestamp - 1); // Expired

        bytes32 routeHash = keccak256(abi.encode(intent.route));
        bytes32 rewardHash = keccak256(abi.encode(intent.reward));
        bytes32 intentHash = keccak256(
            abi.encodePacked(intent.destination, routeHash, rewardHash)
        );

        vm.expectRevert();
        vm.prank(solver);
        portal.fulfill(
            intentHash,
            intent.route,
            rewardHash,
            bytes32(uint256(uint160(recipient)))
        );
    }

    function testValidationWithZeroAddress() public {
        Intent memory intent = _createBasicIntent();
        bytes32 routeHash = keccak256(abi.encode(intent.route));
        bytes32 rewardHash = keccak256(abi.encode(intent.reward));
        bytes32 intentHash = keccak256(
            abi.encodePacked(intent.destination, routeHash, rewardHash)
        );

        vm.expectRevert();
        vm.prank(solver);
        portal.fulfill(
            intentHash,
            intent.route,
            rewardHash,
            bytes32(0) // Zero claimant
        );
    }

    function testValidationWithInvalidPortalAddress() public {
        Intent memory intent = _createBasicIntent();
        intent.route.portal = address(0x999); // Invalid portal

        bytes32 routeHash = keccak256(abi.encode(intent.route));
        bytes32 rewardHash = keccak256(abi.encode(intent.reward));
        bytes32 intentHash = keccak256(
            abi.encodePacked(intent.destination, routeHash, rewardHash)
        );

        vm.expectRevert();
        vm.prank(solver);
        portal.fulfill(
            intentHash,
            intent.route,
            rewardHash,
            bytes32(uint256(uint160(recipient)))
        );
    }

    // ===== COMPLEX SCENARIOS =====

    function testComplexScenarioWithMultipleTokenTypes() public {
        // Test with ERC20, bad token, and USDT-like token
        TokenAmount[] memory tokens = new TokenAmount[](3);
        tokens[0] = TokenAmount({
            token: address(tokenA),
            amount: MINT_AMOUNT / 3
        });
        tokens[1] = TokenAmount({
            token: address(tokenB),
            amount: MINT_AMOUNT / 3
        });
        tokens[2] = TokenAmount({
            token: address(usdtToken),
            amount: MINT_AMOUNT / 3
        });

        Call[] memory calls = new Call[](3);
        calls[0] = Call({
            target: address(tokenA),
            data: abi.encodeWithSignature(
                "transfer(address,uint256)",
                recipient,
                MINT_AMOUNT / 3
            ),
            value: 0
        });
        calls[1] = Call({
            target: address(tokenB),
            data: abi.encodeWithSignature(
                "transfer(address,uint256)",
                recipient,
                MINT_AMOUNT / 3
            ),
            value: 0
        });
        calls[2] = Call({
            target: address(usdtToken),
            data: abi.encodeWithSignature(
                "transfer(address,uint256)",
                recipient,
                MINT_AMOUNT / 3
            ),
            value: 0
        });

        Intent memory intent = Intent({
            destination: uint64(block.chainid),
            route: Route({
                salt: salt,
                deadline: uint64(expiry),
                portal: address(portal),
                nativeAmount: 0,
                tokens: tokens,
                calls: calls
            }),
            reward: Reward({
                deadline: uint64(expiry),
                creator: creator,
                prover: address(prover),
                nativeAmount: 0,
                tokens: new TokenAmount[](0)
            })
        });

        bytes32 routeHash = keccak256(abi.encode(intent.route));
        bytes32 rewardHash = keccak256(abi.encode(intent.reward));
        bytes32 intentHash = keccak256(
            abi.encodePacked(intent.destination, routeHash, rewardHash)
        );

        vm.prank(solver);
        portal.fulfill(
            intentHash,
            intent.route,
            rewardHash,
            bytes32(uint256(uint160(recipient)))
        );

        // Verify all tokens were transferred
        assertEq(tokenA.balanceOf(recipient), MINT_AMOUNT / 3);
        assertEq(tokenB.balanceOf(recipient), MINT_AMOUNT / 3);
        assertEq(usdtToken.balanceOf(recipient), MINT_AMOUNT / 3);
    }

    function testComplexScenarioWithBatchOperations() public {
        // Mint extra tokens for multiple intents
        vm.startPrank(solver);
        tokenA.mint(solver, MINT_AMOUNT * 3);
        tokenA.approve(address(portal), MINT_AMOUNT * 4);
        vm.stopPrank();

        // Create multiple intents and process them
        bytes32[] memory intentHashes = new bytes32[](3);

        for (uint256 i = 0; i < 3; i++) {
            Intent memory intent = _createBasicIntent();
            intent.route.salt = keccak256(abi.encodePacked(salt, i));

            bytes32 routeHash = keccak256(abi.encode(intent.route));
            bytes32 rewardHash = keccak256(abi.encode(intent.reward));
            bytes32 intentHash = keccak256(
                abi.encodePacked(intent.destination, routeHash, rewardHash)
            );
            intentHashes[i] = intentHash;

            // Fulfill each intent
            vm.prank(solver);
            portal.fulfill(
                intentHash,
                intent.route,
                rewardHash,
                bytes32(uint256(uint160(recipient)))
            );
        }

        // Verify all intents were fulfilled
        for (uint256 i = 0; i < 3; i++) {
            assertEq(
                portal.claimants(intentHashes[i]),
                bytes32(uint256(uint160(recipient)))
            );
        }
    }

    // ===== HELPER FUNCTIONS =====

    function _createBasicIntent() internal view returns (Intent memory) {
        TokenAmount[] memory tokens = new TokenAmount[](1);
        tokens[0] = TokenAmount({token: address(tokenA), amount: MINT_AMOUNT});

        Call[] memory calls = new Call[](1);
        calls[0] = Call({
            target: address(tokenA),
            data: abi.encodeWithSignature(
                "transfer(address,uint256)",
                recipient,
                MINT_AMOUNT
            ),
            value: 0
        });

        return
            Intent({
                destination: uint64(block.chainid),
                route: Route({
                    salt: salt,
                    deadline: uint64(expiry),
                    portal: address(portal),
                    nativeAmount: 0,
                    tokens: tokens,
                    calls: calls
                }),
                reward: Reward({
                    deadline: uint64(expiry),
                    creator: creator,
                    prover: address(prover),
                    nativeAmount: 0,
                    tokens: new TokenAmount[](0)
                })
            });
    }
}
