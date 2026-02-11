// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {Flywheel} from "../src/Flywheel.sol";
import {BuilderCodes} from "../src/BuilderCodes.sol";
import {SimpleRewards} from "../src/hooks/SimpleRewards.sol";
import {Campaign} from "../src/Campaign.sol";
import {DummyERC20} from "./mocks/DummyERC20.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/// @title RefCodeAllocationTest
/// @notice Demonstrates deterministic ref code to bytes32 key conversion for allocation tracking
contract RefCodeAllocationTest is Test {
    Flywheel public flywheel;
    BuilderCodes public builderCodes;
    SimpleRewards public simpleRewards;
    DummyERC20 public token;

    address public randoRecipient = makeAddr("randoRecipient");
    address public manager = makeAddr("manager");
    address public owner = makeAddr("owner");

    // Three builder ref codes
    string[3] public refCodes = ["builder1", "builder2", "builder3"];
    address[3] public refCodeOwners;
    bytes32[3] public refCodeKeys;

    function setUp() external {
        // Deploy contracts
        flywheel = new Flywheel();

        // Deploy upgradeable BuilderCodes with proxy
        BuilderCodes impl = new BuilderCodes();
        bytes memory initData = abi.encodeWithSelector(
            BuilderCodes.initialize.selector, address(this), address(this), "https://example.com/"
        );
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);
        builderCodes = BuilderCodes(address(proxy));

        token = new DummyERC20(new address[](0));
        simpleRewards = new SimpleRewards(address(flywheel));

        // Setup ref codes and calculate deterministic keys
        for (uint256 i = 0; i < 3; i++) {
            refCodeOwners[i] = makeAddr(string.concat("owner", vm.toString(i)));
            builderCodes.register(refCodes[i], refCodeOwners[i], refCodeOwners[i]);
            refCodeKeys[i] = bytes32(builderCodes.toTokenId(refCodes[i]));
        }
    }

    function test_optimalRefCodeToTokenIdToKeyConversion() external {
        console.log("=== Optimal RefCode -> TokenId -> Bytes32 Key Conversion ===");
        console.log("Using tokenId (uint256) as intermediate step is better than direct string hashing!");

        // Test bidirectional deterministic conversion
        for (uint256 i = 0; i < 3; i++) {
            console.log("");
            console.log("--- Builder", i + 1, "---");
            console.log("Input refCode:          ", refCodes[i]);

            // Forward: refCode → tokenId → bytes32 key (OPTIMAL PATH)
            uint256 tokenId = builderCodes.toTokenId(refCodes[i]);
            bytes32 key = bytes32(tokenId);

            console.log("Step 1 - toTokenId():   ", tokenId, "(validated & canonical)");
            console.log("Step 2 - bytes32():     ", vm.toString(key), "(gas-free cast)");

            assertEq(key, refCodeKeys[i], "Key should be deterministic");

            // Reverse: bytes32 key → tokenId → refCode (REVERSIBLE!)
            uint256 reversedTokenId = uint256(refCodeKeys[i]);
            string memory reversedRefCode = builderCodes.toCode(reversedTokenId);

            console.log("Reverse 1 - uint256():  ", reversedTokenId);
            console.log("Reverse 2 - toCode():   ", reversedRefCode, "(recovered original!)");
            console.log("Round-trip success:     ", keccak256(bytes(reversedRefCode)) == keccak256(bytes(refCodes[i])));

            assertEq(reversedRefCode, refCodes[i], "Reverse conversion should work");

            // Show alternative (suboptimal) approach for comparison
            bytes32 hashedKey = keccak256(abi.encodePacked(refCodes[i]));
            console.log("Alt: string hash:       ", vm.toString(hashedKey), "(NOT reversible)");
            assertTrue(key != hashedKey, "TokenId approach produces different (better) keys");
        }

        console.log("");
        console.log("=== TokenId approach wins: Reversible + Gas efficient + Protocol consistent! ===");
    }

    function test_simpleRewards_e2e() external {
        // Create campaign - SimpleRewards expects (owner, manager, uri) in hookData
        address campaign =
            flywheel.createCampaign(address(simpleRewards), 1, abi.encode(owner, manager, "Simple Campaign"));

        // Fund and activate
        token.mint(campaign, 1000e18);
        vm.prank(manager);
        flywheel.updateStatus(campaign, Flywheel.CampaignStatus.ACTIVE, "");

        // Create payouts for ref code owners
        uint256[3] memory amounts = [uint256(100e18), uint256(200e18), uint256(300e18)];
        Flywheel.Payout[] memory payouts = new Flywheel.Payout[](3);

        for (uint256 i = 0; i < 3; i++) {
            payouts[i] = Flywheel.Payout({
                recipient: refCodeOwners[i], // SimpleRewards uses recipient address
                amount: amounts[i],
                extraData: ""
            });
        }

        // Allocate (SimpleRewards uses bytes32(bytes20(recipient)) as key)
        vm.startPrank(manager);
        flywheel.allocate(campaign, address(token), abi.encode(payouts));

        // Builders can check allocations using recipient address keys
        for (uint256 i = 0; i < 3; i++) {
            bytes32 recipientKey = bytes32(bytes20(refCodeOwners[i]));
            uint256 pending = flywheel.allocatedPayout(campaign, address(token), recipientKey);
            assertEq(pending, amounts[i], "Should see correct allocation by recipient key");
        }

        // Distribute rewards
        flywheel.distribute(campaign, address(token), abi.encode(payouts));
        vm.stopPrank();

        // Verify final state
        for (uint256 i = 0; i < 3; i++) {
            assertEq(token.balanceOf(refCodeOwners[i]), amounts[i], "Should receive correct amount");

            bytes32 recipientKey = bytes32(bytes20(refCodeOwners[i]));
            uint256 pending = flywheel.allocatedPayout(campaign, address(token), recipientKey);
            assertEq(pending, 0, "No pending should remain");
        }
    }

    function test_refCodeKeyVsAddressKey() external {
        // Show difference between ref code keys and address keys
        for (uint256 i = 0; i < 3; i++) {
            bytes32 refCodeKey = refCodeKeys[i];
            bytes32 addressKey = bytes32(bytes20(refCodeOwners[i]));

            // These are different!
            assertTrue(refCodeKey != addressKey, "Ref code key should differ from address key");

            // Builders can calculate both deterministically
            bytes32 calculatedRefCodeKey = bytes32(builderCodes.toTokenId(refCodes[i]));
            bytes32 calculatedAddressKey = bytes32(bytes20(refCodeOwners[i]));

            assertEq(refCodeKey, calculatedRefCodeKey, "Ref code key should be deterministic");
            assertEq(addressKey, calculatedAddressKey, "Address key should be deterministic");
        }
    }

    function test_refCodeKeyUniqueness() external {
        // Verify each ref code produces unique key
        for (uint256 i = 0; i < 3; i++) {
            for (uint256 j = i + 1; j < 3; j++) {
                assertTrue(refCodeKeys[i] != refCodeKeys[j], "Each ref code should produce unique key");
            }
        }
    }

    function test_builderCanCalculateOwnKey() external {
        // Simulate builder checking their own allocation
        string memory myRefCode = "builder1";

        // Builder calculates their key deterministically
        bytes32 myKey = bytes32(builderCodes.toTokenId(myRefCode));

        // Verify it matches the pre-calculated key
        assertEq(myKey, refCodeKeys[0], "Builder should calculate correct key");

        // Builder can use this key to check pending payouts
        // (In real scenario, this would query actual flywheel.allocatedPayout)
    }

    function test_optimalCollectFeesHookWithRefCodeKeys() external {
        console.log("=== How Collect Fees Hook Could Use RefCode Keys (Optimal Method) ===");

        // 1. Current approach in existing hooks: use address as key
        address someAddress = refCodeOwners[0];
        bytes32 addressKey = bytes32(bytes20(someAddress));

        // 2. Optimal approach for fees hook: refCode -> tokenId -> bytes32 key
        string memory refCode = refCodes[0];
        uint256 tokenId = builderCodes.toTokenId(refCode);
        bytes32 refCodeKey = bytes32(tokenId);

        console.log("");
        console.log("Current hooks use ADDRESS keys:");
        console.log("  Address:     ", someAddress);
        console.log("  AddressKey:  ", vm.toString(addressKey));

        console.log("");
        console.log("Fee collection hook could use REFCODE keys (OPTIMAL PATH):");
        console.log("  RefCode:     ", refCode, "(human-readable)");
        console.log("  TokenId:     ", tokenId, "(validated canonical ID)");
        console.log("  RefCodeKey:  ", vm.toString(refCodeKey), "(gas-efficient cast)");

        console.log("");
        console.log("Keys are different:", addressKey != refCodeKey);
        console.log("RefCode keys are reversible, address keys are not!");

        // Show reversibility of refCode keys (advantage over address keys)
        string memory recoveredRefCode = builderCodes.toCode(uint256(refCodeKey));
        console.log("Recovered refCode:", recoveredRefCode, "(proves reversibility!)");

        // 3. Both are deterministic but serve different purposes:
        assertTrue(addressKey != refCodeKey, "Different key types for different use cases");
        assertEq(recoveredRefCode, refCode, "RefCode keys are fully reversible");

        console.log("");
        console.log("For fee collection by ref code, builders would:");
        console.log("1. Calculate key: bytes32(builderCodes.toTokenId(myRefCode))  // OPTIMAL");
        console.log("2. Check fees:    flywheel.allocatedFee(campaign, token, refCodeKey)");
        console.log("3. Collect fees:  Use same key in distributions");
        console.log("4. Recover code:  builderCodes.toCode(uint256(refCodeKey))  // If needed");
    }

    function test_refCodeKeysWithRandoRecipient() external {
        console.log("=== RefCode Keys with Different Recipient (Collect Fees Pattern) ===");
        console.log("Shows: Key (refCode) != Recipient (who gets paid)");

        // Demonstrate how allocations could be tracked by refCode keys
        // while payments go to a different recipient (like randoRecipient)

        uint256[3] memory amounts = [uint256(150e18), uint256(250e18), uint256(350e18)];

        console.log("");
        console.log("Allocation tracking by REF CODE keys:");

        for (uint256 i = 0; i < 3; i++) {
            // Calculate ref code key for tracking
            bytes32 refCodeKey = bytes32(builderCodes.toTokenId(refCodes[i]));

            console.log("RefCode:", refCodes[i]);
            console.log("  Key:      ", vm.toString(refCodeKey), "(for tracking)");
            console.log("  Amount:   ", amounts[i], "(allocated to this refCode)");
            console.log("  Recipient:", randoRecipient, "(who actually gets paid)");
            console.log("");

            // In a real collect fees hook, you would:
            // 1. Create Allocation with key=refCodeKey, amount=amounts[i]
            // 2. Create Distribution with key=refCodeKey, recipient=randoRecipient, amount=amounts[i]

            // This allows builders to check their allocations by refCode:
            // allocatedFee = flywheel.allocatedPayout(campaign, token, refCodeKey)

            // But all payments actually go to randoRecipient
        }

        console.log("=== This pattern enables: ===");
        console.log("1. Builders track earnings by their refCode");
        console.log("2. All payments flow to a central recipient (like treasury)");
        console.log("3. Key for tracking != Address for payment");
        console.log("4. Perfect for fee collection and revenue sharing!");

        // Verify each refCode produces unique keys (no collisions)
        bytes32 key1 = bytes32(builderCodes.toTokenId(refCodes[0]));
        bytes32 key2 = bytes32(builderCodes.toTokenId(refCodes[1]));
        bytes32 key3 = bytes32(builderCodes.toTokenId(refCodes[2]));

        assertTrue(key1 != key2 && key2 != key3 && key1 != key3, "All refCode keys must be unique");

        // Verify keys are different from recipient address key
        bytes32 recipientKey = bytes32(bytes20(randoRecipient));
        assertTrue(
            key1 != recipientKey && key2 != recipientKey && key3 != recipientKey,
            "RefCode keys must differ from recipient address key"
        );
    }
}
