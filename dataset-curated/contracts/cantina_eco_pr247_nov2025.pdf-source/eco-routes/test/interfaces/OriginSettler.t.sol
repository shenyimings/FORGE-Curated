// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "../BaseTest.sol";
import {IOriginSettler} from "../../contracts/interfaces/ERC7683/IOriginSettler.sol";
import {OnchainCrossChainOrder, GaslessCrossChainOrder, ResolvedCrossChainOrder, Output, FillInstruction} from "../../contracts/types/ERC7683.sol";
import {Portal} from "../../contracts/Portal.sol";
import {OriginSettler} from "../../contracts/ERC7683/OriginSettler.sol";

// Simple concrete implementation for testing
contract TestOriginSettler is IOriginSettler {
    mapping(bytes32 => bool) public opened;

    function open(OnchainCrossChainOrder calldata order) external payable {
        bytes32 orderId = keccak256(abi.encode(order));
        opened[orderId] = true;
        ResolvedCrossChainOrder memory resolved;
        emit Open(orderId, resolved);
    }

    function openFor(
        GaslessCrossChainOrder calldata order,
        bytes calldata /* signature */,
        bytes calldata /* originFillerData */
    ) external payable {
        bytes32 orderId = keccak256(abi.encode(order));
        opened[orderId] = true;
        ResolvedCrossChainOrder memory resolved;
        emit Open(orderId, resolved);
    }

    function resolveFor(
        GaslessCrossChainOrder calldata order,
        bytes calldata /* originFillerData */
    ) external pure returns (ResolvedCrossChainOrder memory) {
        return
            ResolvedCrossChainOrder({
                user: order.user,
                originChainId: order.originChainId,
                openDeadline: order.openDeadline,
                fillDeadline: order.fillDeadline,
                orderId: keccak256(abi.encode(order)),
                maxSpent: new Output[](0),
                minReceived: new Output[](0),
                fillInstructions: new FillInstruction[](0)
            });
    }

    function resolve(
        OnchainCrossChainOrder calldata order
    ) external view returns (ResolvedCrossChainOrder memory) {
        return
            ResolvedCrossChainOrder({
                user: msg.sender,
                originChainId: block.chainid,
                openDeadline: 0,
                fillDeadline: order.fillDeadline,
                orderId: keccak256(abi.encode(order)),
                maxSpent: new Output[](0),
                minReceived: new Output[](0),
                fillInstructions: new FillInstruction[](0)
            });
    }
}

contract OriginSettlerTest is BaseTest {
    TestOriginSettler internal originSettler;

    address internal user;

    function setUp() public override {
        super.setUp();

        user = makeAddr("user");

        vm.prank(deployer);
        originSettler = new TestOriginSettler();

        _mintAndApprove(creator, MINT_AMOUNT);
        _mintAndApprove(user, MINT_AMOUNT);
        _fundUserNative(creator, 10 ether);
        _fundUserNative(user, 10 ether);
    }

    function testOpenOrder() public {
        OnchainCrossChainOrder memory order = OnchainCrossChainOrder({
            fillDeadline: uint32(block.timestamp + 3600),
            orderDataType: keccak256("test"),
            orderData: abi.encode(intent)
        });

        vm.prank(user);
        originSettler.open(order);

        bytes32 orderId = keccak256(abi.encode(order));
        assertTrue(originSettler.opened(orderId));
    }

    function testOpenOrderEmitsEvent() public {
        OnchainCrossChainOrder memory order = OnchainCrossChainOrder({
            fillDeadline: uint32(block.timestamp + 3600),
            orderDataType: keccak256("test"),
            orderData: abi.encode(intent)
        });

        bytes32 orderId = keccak256(abi.encode(order));

        _expectEmit();
        emit IOriginSettler.Open(
            orderId,
            ResolvedCrossChainOrder({
                user: address(0),
                originChainId: 0,
                openDeadline: 0,
                fillDeadline: 0,
                orderId: bytes32(0),
                maxSpent: new Output[](0),
                minReceived: new Output[](0),
                fillInstructions: new FillInstruction[](0)
            })
        );

        vm.prank(user);
        originSettler.open(order);
    }

    function testOpenOrderWithValue() public {
        OnchainCrossChainOrder memory order = OnchainCrossChainOrder({
            fillDeadline: uint32(block.timestamp + 3600),
            orderDataType: keccak256("test"),
            orderData: abi.encode(intent)
        });

        vm.prank(user);
        originSettler.open{value: 1 ether}(order);

        bytes32 orderId = keccak256(abi.encode(order));
        assertTrue(originSettler.opened(orderId));
    }

    function testOpenForGaslessOrder() public {
        GaslessCrossChainOrder memory order = GaslessCrossChainOrder({
            originSettler: address(originSettler),
            user: user,
            nonce: 1,
            originChainId: block.chainid,
            openDeadline: uint32(block.timestamp + 3600),
            fillDeadline: uint32(block.timestamp + 7200),
            orderDataType: keccak256("test"),
            orderData: abi.encode(intent)
        });

        vm.prank(user);
        originSettler.openFor(order, "", "");

        bytes32 orderId = keccak256(abi.encode(order));
        assertTrue(originSettler.opened(orderId));
    }

    function testResolveOrder() public view {
        OnchainCrossChainOrder memory order = OnchainCrossChainOrder({
            fillDeadline: uint32(block.timestamp + 3600),
            orderDataType: keccak256("test"),
            orderData: abi.encode(intent)
        });

        ResolvedCrossChainOrder memory resolved = originSettler.resolve(order);

        assertEq(resolved.user, address(this));
        assertEq(resolved.originChainId, block.chainid);
        assertEq(resolved.fillDeadline, order.fillDeadline);
    }

    function testResolveForGaslessOrder() public view {
        GaslessCrossChainOrder memory order = GaslessCrossChainOrder({
            originSettler: address(originSettler),
            user: user,
            nonce: 1,
            originChainId: block.chainid,
            openDeadline: uint32(block.timestamp + 3600),
            fillDeadline: uint32(block.timestamp + 7200),
            orderDataType: keccak256("test"),
            orderData: abi.encode(intent)
        });

        ResolvedCrossChainOrder memory resolved = originSettler.resolveFor(
            order,
            ""
        );

        assertEq(resolved.user, order.user);
        assertEq(resolved.originChainId, order.originChainId);
        assertEq(resolved.fillDeadline, order.fillDeadline);
    }

    function testDomainSeparatorV4() public {
        // Test that the Portal's domainSeparatorV4 returns the correct EIP-712 domain separator
        bytes32 domainSeparator = portal.domainSeparatorV4();

        // Verify domain separator is not zero (basic sanity check)
        assertNotEq(domainSeparator, bytes32(0));

        // The domain separator should be deterministic for the same contract
        // Call it again to ensure consistency
        bytes32 domainSeparator2 = portal.domainSeparatorV4();
        assertEq(domainSeparator, domainSeparator2);

        // The domain separator should be unique to this contract instance
        // Deploy another Portal and verify they have different domain separators
        Portal portal2 = new Portal();
        bytes32 domainSeparator3 = portal2.domainSeparatorV4();

        // Domain separators should be different due to different contract addresses
        assertNotEq(domainSeparator, domainSeparator3);
    }

    function testDomainSeparatorV4Structure() public view {
        // Test that the domain separator follows EIP-712 structure
        bytes32 domainSeparator = portal.domainSeparatorV4();

        // Calculate expected domain separator manually
        bytes32 typeHash = keccak256(
            "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
        );
        bytes32 nameHash = keccak256(bytes("EcoPortal"));
        bytes32 versionHash = keccak256(bytes("1"));
        uint256 chainId = block.chainid;
        address verifyingContract = address(portal);

        bytes32 expectedDomainSeparator = keccak256(
            abi.encode(
                typeHash,
                nameHash,
                versionHash,
                chainId,
                verifyingContract
            )
        );

        // Verify the domain separator matches our expected calculation
        assertEq(domainSeparator, expectedDomainSeparator);
    }

    function testDomainSeparatorV4ChainDependency() public {
        // Test that domain separator is dependent on chain ID by deploying on different chains
        bytes32 domainSeparator1 = portal.domainSeparatorV4();

        // Deploy a new Portal on a different chain ID
        vm.chainId(999);
        Portal portalDifferentChain = new Portal();
        bytes32 domainSeparator2 = portalDifferentChain.domainSeparatorV4();

        // Domain separators should be different on different chains
        assertNotEq(domainSeparator1, domainSeparator2);

        // Deploy another Portal on the original chain
        vm.chainId(1);
        Portal portalSameChain = new Portal();
        bytes32 domainSeparator3 = portalSameChain.domainSeparatorV4();

        // Domain separator should be different from the first portal due to different addresses
        // but should follow the same calculation pattern for the same chain
        assertNotEq(domainSeparator1, domainSeparator3);
        assertNotEq(domainSeparator2, domainSeparator3);
    }
}
